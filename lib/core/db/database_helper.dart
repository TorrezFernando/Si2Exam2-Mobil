import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('fashionstore_mobile.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
      onConfigure: _onConfigure,
    );
  }

  Future<void> _onConfigure(Database db) async {
    // Activar integridad referencial y claves foráneas en SQLite
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Sucursales
    await db.execute('''
      CREATE TABLE branches (
        id INTEGER PRIMARY KEY,
        tenant_id INTEGER,
        name TEXT NOT NULL,
        address TEXT NOT NULL,
        city TEXT,
        phone TEXT,
        is_active INTEGER NOT NULL DEFAULT 1
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
        tenant_id INTEGER,
        name TEXT NOT NULL,
        description TEXT,
        category_id INTEGER,
        category_name TEXT,
        base_price REAL NOT NULL,
        image_url TEXT,
        is_active INTEGER NOT NULL DEFAULT 1
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
        stock INTEGER NOT NULL DEFAULT 0,
        image_url TEXT,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');

    // 5. Clientes Mínimos
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY,
        tenant_id INTEGER,
        full_name TEXT,
        email TEXT NOT NULL,
        phone TEXT
      )
    ''');

    // 6. Ventas Offline Locales
    await db.execute('''
      CREATE TABLE sales (
        client_operation_uuid TEXT PRIMARY KEY,
        tenant_id INTEGER,
        branch_id INTEGER NOT NULL,
        user_id INTEGER,
        customer_name TEXT,
        payment_method TEXT NOT NULL,
        total_amount REAL NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'PENDIENTE',
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
        variant_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
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
        tenant_id INTEGER,
        branch_id INTEGER NOT NULL,
        user_id INTEGER NOT NULL,
        customer_name TEXT,
        pickup_date TEXT,
        notes TEXT,
        sync_status TEXT NOT NULL DEFAULT 'PENDIENTE',
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
        variant_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
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
        operation_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDIENTE',
        attempts INTEGER NOT NULL DEFAULT 0,
        error_message TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
