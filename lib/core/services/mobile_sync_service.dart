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
  Timer? _backoffTimer;

  void _initConnectivity() async {
    final prefs = await SharedPreferences.getInstance();
    _lastSyncTimestamp = prefs.getString('last_mobile_catalog_sync');

    // 1. Recuperar operaciones huérfanas en estado 'ENVIANDO' tras cierre abrupto
    try {
      final db = await _dbHelper.database;
      await db.update('sync_operations', {'status': 'PENDIENTE'}, where: "status = 'ENVIANDO'");
      await db.update('sales', {'sync_status': 'PENDIENTE'}, where: "sync_status = 'ENVIANDO'");
      await db.update('reservations', {'sync_status': 'PENDIENTE'}, where: "sync_status = 'ENVIANDO'");
    } catch (e) {
      debugPrint('[MOBILE-SYNC] Error recuperando operaciones ENVIANDO al inicio: $e');
    }

    final results = await Connectivity().checkConnectivity();
    _updateConnectionStatus(results);

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      _updateConnectionStatus(results);
    });

    // Iniciar temporizador periódico para backoff exponencial y reintentos
    _backoffTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isOnline && !_isSyncing) {
        syncBatch();
      }
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
    _backoffTimer?.cancel();
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
      final int tenantId = data['tenant_id'] ?? 1;

      await db.transaction((txn) async {
        // Limpiar catálogo previo de productos y variantes
        await txn.delete('variants');
        await txn.delete('products');
        await txn.delete('categories');
        await txn.delete('customers');
        await txn.delete('branches');

        // Guardar sucursal
        await txn.insert('branches', {
          'id': data['branch_id'],
          'tenant_id': tenantId,
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
            'tenant_id': tenantId,
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

        // Guardar clientes autorizados
        for (final cust in (data['customers'] as List? ?? [])) {
          await txn.insert('customers', {
            'id': cust['id'],
            'tenant_id': tenantId,
            'full_name': cust['full_name'] ?? cust['email'],
            'email': cust['email'],
            'phone': cust['phone'],
          });
        }

        // Preservar descuento preventivo de operaciones pendientes/enviando locales
        final pendingOps = await txn.query(
          'sync_operations',
          where: "status IN ('PENDIENTE', 'ENVIANDO') AND branch_id = ?",
          whereArgs: [data['branch_id']],
        );

        for (final op in pendingOps) {
          try {
            final payload = jsonDecode(op['payload'] as String);
            final items = payload['items'] as List? ?? [];
            for (final it in items) {
              final vid = it['variant_id'] as int;
              final qty = (it['quantity'] as num).toInt();
              final v = await txn.query('variants', where: 'id = ?', whereArgs: [vid]);
              if (v.isNotEmpty) {
                final cur = v.first['stock'] as int;
                final newStock = max(0, cur - qty);
                await txn.update('variants', {'stock': newStock}, where: 'id = ?', whereArgs: [vid]);
              }
            }
          } catch (e) {
            debugPrint('[MOBILE-SYNC] Error re-aplicando deducción preventiva: $e');
          }
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

  // ─── 3. REGISTRO LOCAL DE VENTA OFFLINE (CON VALIDACIÓN ESTRICTA) ──────────

  Future<String> recordOfflineSale({
    required int branchId,
    int? tenantId,
    int? userId,
    String? customerName,
    required String paymentMethod,
    required double totalAmount,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) {
      throw ValidationException('No hay prendas seleccionadas para la venta.');
    }

    // 1. Validar y agrupar cantidades por variante
    final Map<int, int> variantTotals = {};
    for (final item in items) {
      final vid = item['variant_id'] as int?;
      final qty = (item['quantity'] as num?)?.toInt() ?? 0;
      if (vid == null || vid <= 0 || qty <= 0) {
        throw ValidationException('La variante $vid o cantidad $qty es inválida.');
      }
      variantTotals[vid] = (variantTotals[vid] ?? 0) + qty;
    }

    final uuid = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final db = await _dbHelper.database;

    final actualTenantId = tenantId ?? 1;
    final actualUserId = userId ?? 1;

    await db.transaction((txn) async {
      // 2. Verificar existencia y suficiencia de stock local para TODAS las líneas
      for (final entry in variantTotals.entries) {
        final vid = entry.key;
        final reqQty = entry.value;

        final varList = await txn.query('variants', where: 'id = ?', whereArgs: [vid]);
        if (varList.isEmpty) {
          throw ValidationException('La variante ID $vid no existe en la base de datos local.');
        }
        final currentStock = varList.first['stock'] as int;
        if (currentStock < reqQty) {
          throw InsufficientStockException(
            'Stock local insuficiente para la variante ID $vid. Disponible: $currentStock, Solicitado: $reqQty',
          );
        }
      }

      // 3. Descontar stock local exacto
      for (final entry in variantTotals.entries) {
        final vid = entry.key;
        final reqQty = entry.value;
        final varList = await txn.query('variants', where: 'id = ?', whereArgs: [vid]);
        final currentStock = varList.first['stock'] as int;
        await txn.update('variants', {'stock': currentStock - reqQty}, where: 'id = ?', whereArgs: [vid]);
      }

      // 4. Registrar cabecera de venta
      await txn.insert('sales', {
        'client_operation_uuid': uuid,
        'tenant_id': actualTenantId,
        'branch_id': branchId,
        'user_id': actualUserId,
        'customer_name': customerName ?? 'Cliente Móvil',
        'payment_method': paymentMethod,
        'total_amount': totalAmount,
        'sync_status': 'PENDIENTE',
        'created_at': now,
      });

      // 5. Registrar detalles
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

      // 6. Encolar en sync_operations con contexto completo
      final payload = {
        'client_operation_uuid': uuid,
        'user_id': actualUserId,
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
        'tenant_id': actualTenantId,
        'user_id': actualUserId,
        'branch_id': branchId,
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
      syncBatch(branchId: branchId, tenantId: actualTenantId, userId: actualUserId);
    }

    return uuid;
  }

  // ─── 4. REGISTRO LOCAL DE RESERVA OFFLINE ──────────────────────────────────

  Future<String> recordOfflineReservation({
    required int branchId,
    int? tenantId,
    required int userId,
    String? customerName,
    String? pickupDate,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) {
      throw ValidationException('No hay prendas seleccionadas para la reserva.');
    }

    final Map<int, int> variantTotals = {};
    for (final item in items) {
      final vid = item['variant_id'] as int?;
      final qty = (item['quantity'] as num?)?.toInt() ?? 0;
      if (vid == null || vid <= 0 || qty <= 0) {
        throw ValidationException('La variante $vid o cantidad $qty es inválida.');
      }
      variantTotals[vid] = (variantTotals[vid] ?? 0) + qty;
    }

    final uuid = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final db = await _dbHelper.database;
    final actualTenantId = tenantId ?? 1;

    await db.transaction((txn) async {
      // 1. Validar existencia y stock
      for (final entry in variantTotals.entries) {
        final vid = entry.key;
        final reqQty = entry.value;

        final varList = await txn.query('variants', where: 'id = ?', whereArgs: [vid]);
        if (varList.isEmpty) {
          throw ValidationException('La variante ID $vid no existe en la base de datos local.');
        }
        final currentStock = varList.first['stock'] as int;
        if (currentStock < reqQty) {
          throw InsufficientStockException(
            'Stock local insuficiente para reservar variante ID $vid. Disponible: $currentStock, Solicitado: $reqQty',
          );
        }
      }

      // 2. Retener preventivamente stock en SQLite
      for (final entry in variantTotals.entries) {
        final vid = entry.key;
        final reqQty = entry.value;
        final varList = await txn.query('variants', where: 'id = ?', whereArgs: [vid]);
        final currentStock = varList.first['stock'] as int;
        await txn.update('variants', {'stock': currentStock - reqQty}, where: 'id = ?', whereArgs: [vid]);
      }

      // 3. Insertar reserva
      await txn.insert('reservations', {
        'client_operation_uuid': uuid,
        'tenant_id': actualTenantId,
        'branch_id': branchId,
        'user_id': userId,
        'customer_name': customerName ?? 'Cliente Móvil',
        'pickup_date': pickupDate,
        'notes': notes,
        'sync_status': 'PENDIENTE',
        'created_at': now,
      });

      // 4. Insertar ítems
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

      // 5. Encolar en sync_operations
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
        'tenant_id': actualTenantId,
        'user_id': userId,
        'branch_id': branchId,
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
      syncBatch(branchId: branchId, tenantId: actualTenantId, userId: userId);
    }

    return uuid;
  }

  // ─── 5. PROCESAMIENTO POR LOTES CON EXPONENTIAL BACKOFF Y SUITE DE SUCURSAL ─

  Future<Map<String, dynamic>?> syncBatch({int? branchId, int? tenantId, int? userId}) async {
    // Adquisición atómica del lock antes de cualquier llamada asíncrona
    if (_isSyncing || !_isOnline) return null;
    _isSyncing = true;
    notifyListeners();

    final db = await _dbHelper.database;
    try {
      // 1. Consultar exclusivamente operaciones en estado 'PENDIENTE'
      String whereClause = "status = 'PENDIENTE'";
      final List<dynamic> whereArgs = [];

      if (tenantId != null) {
        whereClause += " AND tenant_id = ?";
        whereArgs.add(tenantId);
      }
      if (userId != null) {
        whereClause += " AND user_id = ?";
        whereArgs.add(userId);
      }

      final pendingOps = await db.query(
        'sync_operations',
        where: whereClause,
        whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      );

      if (pendingOps.isEmpty) {
        return null;
      }

      final now = DateTime.now();

      // 2. Filtrar por backoff exponencial si next_retry_at está en el futuro
      final eligibleOps = pendingOps.where((op) {
        final nextRetry = op['next_retry_at'] as String?;
        if (nextRetry == null) return true;
        try {
          return now.isAfter(DateTime.parse(nextRetry));
        } catch (_) {
          return true;
        }
      }).toList();

      if (eligibleOps.isEmpty) {
        return null;
      }

      // 3. Agrupar por sucursal original para no mezclar inventarios ni perder sucursal
      final Map<int, List<Map<String, dynamic>>> branchGroups = {};
      for (final op in eligibleOps) {
        final bId = (op['branch_id'] as int?) ?? 1;
        branchGroups.putIfAbsent(bId, () => []).add(op);
      }

      int totalConfirmed = 0;
      int totalConflicts = 0;
      final List<dynamic> allReceipts = [];

      for (final entry in branchGroups.entries) {
        final targetBranchId = entry.key;
        final opsForBranch = entry.value;

        final List<Map<String, dynamic>> salesList = [];
        final List<Map<String, dynamic>> resList = [];

        for (final op in opsForBranch) {
          final payload = jsonDecode(op['payload'] as String);
          if (op['operation_type'] == 'sale') {
            salesList.add(payload);
          } else if (op['operation_type'] == 'reservation') {
            resList.add(payload);
          }
        }

        // Marcar atómicamente en ENVIANDO
        final nowIso = now.toUtc().toIso8601String();
        for (final op in opsForBranch) {
          final attempts = ((op['attempts'] as int?) ?? 0) + 1;
          await db.update(
            'sync_operations',
            {
              'status': 'ENVIANDO',
              'updated_at': nowIso,
              'attempts': attempts,
              'last_attempt_at': nowIso,
            },
            where: 'client_operation_uuid = ?',
            whereArgs: [op['client_operation_uuid']],
          );
        }

        final body = {
          'branch_id': targetBranchId,
          'sales': salesList,
          'reservations': resList,
        };

        try {
          final response = await ApiService.post('/sync/operations', body);
          if (response.statusCode != 200) {
            throw Exception('HTTP ${response.statusCode}: ${response.body}');
          }

          final responseData = jsonDecode(response.body);
          final receipts = responseData['receipts'] as List? ?? [];
          allReceipts.addAll(receipts);
          totalConfirmed += (responseData['confirmed_count'] as int? ?? 0);
          totalConflicts += (responseData['conflict_count'] as int? ?? 0);

          // Procesar recibos
          await db.transaction((txn) async {
            for (final receipt in receipts) {
              final rUuid = receipt['client_operation_uuid'] as String;
              final rStatus = receipt['status'] as String;
              final rServerId = receipt['server_id'] as int?;
              final rReason = receipt['rejection_reason'] as String?;
              final rOpType = receipt['operation_type'] as String;

              // Obtener estado previo para garantizar compensación exactamente una sola vez
              final prevOp = await txn.query('sync_operations', where: 'client_operation_uuid = ?', whereArgs: [rUuid]);
              final prevStatus = prevOp.isNotEmpty ? prevOp.first['status'] as String : '';

              await txn.update(
                'sync_operations',
                {
                  'status': rStatus,
                  'error_message': rReason,
                  'updated_at': DateTime.now().toUtc().toIso8601String(),
                },
                where: 'client_operation_uuid = ?',
                whereArgs: [rUuid],
              );

              if (rOpType == 'sale') {
                await txn.update(
                  'sales',
                  {
                    'sync_status': rStatus,
                    'server_id': rServerId,
                    'rejection_reason': rReason,
                  },
                  where: 'client_operation_uuid = ?',
                  whereArgs: [rUuid],
                );

                // Solo restaurar stock si transitó de ENVIANDO/PENDIENTE a RECHAZADA_CONFLICTO
                if (rStatus == 'RECHAZADA_CONFLICTO' && (prevStatus == 'ENVIANDO' || prevStatus == 'PENDIENTE')) {
                  final items = await txn.query('sale_items', where: 'client_operation_uuid = ?', whereArgs: [rUuid]);
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
              } else if (rOpType == 'reservation') {
                await txn.update(
                  'reservations',
                  {
                    'sync_status': rStatus,
                    'server_id': rServerId,
                    'rejection_reason': rReason,
                  },
                  where: 'client_operation_uuid = ?',
                  whereArgs: [rUuid],
                );

                if (rStatus == 'RECHAZADA_CONFLICTO' && (prevStatus == 'ENVIANDO' || prevStatus == 'PENDIENTE')) {
                  final items = await txn.query('reservation_items', where: 'client_operation_uuid = ?', whereArgs: [rUuid]);
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
        } catch (branchError) {
          debugPrint('[MOBILE-SYNC] Error sincronizando lote de sucursal $targetBranchId: $branchError');
          // Aplicar backoff exponencial para reintentos futuros
          for (final op in opsForBranch) {
            final attempts = (op['attempts'] as int? ?? 1);
            final delaySec = min(300, (pow(2, attempts) * 3)).toInt();
            final nextRetry = DateTime.now().add(Duration(seconds: delaySec)).toIso8601String();

            await db.update(
              'sync_operations',
              {
                'status': 'PENDIENTE',
                'next_retry_at': nextRetry,
                'error_message': branchError.toString(),
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              },
              where: 'client_operation_uuid = ?',
              whereArgs: [op['client_operation_uuid']],
            );
          }
        }
      }

      return {
        'total_processed': allReceipts.length,
        'confirmed_count': totalConfirmed,
        'conflict_count': totalConflicts,
        'receipts': allReceipts,
      };
    } finally {
      _isSyncing = false;
      await refreshPendingCount(tenantId: tenantId, userId: userId);
      notifyListeners();
    }
  }

  // ─── 6. CONSULTAS Y HISTORIAL FILTRADO POR USUARIO Y TENANT ────────────────

  Future<List<Map<String, dynamic>>> getSyncHistory({int? tenantId, int? userId}) async {
    final db = await _dbHelper.database;
    String? whereClause;
    List<dynamic>? whereArgs;

    if (tenantId != null && userId != null) {
      whereClause = 'tenant_id = ? AND user_id = ?';
      whereArgs = [tenantId, userId];
    } else if (tenantId != null) {
      whereClause = 'tenant_id = ?';
      whereArgs = [tenantId];
    } else if (userId != null) {
      whereClause = 'user_id = ?';
      whereArgs = [userId];
    }

    return await db.query(
      'sync_operations',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );
  }

  Future<int> refreshPendingCount({int? tenantId, int? userId}) async {
    final db = await _dbHelper.database;
    String sql = "SELECT COUNT(*) as count FROM sync_operations WHERE status = 'PENDIENTE'";
    List<dynamic> args = [];

    if (tenantId != null) {
      sql += " AND tenant_id = ?";
      args.add(tenantId);
    }
    if (userId != null) {
      sql += " AND user_id = ?";
      args.add(userId);
    }

    final res = await db.rawQuery(sql, args.isNotEmpty ? args : null);
    _pendingCount = Sqflite.firstIntValue(res) ?? 0;
    notifyListeners();
    return _pendingCount;
  }
}
