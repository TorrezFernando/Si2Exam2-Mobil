import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import 'api_service.dart';

import 'package:http/http.dart' as http;

class InsufficientStockException implements Exception {
  final String message;
  InsufficientStockException(this.message);
  @override
  String toString() => message;
}

class ValidationException implements Exception {
  final String message;
  ValidationException(this.message);
  @override
  String toString() => message;
}

class MobileSyncService extends ChangeNotifier {
  static final instance = MobileSyncService._();
  MobileSyncService._() : _helper = DatabaseHelper.instance {
    _initConnectivity();
  }
  MobileSyncService.forTesting(this._helper) {
    _online = false;
  }
  final DatabaseHelper _helper;
  Future<http.Response> Function(String, String) getRequest = (path, token) =>
      ApiService.get(path, sessionToken: token);
  Future<http.Response> Function(String, Map<String, dynamic>, String)
  postRequest = (path, body, token) =>
      ApiService.post(path, body, sessionToken: token);
  Future<void> ready = Future.value();
  @visibleForTesting
  void setOnline(bool online) {
    _online = online;
  }

  Map<String, dynamic>? _profile;
  String? _token;
  int _generation = 0;
  bool _online = true, _busy = false, _paused = false;
  int _pending = 0;
  String? _timestamp;
  String? message;
  bool legacyData = false;
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool get isOnline => _online;
  bool get isOffline => !_online;
  bool get isSyncing => _busy;
  int get pendingCount => _pending;
  String? get lastSyncTimestamp => _timestamp;
  int? get tenantId => _profile?['tenant_id'] as int?;
  int? get ownerId => _profile?['id'] as int?;
  int? get assignedBranch => _profile?['branch_id'] as int?;
  bool get hasSession => tenantId != null && ownerId != null && _token != null;
  Set<String> get permissions {
    final result = <String>{};
    for (final p in (_profile?['role']?['permissions'] as List? ?? [])) {
      result.add(p['name'] as String);
    }
    for (final p in (_profile?['user_permissions'] as List? ?? [])) {
      final name = p['permission']['name'] as String;
      if (p['is_granted'] == true) {
        result.add(name);
      } else {
        result.remove(name);
      }
    }
    return result;
  }

  bool get canSell => permissions.contains('sales:write');

  void setSession(Map<String, dynamic>? profile, String? token) {
    final same =
        _token == token &&
        tenantId == profile?['tenant_id'] &&
        ownerId == profile?['id'];
    _profile = profile;
    _token = token;
    if (same) return;
    _generation++;
    _paused = false;
    _pending = 0;
    _timestamp = null;
    message = null;
    _helper.setScope(tenantId, ownerId);
    if (hasSession) {
      ready = _resume(_generation);
    }
  }

  Future<void> _resume(int generation) async {
    try {
      final db = await _helper.database;
      if (generation != _generation) return;
      await db.transaction((txn) async {
        await txn.update('sync_operations', {
          'status': 'PENDIENTE',
        }, where: "status = 'ENVIANDO'");
        for (final table in ['sales', 'reservations']) {
          await txn.update(table, {
            'sync_status': 'PENDIENTE',
          }, where: "sync_status = 'ENVIANDO'");
        }
      });
      final meta = await db.query('cache_metadata');
      if (generation != _generation) return;
      _timestamp = meta.isEmpty
          ? null
          : meta.first['server_timestamp'] as String;
      legacyData = await _helper.hasLegacyData();
      await refreshPendingCount();
      await syncBatch();
    } catch (e) {
      message = 'No se pudo abrir el almacenamiento: $e';
      notifyListeners();
    }
  }

  void _initConnectivity() async {
    try {
      void update(List<ConnectivityResult> values) {
        _online = values.any((r) => r != ConnectivityResult.none);
        notifyListeners();
        if (_online && hasSession) {
          unawaited(syncBatch());
        }
      }

      update(await Connectivity().checkConnectivity());
      _subscription = Connectivity().onConnectivityChanged.listen(update);
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (hasSession && !_busy && !_paused && _online) {
          unawaited(syncBatch());
        }
      });
    } catch (e) {
      debugPrint('Conectividad no disponible: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  void _requireContext({int? tenant, int? owner}) {
    if (!hasSession ||
        (tenant != null && tenant != tenantId) ||
        (owner != null && owner != ownerId)) {
      throw ValidationException(
        'Inicia sesión con la cuenta propietaria de estos datos.',
      );
    }
  }

  Future<bool> downloadCatalog(int branchId) async {
    _requireContext();
    if (!_online || _busy || _paused) return false;
    // Drain/reconcile uncertain sends before obtaining a stock snapshot. If any
    // operation remains unresolved, keep the existing stock instead of rebasing it.
    await syncBatch();
    if (_busy || !hasSession) return false;
    _busy = true;
    final gen = _generation, tenant = tenantId;
    final token = _token!;
    try {
      final db = await _helper.database;
      if (gen != _generation) return false;
      final unresolved =
          Sqflite.firstIntValue(
            await db.rawQuery(
              "SELECT COUNT(*) FROM sync_operations WHERE status IN ('PENDIENTE','ENVIANDO')",
            ),
          ) ??
          0;
      if (unresolved != 0) {
        message = 'Resuelve los envíos pendientes antes de actualizar o cambiar el catálogo.';
        return false;
      }
      final response = await getRequest(
        '/sync/catalog?branch_id=$branchId',
        token,
      );
      if (response.statusCode != 200) {
        message = 'No se pudo descargar el catálogo (${response.statusCode}).';
        return false;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (gen != _generation ||
          data['tenant_id'] != tenant ||
          data['branch_id'] != branchId)
        return false;
      await db.transaction((txn) async {
        // Preserve referenced historical variants and branches; no destructive replace.
        await txn.update('products', {'is_active': 0});
        await txn.update('variants', {'stock': 0});
        Future<void> put(String table, Map<String, dynamic> row) async {
          final exists = await txn.update(
            table,
            row,
            where: 'id = ?',
            whereArgs: [row['id']],
          );
          if (exists == 0) await txn.insert(table, row);
        }

        await put('branches', {
          'id': branchId,
          'tenant_id': tenant,
          'name': data['branch_name'],
          'address': '',
          'is_active': 1,
        });
        for (final c in data['categories'] as List) {
          await put('categories', {
            'id': c['id'],
            'name': c['name'],
            'description': c['description'],
          });
        }
        for (final p in data['products'] as List) {
          await put('products', {
            'id': p['id'],
            'tenant_id': tenant,
            'name': p['name'],
            'description': p['description'],
            'category_id': p['category_id'],
            'category_name': p['category_name'],
            'base_price': p['base_price'],
            'image_url': p['image_url'],
            'is_active': 1,
          });
          for (final v in p['variants'] as List) {
            await put('variants', {
              'id': v['id'],
              'product_id': p['id'],
              'sku': v['sku'],
              'size': v['size'],
              'color': v['color'],
              'price': v['price'],
              'stock': v['stock'],
              'image_url': v['image_url'],
            });
          }
        }
        await txn.delete('customers');
        for (final c in data['customers'] as List) {
          await put('customers', {
            'id': c['id'],
            'tenant_id': tenant,
            'full_name': c['full_name'],
            'email': c['email'],
            'phone': c['phone'],
          });
        }
        await txn.delete('cache_metadata');
        await txn.insert('cache_metadata', {
          'id': 1,
          'branch_id': branchId,
          'server_timestamp': data['server_timestamp'],
        });
      });
      if (gen == _generation) {
        _timestamp = data['server_timestamp'];
        message = null;
      }
      return true;
    } catch (e) {
      message = 'Catálogo sin actualizar: $e';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<int?> cachedBranch() async {
    _requireContext();
    final rows = await (await _helper.database).query('cache_metadata');
    return rows.isEmpty ? null : rows.first['branch_id'] as int;
  }

  Future<List<Map<String, dynamic>>> getLocalProducts() async {
    _requireContext();
    final db = await _helper.database;
    final products = await db.query('products', where: 'is_active = 1');
    return Future.wait(
      products.map(
        (p) async => {
          ...p,
          'variants': await db.query(
            'variants',
            where: 'product_id = ?',
            whereArgs: [p['id']],
          ),
        },
      ),
    );
  }

  Future<Map<String, dynamic>?> getLocalVariant(int id) async {
    _requireContext();
    final rows = await (await _helper.database).query(
      'variants',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<String> recordOfflineSale({
    required int branchId,
    int? tenantId,
    int? userId,
    String? customerName,
    required String paymentMethod,
    required double totalAmount,
    required List<Map<String, dynamic>> items,
    bool cashConfirmed = false,
  }) {
    if (!canSell || !cashConfirmed || paymentMethod != 'efectivo') {
      throw ValidationException(
        'La caja offline requiere permiso de venta y confirmación de efectivo cobrado.',
      );
    }
    return _record(
      'sale',
      branchId,
      tenantId,
      userId ?? ownerId,
      customerName,
      items,
      total: totalAmount,
      payment: paymentMethod,
    );
  }

  Future<String> recordOfflineReservation({
    required int branchId,
    int? tenantId,
    required int userId,
    String? customerName,
    String? pickupDate,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) {
    if (userId != ownerId && !permissions.contains('reservations:write')) {
      throw ValidationException('Solo puedes reservar para ti mismo.');
    }
    return _record(
      'reservation',
      branchId,
      tenantId,
      userId,
      customerName,
      items,
      pickup: pickupDate,
      notes: notes,
    );
  }

  Future<String> _record(
    String type,
    int branch,
    int? tenant,
    int? customer,
    String? name,
    List<Map<String, dynamic>> items, {
    double? total,
    String? payment,
    String? pickup,
    String? notes,
  }) async {
    _requireContext(tenant: tenant);
    final expiry = _profile?['_offline_valid_until'] as String?;
    if (expiry == null || !DateTime.parse(expiry).isAfter(DateTime.now()))
      throw ValidationException(
        'Revalida tu sesión online para registrar operaciones offline (vigencia: 24 horas).',
      );
    if (_busy)
      throw ValidationException(
        'Espera a que termine la sincronización o actualización.',
      );
    _busy = true;
    final gen = _generation, currentTenant = tenantId!, owner = ownerId!;
    try {
      if (customer == null || customer <= 0 || items.isEmpty)
        throw ValidationException('Cliente y prendas requeridos.');
      if (pickup != null && !DateTime.parse(pickup).isAfter(DateTime.now()))
        throw ValidationException('El horario de retiro debe ser futuro.');
      final db = await _helper.database;
      if (gen != _generation) throw ValidationException('La sesión cambió.');
      final uuid = const Uuid().v4(),
          now = DateTime.now().toUtc().toIso8601String();
      final counts = <int, int>{};
      for (final item in items) {
        final id = item['variant_id'], qty = item['quantity'];
        if (id is! int || id <= 0 || qty is! int || qty <= 0)
          throw ValidationException(
            'Variante y cantidad entera positiva requeridas.',
          );
        counts[id] = (counts[id] ?? 0) + qty;
      }
      await db.transaction((txn) async {
        final meta = await txn.query('cache_metadata');
        if (meta.isEmpty || meta.first['branch_id'] != branch)
          throw ValidationException(
            'Descarga primero el catálogo de la sucursal seleccionada.',
          );
        int cents = 0;
        for (final entry in counts.entries) {
          final variants = await txn.rawQuery(
            'SELECT v.* FROM variants v JOIN products p ON p.id=v.product_id WHERE v.id=? AND p.is_active=1',
            [entry.key],
          );
          if (variants.isEmpty)
            throw ValidationException('Variante no disponible en el catálogo.');
          final v = variants.first;
          if ((v['stock'] as int) < entry.value)
            throw InsufficientStockException(
              'Stock local insuficiente para variante ${entry.key}.',
            );
          cents += ((v['price'] as num).toDouble() * 100).round() * entry.value;
          for (final item in items.where((i) => i['variant_id'] == entry.key)) {
            if (type == 'sale' &&
                ((item['unit_price'] as num).toDouble() * 100).round() !=
                    ((v['price'] as num).toDouble() * 100).round())
              throw ValidationException(
                'El precio del carrito cambió; vuelve a cargar la prenda.',
              );
          }
          await txn.rawUpdate('UPDATE variants SET stock=stock-? WHERE id=?', [
            entry.value,
            entry.key,
          ]);
        }
        if (type == 'sale' &&
            (total == null ||
                !total.isFinite ||
                (total * 100).round() != cents))
          throw ValidationException('Importe de caja inconsistente.');
        final table = type == 'sale' ? 'sales' : 'reservations';
        final header = <String, dynamic>{
          'client_operation_uuid': uuid,
          'tenant_id': currentTenant,
          'user_id': customer,
          'branch_id': branch,
          'customer_name': name,
          'created_at': now,
        };
        if (type == 'sale') {
          header.addAll({
            'payment_method': payment,
            'total_amount': cents / 100,
          });
        } else {
          header.addAll({'pickup_date': pickup, 'notes': notes});
        }
        await txn.insert(table, header);
        for (final i in items) {
          await txn.insert(
            type == 'sale' ? 'sale_items' : 'reservation_items',
            {
              'client_operation_uuid': uuid,
              'variant_id': i['variant_id'],
              'quantity': i['quantity'],
              'unit_price': i['unit_price'] ?? 0,
              'product_name': i['product_name'],
              'variant_label': i['variant_label'],
            },
          );
        }
        final payload = <String, dynamic>{
          'client_operation_uuid': uuid,
          'user_id': customer,
          'items': items
              .map(
                (i) => {
                  'variant_id': i['variant_id'],
                  'quantity': i['quantity'],
                  if (type == 'sale') 'unit_price': i['unit_price'],
                },
              )
              .toList(),
        };
        if (type == 'sale') {
          payload.addAll({
            'payment_method': payment,
            'total_amount': cents / 100,
            'created_at': now,
          });
        } else {
          payload.addAll({'pickup_date': pickup, 'notes': notes});
        }
        await txn.insert('sync_operations', {
          'client_operation_uuid': uuid,
          'tenant_id': currentTenant,
          'user_id': owner,
          'branch_id': branch,
          'operation_type': type,
          'payload': jsonEncode(payload),
          'created_at': now,
          'updated_at': now,
          type == 'sale' ? 'sale_uuid' : 'reservation_uuid': uuid,
        });
      });
      return uuid;
    } finally {
      _busy = false;
      await refreshPendingCount();
      if (_online) unawaited(syncBatch());
    }
  }

  Future<Map<String, dynamic>?> syncBatch({
    int? branchId,
    int? tenantId,
    int? userId,
    bool manual = false,
  }) async {
    if (!hasSession || _busy || !_online || _paused) return null;
    _requireContext(tenant: tenantId, owner: userId);
    _busy = true;
    final gen = _generation, token = _token!;
    final receiptsAll = <dynamic>[];
    try {
      final db = await _helper.database;
      if (gen != _generation) return null;
      if (manual)
        await db.update('sync_operations', {
          'blocked': 0,
          'next_retry_at': null,
        }, where: "status='PENDIENTE'");
      final pending = await db.query(
        'sync_operations',
        where: "status='PENDIENTE' AND blocked=0",
      );
      final groups = <int, List<Map<String, dynamic>>>{};
      for (final op in pending) {
        if (branchId != null && op['branch_id'] != branchId) continue;
        final next = op['next_retry_at'] as String?;
        if (next != null && DateTime.parse(next).isAfter(DateTime.now()))
          continue;
        groups.putIfAbsent(op['branch_id'] as int, () => []).add(op);
      }
      for (final entry in groups.entries) {
        if (gen != _generation) break;
        final ops = entry.value, now = DateTime.now().toUtc().toIso8601String();
        var blocked = false;
        try {
          final body = <String, dynamic>{
            'branch_id': entry.key,
            'sales': <dynamic>[],
            'reservations': <dynamic>[],
          };
          for (final op in ops) {
            (body[op['operation_type'] == 'sale' ? 'sales' : 'reservations']
                    as List)
                .add(jsonDecode(op['payload'] as String));
          }
          await db.transaction((txn) async {
            for (final op in ops) {
              final id = op['client_operation_uuid'];
              await txn.update(
                'sync_operations',
                {
                  'status': 'ENVIANDO',
                  'last_attempt_at': now,
                  'attempts': (op['attempts'] as int) + 1,
                },
                where: 'client_operation_uuid=?',
                whereArgs: [id],
              );
              await txn.update(
                op['operation_type'] == 'sale' ? 'sales' : 'reservations',
                {'sync_status': 'ENVIANDO'},
                where: 'client_operation_uuid=?',
                whereArgs: [id],
              );
            }
          });
          final response = await postRequest('/sync/operations', body, token);
          if (response.statusCode != 200) {
            if (response.statusCode == 401) _paused = gen == _generation;
            blocked = [400, 403, 409, 422].contains(response.statusCode);
            throw ValidationException(
              response.statusCode == 401
                  ? 'Vuelve a iniciar sesión para sincronizar.'
                  : 'Sincronización HTTP ${response.statusCode}; ${blocked ? 'requiere revisión, se conservan los datos' : 'se reintentará'}.',
            );
          }
          if (gen != _generation)
            throw ValidationException(
              'La sesión cambió; se conciliará con su cuenta original.',
            );
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final receipts = data['receipts'] as List;
          final expected = {
            for (final op in ops)
              op['client_operation_uuid']: op['operation_type'],
          };
          final seen = <String>{};
          for (final r in receipts) {
            final id = r['client_operation_uuid'] as String;
            if (expected[id] != r['operation_type'] ||
                !seen.add(id) ||
                !['CONFIRMADA', 'RECHAZADA_CONFLICTO'].contains(r['status']) ||
                (r['status'] == 'CONFIRMADA' && r['server_id'] is! int))
              throw ValidationException(
                'Recibo inválido; se conserva el lote para conciliación.',
              );
          }
          if (seen.length != expected.length)
            throw ValidationException(
              'Faltan recibos del lote; se reintentará con los mismos UUID.',
            );
          await db.transaction((txn) async {
            for (final r in receipts) {
              final id = r['client_operation_uuid'],
                  state = r['status'],
                  sale = r['operation_type'] == 'sale';
              final previous = await txn.query(
                'sync_operations',
                where: 'client_operation_uuid=?',
                whereArgs: [id],
              );
              final wasPending = [
                'PENDIENTE',
                'ENVIANDO',
              ].contains(previous.single['status']);
              if (!wasPending) continue;
              await txn.update(
                'sync_operations',
                {
                  'status': state,
                  'error_message': r['rejection_reason'],
                  'updated_at': now,
                },
                where: 'client_operation_uuid=?',
                whereArgs: [id],
              );
              await txn.update(
                sale ? 'sales' : 'reservations',
                {
                  'sync_status': state,
                  'server_id': r['server_id'],
                  'rejection_reason': r['rejection_reason'],
                },
                where: 'client_operation_uuid=?',
                whereArgs: [id],
              );
              if (state == 'RECHAZADA_CONFLICTO') {
                final items = await txn.query(
                  sale ? 'sale_items' : 'reservation_items',
                  where: 'client_operation_uuid=?',
                  whereArgs: [id],
                );
                for (final item in items) {
                  await txn.rawUpdate(
                    'UPDATE variants SET stock=stock+? WHERE id=?',
                    [item['quantity'], item['variant_id']],
                  );
                }
              }
            }
          });
          receiptsAll.addAll(receipts);
        } catch (e) {
          await db.transaction((txn) async {
            for (final op in ops) {
              final seconds =
                  min(
                    300,
                    3 * pow(2, min(8, (op['attempts'] as int) + 1)).toInt(),
                  ) +
                  Random().nextInt(4);
              await txn.update(
                'sync_operations',
                {
                  'status': 'PENDIENTE',
                  'blocked': blocked ? 1 : 0,
                  'error_message': e.toString(),
                  'next_retry_at': DateTime.now()
                      .toUtc()
                      .add(Duration(seconds: seconds))
                      .toIso8601String(),
                },
                where: "client_operation_uuid=? AND status IN ('PENDIENTE','ENVIANDO')",
                whereArgs: [op['client_operation_uuid']],
              );
              await txn.update(
                op['operation_type'] == 'sale' ? 'sales' : 'reservations',
                {'sync_status': 'PENDIENTE'},
                where: "client_operation_uuid=? AND sync_status='ENVIANDO'",
                whereArgs: [op['client_operation_uuid']],
              );
            }
          });
          if (gen == _generation) message = e.toString();
          if (_paused) break;
        }
      }
      final confirmed = receiptsAll
          .where((r) => r['status'] == 'CONFIRMADA')
          .length;
      return {
        'total_processed': receiptsAll.length,
        'confirmed_count': confirmed,
        'conflict_count': receiptsAll.length - confirmed,
        'receipts': receiptsAll,
      };
    } catch (e) {
      if (gen == _generation) message = 'No se pudo sincronizar: $e';
      return null;
    } finally {
      _busy = false;
      await refreshPendingCount();
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> getSyncHistory({
    int? tenantId,
    int? userId,
  }) async {
    if (!hasSession) return [];
    _requireContext(tenant: tenantId, owner: userId);
    return (await _helper.database).query(
      'sync_operations',
      orderBy: 'created_at DESC',
    );
  }

  Future<int> refreshPendingCount({int? tenantId, int? userId}) async {
    if (!hasSession) {
      _pending = 0;
      return 0;
    }
    final gen = _generation;
    try {
      _requireContext(tenant: tenantId, owner: userId);
      final db = await _helper.database;
      final count =
          Sqflite.firstIntValue(
            await db.rawQuery(
              "SELECT COUNT(*) FROM sync_operations WHERE status IN ('PENDIENTE','ENVIANDO')",
            ),
          ) ??
          0;
      if (gen == _generation) {
        _pending = count;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Contador offline: $e');
    }
    return _pending;
  }
}
