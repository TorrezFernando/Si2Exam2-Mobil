import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fashionstore_mobile/core/db/database_helper.dart';
import 'package:fashionstore_mobile/core/services/mobile_sync_service.dart';

Map<String, dynamic> profile(int id, int tenant) => {
  'id': id,
  'tenant_id': tenant,
  'branch_id': 7,
  '_offline_valid_until': DateTime.now()
      .toUtc()
      .add(const Duration(hours: 24))
      .toIso8601String(),
  'role': {
    'permissions': [
      {'name': 'sales:write'},
      {'name': 'reservations:write'},
    ],
  },
};
Map<String, dynamic> catalog(int tenant, {int stock = 5}) => {
  'tenant_id': tenant,
  'branch_id': 7,
  'branch_name': 'Sucursal 7',
  'server_timestamp': '2026-10-21T00:00:00Z',
  'categories': [],
  'customers': [],
  'products': [
    {
      'id': 1,
      'name': 'Camisa',
      'base_price': 100,
      'variants': [
        {
          'id': 10,
          'sku': 'TEST',
          'size': 'M',
          'color': 'Azul',
          'price': 120,
          'stock': stock,
        },
      ],
    },
  ],
};
http.Response receipt(
  Map<String, dynamic> body, {
  String status = 'CONFIRMADA',
}) => http.Response(
  jsonEncode({
    'receipts': [
      for (final op in body['sales'])
        {
          'client_operation_uuid': op['client_operation_uuid'],
          'operation_type': 'sale',
          'status': status,
          'server_id': status == 'CONFIRMADA' ? 9 : null,
          'rejection_reason': status == 'CONFIRMADA'
              ? null
              : 'Stock central insuficiente',
        },
      for (final op in body['reservations'])
        {
          'client_operation_uuid': op['client_operation_uuid'],
          'operation_type': 'reservation',
          'status': status,
          'server_id': status == 'CONFIRMADA' ? 8 : null,
          'rejection_reason': null,
        },
    ],
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root;
  late DatabaseHelper helper;
  late MobileSyncService sync;
  Future<int> stock() async =>
      (await (await helper.database).query('variants')).single['stock'] as int;
  Future<String> sell({int qty = 2, int branch = 7}) => sync.recordOfflineSale(
    branchId: branch,
    tenantId: 2,
    userId: 20,
    paymentMethod: 'efectivo',
    cashConfirmed: true,
    totalAmount: qty * 120,
    items: [
      {'variant_id': 10, 'quantity': qty, 'unit_price': 120},
    ],
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('fashion-sync-test-');
    helper = DatabaseHelper.forTesting(databaseFactoryFfi, root.path);
    sync = MobileSyncService.forTesting(helper);
    sync.setSession(profile(20, 2), 'token-A');
    await sync.ready;
    sync.getRequest = (path, token) async =>
        http.Response(jsonEncode(catalog(2)), 200);
    sync.setOnline(true);
    expect(await sync.downloadCatalog(7), isTrue);
    sync.setOnline(false);
  });
  tearDown(() async {
    sync.dispose();
    await helper.close();
    await root.delete(recursive: true);
  });

  test(
    'atomic registration, stock validation and relational integrity',
    () async {
      await expectLater(
        sell(qty: 6),
        throwsA(isA<InsufficientStockException>()),
      );
      expect(await stock(), 5);
      expect(await sync.getSyncHistory(), isEmpty);
      await expectLater(sell(branch: 8), throwsA(isA<ValidationException>()));
      await sell();
      expect(await stock(), 3);
      final db = await helper.database;
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect((await db.query('sales')).single['tenant_id'], 2);
      expect((await db.query('sync_operations')).single['user_id'], 20);
      await expectLater(
        db.insert('sale_items', {
          'client_operation_uuid': 'missing',
          'variant_id': 10,
          'quantity': 1,
          'unit_price': 120,
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
  test('account switch never sends another owners queue', () async {
    await sell();
    sync.setSession(profile(30, 3), 'token-B');
    await sync.ready;
    var calls = 0;
    sync.postRequest = (p, b, t) async {
      calls++;
      return receipt(b);
    };
    sync.setOnline(true);
    await sync.syncBatch();
    expect(calls, 0);
    expect(await sync.getSyncHistory(), isEmpty);
    sync.setOnline(false);
    sync.setSession(profile(20, 2), 'token-A');
    await sync.ready;
    expect((await sync.getSyncHistory()).length, 1);
    expect(await stock(), 3);
  });
  test('same operation survives closing SQLite and reopening', () async {
    final id = await sell();
    await helper.close();
    expect((await sync.getSyncHistory()).single['client_operation_uuid'], id);
    expect(await stock(), 3);
  });
  test(
    'partial receipt restores pending, preserves UUID and reserves stock',
    () async {
      final id = await sell();
      sync.postRequest = (p, b, t) async =>
          http.Response('{"receipts":[]}', 200);
      sync.setOnline(true);
      await sync.syncBatch();
      final op = (await sync.getSyncHistory()).single;
      expect(op['status'], 'PENDIENTE');
      expect(op['client_operation_uuid'], id);
      expect(op['next_retry_at'], isNotNull);
      expect(await stock(), 3);
    },
  );
  test('conflict compensates once and is not automatically resent', () async {
    await sell();
    var calls = 0;
    sync.postRequest = (p, b, t) async {
      calls++;
      return receipt(b, status: 'RECHAZADA_CONFLICTO');
    };
    sync.setOnline(true);
    await sync.syncBatch();
    await sync.syncBatch();
    expect(calls, 1);
    expect(await stock(), 5);
    expect(
      (await sync.getSyncHistory()).single['status'],
      'RECHAZADA_CONFLICTO',
    );
  });
  test(
    'lost response prevents snapshot rebase until receipt reconciled',
    () async {
      await sell();
      var downloads = 0;
      sync.postRequest = (p, b, t) async =>
          throw TimeoutException('response lost after server commit');
      sync.getRequest = (p, t) async {
        downloads++;
        return http.Response(jsonEncode(catalog(2, stock: 3)), 200);
      };
      sync.setOnline(true);
      await sync.syncBatch();
      expect(await sync.downloadCatalog(7), isFalse);
      expect(downloads, 0);
      expect(await stock(), 3);
      await (await helper.database).update('sync_operations', {
        'next_retry_at': null,
      });
      sync.postRequest = (p, b, t) async => receipt(b);
      expect(await sync.downloadCatalog(7), isTrue);
      expect(await stock(), 3);
    },
  );
  test('concurrent triggers make one request', () async {
    await sell();
    final started = Completer<void>(), finish = Completer<void>();
    var calls = 0;
    sync.postRequest = (p, b, t) async {
      calls++;
      started.complete();
      await finish.future;
      return receipt(b);
    };
    sync.setOnline(true);
    final first = sync.syncBatch();
    await started.future;
    await sync.syncBatch();
    finish.complete();
    await first;
    expect(calls, 1);
    expect(await stock(), 3);
  });
  test(
    'session switch during POST leaves receipt with original owner',
    () async {
      await sell();
      final started = Completer<void>(), finish = Completer<void>();
      sync.postRequest = (p, b, t) async {
        expect(t, 'token-A');
        started.complete();
        await finish.future;
        return receipt(b);
      };
      sync.setOnline(true);
      final sending = sync.syncBatch();
      await started.future;
      sync.setOnline(false);
      sync.setSession(profile(30, 3), 'token-B');
      await sync.ready;
      finish.complete();
      await sending;
      expect(await sync.getSyncHistory(), isEmpty);
      sync.setSession(profile(20, 2), 'token-A');
      await sync.ready;
      expect((await sync.getSyncHistory()).single['status'], 'PENDIENTE');
      expect(await stock(), 3);
    },
  );
  test('unauthorized consumer cannot record paid cash sale', () async {
    sync.setSession({
      'id': 20,
      'tenant_id': 2,
      'role': {'permissions': []},
    }, 'consumer');
    await sync.ready;
    expect(() => sell(), throwsA(isA<ValidationException>()));
  });
  test('legacy file is preserved without automatic assignment', () async {
    final legacy = File('${root.path}/fashionstore_mobile.db');
    await legacy.writeAsString('legacy bytes');
    expect(await helper.hasLegacyData(), isTrue);
    expect(await legacy.readAsString(), 'legacy bytes');
    expect(await sync.getSyncHistory(), isEmpty);
  });
}
