import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import 'api_service.dart';

class MobileSyncService extends ChangeNotifier {
  static final MobileSyncService instance = MobileSyncService._internal();

  MobileSyncService._internal() {
    _initConnectivity();
  }

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();

  bool _isOnline = true;
  bool _isSyncing = false;
  int _pendingCount = 0;
  String? _lastSyncTimestamp;

  bool get isOnline => _isOnline;
  bool get isOffline => !_isOnline;
  bool get isSyncing => _isSyncing;
  int get pendingCount => _pendingCount;
  String? get lastSyncTimestamp => _lastSyncTimestamp;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  void _initConnectivity() async {
    final prefs = await SharedPreferences.getInstance();
    _lastSyncTimestamp = prefs.getString('last_mobile_catalog_sync');

    final results = await Connectivity().checkConnectivity();
    _updateConnectionStatus(results);

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      _updateConnectionStatus(results);
    });

    await refreshPendingCount();
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final hasConnection = results.any((r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet);

    final changed = _isOnline != hasConnection;
    _isOnline = hasConnection;

    if (changed) {
      notifyListeners();
      if (_isOnline) {
        debugPrint('[MOBILE-SYNC] Conexión recuperada. Evaluando auto-sincronización...');
        syncBatch();
      }
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  // ─── 1. DESCARGA Y CACHEO DE CATÁLOGO OFFLINE ──────────────────────────────

  Future<bool> downloadCatalog(int branchId) async {
    if (!_isOnline) return false;

    try {
      final response = await ApiService.get('/sync/catalog?branch_id=$branchId');
      if (response.statusCode != 200) {
        debugPrint('[MOBILE-SYNC] Error al descargar catálogo: ${response.statusCode}');
        return false;
      }

      final data = jsonDecode(response.body);
      final db = await _dbHelper.database;

      await db.transaction((txn) async {
        // Limpiar catálogo local
        await txn.delete('variants');
        await txn.delete('products');
        await txn.delete('categories');
        await txn.delete('customers');
        await txn.delete('branches');

        // Guardar sucursal
        await txn.insert('branches', {
          'id': data['branch_id'],
          'tenant_id': data['tenant_id'],
          'name': data['branch_name'],
          'address': 'Sucursal Sincronizada',
          'is_active': 1,
        });

        // Guardar categorías
        for (final cat in (data['categories'] as List? ?? [])) {
          await txn.insert('categories', {
            'id': cat['id'],
            'name': cat['name'],
            'description': cat['description'] ?? '',
          });
        }

        // Guardar productos y variantes con stock local
        for (final prod in (data['products'] as List? ?? [])) {
          await txn.insert('products', {
            'id': prod['id'],
            'tenant_id': data['tenant_id'],
            'name': prod['name'],
            'description': prod['description'] ?? '',
            'category_id': prod['category_id'],
            'category_name': prod['category_name'] ?? '',
            'base_price': (prod['base_price'] as num).toDouble(),
            'image_url': prod['image_url'],
            'is_active': 1,
          });

          for (final v in (prod['variants'] as List? ?? [])) {
            await txn.insert('variants', {
              'id': v['id'],
              'product_id': prod['id'],
              'sku': v['sku'],
              'size': v['size'],
              'color': v['color'],
              'price': (v['price'] as num).toDouble(),
              'stock': (v['stock'] as num).toInt(),
              'image_url': v['image_url'],
            });
          }
        }

        // Guardar clientes
        for (final cust in (data['customers'] as List? ?? [])) {
          await txn.insert('customers', {
            'id': cust['id'],
            'tenant_id': data['tenant_id'],
            'full_name': cust['full_name'] ?? cust['email'],
            'email': cust['email'],
            'phone': cust['phone'],
          });
        }
      });

      final now = DateTime.now().toUtc().toIso8601String();
      _lastSyncTimestamp = now;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_mobile_catalog_sync', now);
      await prefs.setInt('exchange_window_days', data['exchange_window_days'] ?? 30);

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[MOBILE-SYNC] Error en downloadCatalog: $e');
      return false;
    }
  }

  // ─── 2. CONSULTA DE CATÁLOGO DESDE SQLITE ─────────────────────────────────

  Future<List<Map<String, dynamic>>> getLocalProducts() async {
    final db = await _dbHelper.database;
    final products = await db.query('products', where: 'is_active = 1');
    final List<Map<String, dynamic>> result = [];

    for (final prod in products) {
      final variants = await db.query('variants', where: 'product_id = ?', whereArgs: [prod['id']]);
      final map = Map<String, dynamic>.from(prod);
      map['variants'] = variants;
      result.add(map);
    }

    return result;
  }

  Future<Map<String, dynamic>?> getLocalVariant(int variantId) async {
    final db = await _dbHelper.database;
    final res = await db.query('variants', where: 'id = ?', whereArgs: [variantId]);
    if (res.isNotEmpty) return res.first;
    return null;
  }

  // ─── 3. REGISTRO LOCAL DE VENTA OFFLINE ────────────────────────────────────

  Future<String> recordOfflineSale({
    required int branchId,
    int? userId,
    String? customerName,
    required String paymentMethod,
    required double totalAmount,
    required List<Map<String, dynamic>> items,
  }) async {
    final uuid = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final db = await _dbHelper.database;

    await db.transaction((txn) async {
      // 1. Descontar preventivamente inventario en SQLite
      for (final item in items) {
        final variantId = item['variant_id'] as int;
        final qty = item['quantity'] as int;

        final varList = await txn.query('variants', where: 'id = ?', whereArgs: [variantId]);
        if (varList.isNotEmpty) {
          final currentStock = varList.first['stock'] as int;
          final newStock = max(0, currentStock - qty);
          await txn.update('variants', {'stock': newStock}, where: 'id = ?', whereArgs: [variantId]);
        }
      }

      // 2. Registrar venta
      await txn.insert('sales', {
        'client_operation_uuid': uuid,
        'branch_id': branchId,
        'user_id': userId,
        'customer_name': customerName ?? 'Cliente Móvil',
        'payment_method': paymentMethod,
        'total_amount': totalAmount,
        'sync_status': 'PENDIENTE',
        'created_at': now,
      });

      // 3. Registrar ítems de venta
      for (final item in items) {
        await txn.insert('sale_items', {
          'client_operation_uuid': uuid,
          'variant_id': item['variant_id'],
          'quantity': item['quantity'],
          'unit_price': (item['unit_price'] as num).toDouble(),
          'product_name': item['product_name'] ?? '',
          'variant_label': item['variant_label'] ?? '',
        });
      }

      // 4. Encolar en sync_operations
      final payload = {
        'client_operation_uuid': uuid,
        'user_id': userId,
        'payment_method': paymentMethod,
        'total_amount': totalAmount,
        'created_at': now,
        'items': items.map((i) => {
          'variant_id': i['variant_id'],
          'quantity': i['quantity'],
          'unit_price': (i['unit_price'] as num).toDouble(),
        }).toList(),
      };

      await txn.insert('sync_operations', {
        'client_operation_uuid': uuid,
        'operation_type': 'sale',
        'payload': jsonEncode(payload),
        'status': 'PENDIENTE',
        'attempts': 0,
        'created_at': now,
        'updated_at': now,
      });
    });

    await refreshPendingCount();

    if (_isOnline) {
      syncBatch(branchId: branchId);
    }

    return uuid;
  }

  // ─── 4. REGISTRO LOCAL DE RESERVA OFFLINE ──────────────────────────────────

  Future<String> recordOfflineReservation({
    required int branchId,
    required int userId,
    String? customerName,
    String? pickupDate,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    final uuid = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final db = await _dbHelper.database;

    await db.transaction((txn) async {
      // 1. Retener preventivamente stock en SQLite
      for (final item in items) {
        final variantId = item['variant_id'] as int;
        final qty = item['quantity'] as int;

        final varList = await txn.query('variants', where: 'id = ?', whereArgs: [variantId]);
        if (varList.isNotEmpty) {
          final currentStock = varList.first['stock'] as int;
          final newStock = max(0, currentStock - qty);
          await txn.update('variants', {'stock': newStock}, where: 'id = ?', whereArgs: [variantId]);
        }
      }

      // 2. Insertar reserva
      await txn.insert('reservations', {
        'client_operation_uuid': uuid,
        'branch_id': branchId,
        'user_id': userId,
        'customer_name': customerName ?? 'Cliente Móvil',
        'pickup_date': pickupDate,
        'notes': notes,
        'sync_status': 'PENDIENTE',
        'created_at': now,
      });

      // 3. Insertar ítems
      for (final item in items) {
        await txn.insert('reservation_items', {
          'client_operation_uuid': uuid,
          'variant_id': item['variant_id'],
          'quantity': item['quantity'],
          'unit_price': (item['unit_price'] as num?)?.toDouble() ?? 0.0,
          'product_name': item['product_name'] ?? '',
          'variant_label': item['variant_label'] ?? '',
        });
      }

      // 4. Encolar en sync_operations
      final payload = {
        'client_operation_uuid': uuid,
        'user_id': userId,
        'pickup_date': pickupDate,
        'notes': notes,
        'items': items.map((i) => {
          'variant_id': i['variant_id'],
          'quantity': i['quantity'],
        }).toList(),
      };

      await txn.insert('sync_operations', {
        'client_operation_uuid': uuid,
        'operation_type': 'reservation',
        'payload': jsonEncode(payload),
        'status': 'PENDIENTE',
        'attempts': 0,
        'created_at': now,
        'updated_at': now,
      });
    });

    await refreshPendingCount();

    if (_isOnline) {
      syncBatch(branchId: branchId);
    }

    return uuid;
  }

  // ─── 5. PROCESAMIENTO POR LOTES CON REINTENTO EXPONENCIAL ──────────────────

  Future<Map<String, dynamic>?> syncBatch({int? branchId}) async {
    if (_isSyncing || !_isOnline) return null;

    final db = await _dbHelper.database;
    final pendingOps = await db.query(
      'sync_operations',
      where: "status IN ('PENDIENTE', 'RECHAZADA_CONFLICTO')",
    );

    if (pendingOps.isEmpty) {
      await refreshPendingCount();
      return null;
    }

    _isSyncing = true;
    notifyListeners();

    try {
      int targetBranchId = branchId ?? 1;
      final branches = await db.query('branches', limit: 1);
      if (branches.isNotEmpty) {
        targetBranchId = branches.first['id'] as int;
      }

      final List<Map<String, dynamic>> salesList = [];
      final List<Map<String, dynamic>> resList = [];

      for (final op in pendingOps) {
        final payload = jsonDecode(op['payload'] as String);
        if (op['operation_type'] == 'sale') {
          salesList.add(payload);
        } else if (op['operation_type'] == 'reservation') {
          resList.add(payload);
        }
      }

      // Marcar en estado ENVIANDO
      final now = DateTime.now().toUtc().toIso8601String();
      for (final op in pendingOps) {
        final attempts = (op['attempts'] as int? ?? 0) + 1;
        await db.update(
          'sync_operations',
          {'status': 'ENVIANDO', 'updated_at': now, 'attempts': attempts},
          where: 'client_operation_uuid = ?',
          whereArgs: [op['client_operation_uuid']],
        );
      }

      final body = {
        'branch_id': targetBranchId,
        'sales': salesList,
        'reservations': resList,
      };

      final response = await ApiService.post('/sync/operations', body);
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final responseData = jsonDecode(response.body);
      final receipts = responseData['receipts'] as List? ?? [];

      // Procesar recibos del servidor (CONFIRMADA o RECHAZADA_CONFLICTO)
      await db.transaction((txn) async {
        for (final receipt in receipts) {
          final uuid = receipt['client_operation_uuid'] as String;
          final status = receipt['status'] as String;
          final serverId = receipt['server_id'] as int?;
          final reason = receipt['rejection_reason'] as String?;
          final opType = receipt['operation_type'] as String;

          // Actualizar cola
          await txn.update(
            'sync_operations',
            {
              'status': status,
              'error_message': reason,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'client_operation_uuid = ?',
            whereArgs: [uuid],
          );

          if (opType == 'sale') {
            await txn.update(
              'sales',
              {
                'sync_status': status,
                'server_id': serverId,
                'rejection_reason': reason,
              },
              where: 'client_operation_uuid = ?',
              whereArgs: [uuid],
            );

            // Si fue rechazada por conflicto, restaurar inventario local
            if (status == 'RECHAZADA_CONFLICTO') {
              final items = await txn.query('sale_items', where: 'client_operation_uuid = ?', whereArgs: [uuid]);
              for (final it in items) {
                final vid = it['variant_id'] as int;
                final qty = it['quantity'] as int;
                final v = await txn.query('variants', where: 'id = ?', whereArgs: [vid]);
                if (v.isNotEmpty) {
                  final cur = v.first['stock'] as int;
                  await txn.update('variants', {'stock': cur + qty}, where: 'id = ?', whereArgs: [vid]);
                }
              }
            }
          } else if (opType == 'reservation') {
            await txn.update(
              'reservations',
              {
                'sync_status': status,
                'server_id': serverId,
                'rejection_reason': reason,
              },
              where: 'client_operation_uuid = ?',
              whereArgs: [uuid],
            );

            if (status == 'RECHAZADA_CONFLICTO') {
              final items = await txn.query('reservation_items', where: 'client_operation_uuid = ?', whereArgs: [uuid]);
              for (final it in items) {
                final vid = it['variant_id'] as int;
                final qty = it['quantity'] as int;
                final v = await txn.query('variants', where: 'id = ?', whereArgs: [vid]);
                if (v.isNotEmpty) {
                  final cur = v.first['stock'] as int;
                  await txn.update('variants', {'stock': cur + qty}, where: 'id = ?', whereArgs: [vid]);
                }
              }
            }
          }
        }
      });

      debugPrint('[MOBILE-SYNC] Sincronización exitosa: ${responseData['confirmed_count']} confirmadas, ${responseData['conflict_count']} conflictos.');
      return responseData;
    } catch (e) {
      debugPrint('[MOBILE-SYNC] Error en syncBatch: $e');
      // RNF03: PROHIBIDO borrar operaciones locales en fallo de envío
      for (final op in pendingOps) {
        await db.update(
          'sync_operations',
          {
            'status': 'PENDIENTE',
            'error_message': e.toString(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'client_operation_uuid = ?',
          whereArgs: [op['client_operation_uuid']],
        );
      }
      return null;
    } finally {
      _isSyncing = false;
      await refreshPendingCount();
    }
  }

  // ─── 6. CONSULTAS Y HISTORIAL ─────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getSyncHistory() async {
    final db = await _dbHelper.database;
    return await db.query('sync_operations', orderBy: 'created_at DESC');
  }

  Future<int> refreshPendingCount() async {
    final db = await _dbHelper.database;
    final res = await db.rawQuery(
      "SELECT COUNT(*) as count FROM sync_operations WHERE status IN ('PENDIENTE', 'RECHAZADA_CONFLICTO', 'ENVIANDO')",
    );
    _pendingCount = Sqflite.firstIntValue(res) ?? 0;
    notifyListeners();
    return _pendingCount;
  }
}
