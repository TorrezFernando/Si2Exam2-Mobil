import 'dart:async';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  String? _scope;
  final Map<String, Future<Database>> _databases = {};
  final DatabaseFactory? _factory;
  final String? _root;
  DatabaseHelper._init() : _factory = null, _root = null;
  DatabaseHelper.forTesting(DatabaseFactory factory, String root)
    : _factory = factory,
      _root = root;
  Future<String> get directory async => _root ?? await getDatabasesPath();

  void setScope(int? tenant, int? owner) {
    _scope = tenant != null && owner != null && tenant > 0 && owner > 0
        ? '${tenant}_$owner'
        : null;
  }

  Future<Database> get database {
    final scope = _scope;
    if (scope == null)
      throw StateError('Se requiere una sesión con empresa y usuario.');
    return _databases.putIfAbsent(scope, () async {
      try {
        return await (_factory ?? databaseFactory).openDatabase(
          join(await directory, 'fashionstore_account_$scope.db'),
          options: OpenDatabaseOptions(
            version: 3,
            onCreate: _createDB,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          ),
        );
      } catch (_) {
        _databases.remove(scope);
        rethrow;
      }
    });
  }

  // Legacy v1/v2 contains no reliable operator identity. Keep it byte-for-byte
  // intact, outside active account databases. Never assign its rows to user 1.
  Future<bool> hasLegacyData() async => (_factory ?? databaseFactory)
      .databaseExists(join(await directory, 'fashionstore_mobile.db'));

  Future<void> _createDB(Database db, int version) async {
    await db.execute(
      'CREATE TABLE cache_metadata (id INTEGER PRIMARY KEY CHECK(id=1), branch_id INTEGER NOT NULL, server_timestamp TEXT NOT NULL)',
    );
    // 1. Sucursales
    await db.execute('''
      CREATE TABLE branches (
        id INTEGER PRIMARY KEY,
        tenant_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        address TEXT NOT NULL,
        city TEXT,
        phone TEXT,
        is_active INTEGER NOT NULL
      )
    ''');

    // 2. Categorías
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT
      )
    ''');

    // 3. Productos
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY,
        tenant_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        category_id INTEGER,
        category_name TEXT,
        base_price REAL NOT NULL,
        image_url TEXT,
        is_active INTEGER NOT NULL
      )
    ''');

    // 4. Variantes de Producto con Stock de Sucursal
    await db.execute('''
      CREATE TABLE variants (
        id INTEGER PRIMARY KEY,
        product_id INTEGER NOT NULL,
        sku TEXT NOT NULL,
        size TEXT NOT NULL,
        color TEXT NOT NULL,
        price REAL NOT NULL,
        stock INTEGER NOT NULL DEFAULT 0 CHECK(stock >= 0),
        image_url TEXT,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');

    // 5. Clientes Mínimos
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY,
        tenant_id INTEGER NOT NULL,
        full_name TEXT,
        email TEXT NOT NULL,
        phone TEXT
      )
    ''');

    // 6. Ventas Offline Locales
    await db.execute('''
      CREATE TABLE sales (
        client_operation_uuid TEXT PRIMARY KEY,
        tenant_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL REFERENCES branches(id),
        user_id INTEGER,
        customer_name TEXT,
        payment_method TEXT NOT NULL,
        total_amount REAL NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK(sync_status IN ('PENDIENTE','ENVIANDO','CONFIRMADA','RECHAZADA_CONFLICTO')),
        server_id INTEGER,
        rejection_reason TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // 7. Detalles de Venta
    await db.execute('''
      CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_operation_uuid TEXT NOT NULL,
        variant_id INTEGER NOT NULL REFERENCES variants(id),
        quantity INTEGER NOT NULL CHECK(quantity > 0),
        unit_price REAL NOT NULL,
        product_name TEXT,
        variant_label TEXT,
        FOREIGN KEY (client_operation_uuid) REFERENCES sales (client_operation_uuid) ON DELETE CASCADE
      )
    ''');

    // 8. Reservas Offline Locales
    await db.execute('''
      CREATE TABLE reservations (
        client_operation_uuid TEXT PRIMARY KEY,
        tenant_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL REFERENCES branches(id),
        user_id INTEGER NOT NULL,
        customer_name TEXT,
        pickup_date TEXT,
        notes TEXT,
        sync_status TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK(sync_status IN ('PENDIENTE','ENVIANDO','CONFIRMADA','RECHAZADA_CONFLICTO')),
        server_id INTEGER,
        rejection_reason TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // 9. Detalles de Reserva
    await db.execute('''
      CREATE TABLE reservation_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_operation_uuid TEXT NOT NULL,
        variant_id INTEGER NOT NULL REFERENCES variants(id),
        quantity INTEGER NOT NULL CHECK(quantity > 0),
        unit_price REAL,
        product_name TEXT,
        variant_label TEXT,
        FOREIGN KEY (client_operation_uuid) REFERENCES reservations (client_operation_uuid) ON DELETE CASCADE
      )
    ''');

    // 10. Cola de Operaciones de Sincronización (RNF03, RNF04, RNF05, RNF06)
    await db.execute('''
      CREATE TABLE sync_operations (
        client_operation_uuid TEXT PRIMARY KEY,
        tenant_id INTEGER NOT NULL,
        user_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL REFERENCES branches(id),
        operation_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK(status IN ('PENDIENTE','ENVIANDO','CONFIRMADA','RECHAZADA_CONFLICTO')),
        attempts INTEGER NOT NULL DEFAULT 0,
        next_retry_at TEXT,
        last_attempt_at TEXT,
        error_message TEXT,
        blocked INTEGER NOT NULL DEFAULT 0,
        sale_uuid TEXT REFERENCES sales(client_operation_uuid),
        reservation_uuid TEXT REFERENCES reservations(client_operation_uuid),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK ((operation_type = 'sale' AND sale_uuid = client_operation_uuid AND sale_uuid IS NOT NULL AND reservation_uuid IS NULL) OR (operation_type = 'reservation' AND reservation_uuid = client_operation_uuid AND reservation_uuid IS NOT NULL AND sale_uuid IS NULL))
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_ops_status ON sync_operations (tenant_id, user_id, status);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_ops_branch ON sync_operations (tenant_id, branch_id);',
    );
  }

  Future<void> close() async {
    for (final future in _databases.values) {
      await (await future).close();
    }
    _databases.clear();
  }
}
