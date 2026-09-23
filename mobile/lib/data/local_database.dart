import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();
  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'oma_mobile.db'),
      version: 5,
      onCreate: (database, version) => _create(database),
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute('ALTER TABLE products ADD COLUMN cost TEXT');
          await database.execute('ALTER TABLE sales ADD COLUMN notes TEXT');
        }
        if (oldVersion < 3) {
          await database.execute("ALTER TABLE sales ADD COLUMN local_only INTEGER NOT NULL DEFAULT 0");
          await database.execute("ALTER TABLE sales ADD COLUMN sync_error TEXT");
          await database.execute("ALTER TABLE sync_queue ADD COLUMN local_sale_id INTEGER");
        }
        if (oldVersion < 4) {
          await database.execute('''CREATE TABLE IF NOT EXISTS batches (id INTEGER PRIMARY KEY, name TEXT, status TEXT, departed_at TEXT, arrived_at TEXT, notes TEXT, created_at TEXT)''');
          await database.execute('''CREATE TABLE IF NOT EXISTS deliveries (id INTEGER PRIMARY KEY, method TEXT, status TEXT, is_consolidated INTEGER DEFAULT 0, consolidation_type TEXT, delivery_address TEXT, notes TEXT, created_at TEXT, shipped_at TEXT, delivered_at TEXT, package_weight_kg TEXT, package_dimensions TEXT, remarks TEXT, sale_ids_json TEXT)''');
          await database.execute('''CREATE TABLE IF NOT EXISTS shipping (id INTEGER PRIMARY KEY, sale_id INTEGER, courier TEXT, tracking_number TEXT, chargeable_weight_kg TEXT, total_cbm TEXT, shipping_status TEXT, shipped_at TEXT, delivered_at TEXT, notes TEXT)''');
        }
        if (oldVersion < 5) {
          await database.execute("ALTER TABLE sync_queue ADD COLUMN depends_on_operation_id TEXT");
          await database.execute("ALTER TABLE sync_queue ADD COLUMN next_attempt_at TEXT");
          await database.execute("ALTER TABLE sync_queue ADD COLUMN response_json TEXT");
        }
      },
    );
    return _db!;
  }

  Future<void> _create(Database database) async {
    await database.execute('''CREATE TABLE products (
      id INTEGER PRIMARY KEY, name TEXT NOT NULL, sku TEXT, cost TEXT,
      length_cm REAL, width_cm REAL, height_cm REAL, cbm REAL,
      volumetric_kg REAL, actual_weight_kg REAL, stock INTEGER NOT NULL DEFAULT 0,
      created_at TEXT, updated_at TEXT)''');
    await database.execute('''CREATE TABLE sales (
      id INTEGER PRIMARY KEY, order_id TEXT, client_operation_id TEXT,
      sale_date TEXT, customer_name TEXT, customer_phone TEXT, customer_address TEXT,
      customer_state TEXT, order_status TEXT, payment_status TEXT, notes TEXT,
      subtotal_amount TEXT, estimated_shipping_cost TEXT, actual_shipping_cost TEXT,
      shipping_payment_settled INTEGER NOT NULL DEFAULT 0, total_amount TEXT,
      batch_id INTEGER, delivery_id INTEGER, raw_json TEXT, updated_at TEXT,
      local_only INTEGER NOT NULL DEFAULT 0, sync_error TEXT)''');
    await database.execute('''CREATE TABLE sale_items (
      id INTEGER PRIMARY KEY, sale_id INTEGER NOT NULL, product_id INTEGER NOT NULL,
      product_name TEXT, qty INTEGER NOT NULL, unit_cost TEXT, unit_price TEXT,
      variant_note TEXT, line_cbm TEXT, line_volumetric_kg TEXT)''');
    await database.execute('''CREATE TABLE sync_queue (
      local_id INTEGER PRIMARY KEY AUTOINCREMENT, operation_id TEXT NOT NULL UNIQUE,
      operation_type TEXT NOT NULL, payload_json TEXT NOT NULL, local_sale_id INTEGER,
      status TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      depends_on_operation_id TEXT, next_attempt_at TEXT, response_json TEXT)''');
    await database.execute('''CREATE TABLE sync_meta (key TEXT PRIMARY KEY, value TEXT)''');
    await database.execute('''CREATE TABLE batches (id INTEGER PRIMARY KEY, name TEXT, status TEXT, departed_at TEXT, arrived_at TEXT, notes TEXT, created_at TEXT)''');
    await database.execute('''CREATE TABLE deliveries (id INTEGER PRIMARY KEY, method TEXT, status TEXT, is_consolidated INTEGER DEFAULT 0, consolidation_type TEXT, delivery_address TEXT, notes TEXT, created_at TEXT, shipped_at TEXT, delivered_at TEXT, package_weight_kg TEXT, package_dimensions TEXT, remarks TEXT, sale_ids_json TEXT)''');
    await database.execute('''CREATE TABLE shipping (id INTEGER PRIMARY KEY, sale_id INTEGER, courier TEXT, tracking_number TEXT, chargeable_weight_kg TEXT, total_cbm TEXT, shipping_status TEXT, shipped_at TEXT, delivered_at TEXT, notes TEXT)''');
  }

  Future<String?> getMeta(String key) async {
    final rows = await (await db).query('sync_meta', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value']?.toString();
  }

  Future<void> setMeta(String key, String value) async {
    await (await db).insert('sync_meta', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearAllData() async {
    final database = await db;
    await database.transaction((txn) async {
      for (final table in ['sale_items', 'sales', 'products', 'batches', 'deliveries', 'shipping']) await txn.delete(table);
      await txn.delete('sync_queue');
      await txn.delete('sync_meta');
    });
  }

  Future<void> applyBootstrap(Map<String, dynamic> data) async {
    final database = await db;
    await database.transaction((txn) async {
      // Never wipe unsynced work during a bootstrap.
      await txn.delete('sale_items', where: 'sale_id >= 0');
      await txn.delete('sales', where: 'id >= 0');
      await txn.delete('products');
      await txn.delete('batches');
      await txn.delete('deliveries');
      await txn.delete('shipping');
      for (final raw in (data['products'] as List? ?? const [])) {
        await _upsertProduct(txn, Map<String, dynamic>.from(raw as Map));
      }
      for (final raw in (data['sales'] as List? ?? const [])) {
        await _upsertSale(txn, Map<String, dynamic>.from(raw as Map));
      }
      for (final raw in (data['batches'] as List? ?? const [])) { await _upsertBatch(txn, Map<String, dynamic>.from(raw as Map)); }
      for (final raw in (data['deliveries'] as List? ?? const [])) { await _upsertDelivery(txn, Map<String, dynamic>.from(raw as Map)); }
      for (final raw in (data['shipping'] as List? ?? const [])) { await _upsertShipping(txn, Map<String, dynamic>.from(raw as Map)); }
    });
    final cursor = data['cursor']?.toString();
    if (cursor != null) await setMeta('sync_cursor', cursor);
  }

  Future<int> nextLocalSaleId() async {
    final rows = await (await db).rawQuery('SELECT MIN(id) AS min_id FROM sales WHERE id < 0');
    final minId = rows.first['min_id'] as int?;
    return (minId ?? 0) - 1;
  }

  Future<int> createLocalSale(Map<String, dynamic> sale, List<Map<String, dynamic>> items) async {
    final database = await db;
    final localId = await nextLocalSaleId();
    final now = DateTime.now().toUtc().toIso8601String();
    await database.transaction((txn) async {
      for (final item in items) {
        final pid = item['product_id'] as int;
        final qty = item['qty'] as int;
        final rows = await txn.query('products', columns: ['stock'], where: 'id = ?', whereArgs: [pid], limit: 1);
        if (rows.isEmpty) throw Exception('Product no longer exists locally.');
        final stock = rows.first['stock'] as int? ?? 0;
        if (stock < qty) throw Exception('Not enough local stock for product #$pid.');
      }
      await txn.insert('sales', {
        'id': localId, 'order_id': 'OFF-${(-localId).toString().padLeft(6, '0')}',
        'client_operation_id': sale['operation_id'], 'sale_date': now.substring(0, 10),
        'customer_name': sale['customer_name'], 'customer_phone': sale['customer_phone'],
        'customer_address': sale['customer_address'], 'customer_state': sale['customer_state'],
        'order_status': 'Pending Sync', 'payment_status': sale['payment_status'] ?? 'Paid',
        'notes': sale['notes'], 'subtotal_amount': sale['subtotal_amount']?.toString(),
        'total_amount': sale['subtotal_amount']?.toString(), 'raw_json': jsonEncode(sale),
        'updated_at': now, 'local_only': 1,
      });
      final itemIdRows = await txn.rawQuery('SELECT MIN(id) AS min_id FROM sale_items WHERE id < 0');
      var itemId = ((itemIdRows.first['min_id'] as int?) ?? 0) - 1;
      for (final item in items) {
        final productRows = await txn.query('products', columns: ['name'], where: 'id = ?', whereArgs: [item['product_id']], limit: 1);
        final name = productRows.isEmpty ? '' : productRows.first['name'];
        await txn.insert('sale_items', {
          'id': itemId--, 'sale_id': localId, 'product_id': item['product_id'], 'product_name': name,
          'qty': item['qty'], 'unit_price': item['unit_price']?.toString(), 'variant_note': item['variant_note'],
        });
        await txn.rawUpdate('UPDATE products SET stock = stock - ? WHERE id = ?', [item['qty'], item['product_id']]);
      }
    });
    return localId;
  }

  Future<void> markLocalSaleError(int localSaleId, String error) async {
    await (await db).update('sales', {'sync_error': error, 'order_status': 'Sync Error'}, where: 'id = ?', whereArgs: [localSaleId]);
  }

  Future<void> removeLocalSaleAndRestoreStock(int localSaleId) async {
    final database = await db;
    await database.transaction((txn) async {
      final items = await txn.query('sale_items', where: 'sale_id = ?', whereArgs: [localSaleId]);
      for (final item in items) {
        await txn.rawUpdate('UPDATE products SET stock = stock + ? WHERE id = ?', [item['qty'], item['product_id']]);
      }
      await txn.delete('sale_items', where: 'sale_id = ?', whereArgs: [localSaleId]);
      await txn.delete('sales', where: 'id = ?', whereArgs: [localSaleId]);
    });
  }

  Future<void> applyChanges(List<dynamic> changes) async {
    final database = await db;
    await database.transaction((txn) async {
      for (final raw in changes) {
        final change = Map<String, dynamic>.from(raw as Map);
        final type = change['entity_type']?.toString();
        final operation = change['operation']?.toString();
        final entityId = int.tryParse('${change['entity_id']}');
        final payload = change['payload'] is Map ? Map<String, dynamic>.from(change['payload']) : <String, dynamic>{};
        if (type == 'product') {
          if (operation == 'delete') await txn.delete('products', where: 'id = ?', whereArgs: [entityId]);
          else await _upsertProduct(txn, payload);
        } else if (type == 'sale') {
          if (operation == 'delete') await txn.delete('sales', where: 'id = ?', whereArgs: [entityId]);
          else await _upsertSale(txn, payload);
        } else if (type == 'sale_item') {
          if (operation == 'delete') await txn.delete('sale_items', where: 'id = ?', whereArgs: [entityId]);
          else await _upsertSaleItem(txn, payload);
        } else if (type == 'shipment_batch') {
          if (operation == 'delete') await txn.delete('batches', where: 'id = ?', whereArgs: [entityId]);
          else await _upsertBatch(txn, payload);
        } else if (type == 'delivery') {
          if (operation == 'delete') await txn.delete('deliveries', where: 'id = ?', whereArgs: [entityId]);
          else await _upsertDelivery(txn, payload);
        } else if (type == 'shipping') {
          if (operation == 'delete') await txn.delete('shipping', where: 'id = ?', whereArgs: [entityId]);
          else await _upsertShipping(txn, payload);
        }
      }
    });
  }

  Future<void> _upsertProduct(Transaction txn, Map<String, dynamic> p) async {
    await txn.insert('products', {
      'id': p['id'], 'name': p['name'] ?? '', 'sku': p['sku'], 'cost': p['cost']?.toString(),
      'length_cm': _num(p['length_cm']), 'width_cm': _num(p['width_cm']), 'height_cm': _num(p['height_cm']),
      'cbm': _num(p['cbm']), 'volumetric_kg': _num(p['volumetric_kg']), 'actual_weight_kg': _num(p['actual_weight_kg']),
      'stock': p['stock'] ?? 0, 'created_at': p['created_at'], 'updated_at': p['updated_at'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _upsertSale(Transaction txn, Map<String, dynamic> s) async {
    final serverId = int.tryParse('${s['id']}');
    if (serverId == null || serverId <= 0) return;
    // A successful sync replaces the matching negative local sale by operation id.
    final opId = s['client_operation_id']?.toString();
    if (opId != null && opId.isNotEmpty) {
      final locals = await txn.query('sales', columns: ['id'], where: 'client_operation_id = ? AND id < 0', whereArgs: [opId]);
      for (final row in locals) {
        final localId = row['id'];
        await txn.delete('sale_items', where: 'sale_id = ?', whereArgs: [localId]);
        await txn.delete('sales', where: 'id = ?', whereArgs: [localId]);
      }
    }
    await txn.insert('sales', {
      'id': serverId, 'order_id': s['order_id'], 'client_operation_id': s['client_operation_id'],
      'sale_date': s['sale_date'], 'customer_name': s['customer_name'], 'customer_phone': s['customer_phone'],
      'customer_address': s['customer_address'], 'customer_state': s['customer_state'], 'order_status': s['order_status'],
      'payment_status': s['payment_status'], 'notes': s['notes'], 'subtotal_amount': s['subtotal_amount']?.toString(),
      'estimated_shipping_cost': s['estimated_shipping_cost']?.toString(), 'actual_shipping_cost': s['actual_shipping_cost']?.toString(),
      'shipping_payment_settled': s['shipping_payment_settled'] == true ? 1 : 0, 'total_amount': s['total_amount']?.toString(),
      'batch_id': s['batch_id'], 'delivery_id': s['delivery_id'], 'raw_json': jsonEncode(s), 'updated_at': s['created_at'], 'local_only': 0, 'sync_error': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await txn.delete('sale_items', where: 'sale_id = ?', whereArgs: [serverId]);
    for (final raw in (s['items'] as List? ?? const [])) {
      final item = Map<String, dynamic>.from(raw as Map);
      await _upsertSaleItem(txn, {...item, 'sale_id': serverId});
    }
  }

  Future<void> _upsertSaleItem(Transaction txn, Map<String, dynamic> i) async {
    await txn.insert('sale_items', {
      'id': i['id'], 'sale_id': i['sale_id'], 'product_id': i['product_id'], 'product_name': i['product_name'],
      'qty': i['qty'] ?? 0, 'unit_cost': i['unit_cost']?.toString(), 'unit_price': i['unit_price']?.toString(),
      'variant_note': i['variant_note'], 'line_cbm': i['line_cbm']?.toString(), 'line_volumetric_kg': i['line_volumetric_kg']?.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _upsertBatch(Transaction txn, Map<String, dynamic> b) async {
    await txn.insert('batches', {
      'id': b['id'], 'name': b['name'], 'status': b['status'], 'departed_at': b['departed_at'],
      'arrived_at': b['arrived_at'], 'notes': b['notes'], 'created_at': b['created_at'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _upsertDelivery(Transaction txn, Map<String, dynamic> d) async {
    await txn.insert('deliveries', {
      'id': d['id'], 'method': d['method'], 'status': d['status'], 'is_consolidated': d['is_consolidated'] == true ? 1 : 0,
      'consolidation_type': d['consolidation_type'], 'delivery_address': d['delivery_address'], 'notes': d['notes'],
      'created_at': d['created_at'], 'shipped_at': d['shipped_at'], 'delivered_at': d['delivered_at'],
      'package_weight_kg': d['package_weight_kg']?.toString(), 'package_dimensions': d['package_dimensions'],
      'remarks': d['remarks'], 'sale_ids_json': jsonEncode(d['sale_ids'] ?? const []),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _upsertShipping(Transaction txn, Map<String, dynamic> s) async {
    await txn.insert('shipping', {
      'id': s['id'], 'sale_id': s['sale_id'], 'courier': s['courier'], 'tracking_number': s['tracking_number'],
      'chargeable_weight_kg': s['chargeable_weight_kg']?.toString(), 'total_cbm': s['total_cbm']?.toString(),
      'shipping_status': s['shipping_status'], 'shipped_at': s['shipped_at'], 'delivered_at': s['delivered_at'], 'notes': s['notes'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  double? _num(dynamic value) => value == null ? null : double.tryParse(value.toString());
}
