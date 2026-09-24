import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'api_client.dart';
import 'local_database.dart';

class SyncRepository {
  SyncRepository(this.api, this.local);
  final ApiClient api;
  final LocalDatabase local;
  final _uuid = const Uuid();

  Future<String> enqueue(String type, Map<String, dynamic> payload, {String? localSaleId, String? dependsOn}) async {
    final op = (payload['operation_id']?.toString().isNotEmpty ?? false) ? payload['operation_id'].toString() : _uuid.v4();
    payload = {...payload, 'operation_id': op};
    final db = await local.db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('sync_queue', {
      'operation_id': op, 'operation_type': type, 'payload_json': jsonEncode(payload),
      'local_sale_id': localSaleId == null ? null : int.tryParse(localSaleId),
      'status': 'pending', 'attempts': 0, 'created_at': now, 'updated_at': now,
      'depends_on_operation_id': dependsOn,
    });
    return op;
  }

  Future<void> bootstrapIfNeeded() async {
    if (await local.getMeta('bootstrapped') == '1') return;
    final data = await api.bootstrap();
    await local.applyBootstrap(data);
    await local.setMeta('bootstrapped', '1');
  }

  Future<int> saveSaleOffline({required String customerName, required String customerPhone, required String customerAddress, required String customerState, required String paymentStatus, required String notes, required List<Map<String, dynamic>> items}) async {
    final op = _uuid.v4();
    var subtotal = 0.0;
    for (final item in items) subtotal += (double.tryParse('${item['unit_price']}') ?? 0) * (item['qty'] as int);
    final payload = {'operation_id': op, 'customer_name': customerName.trim(), 'customer_phone': customerPhone.trim(), 'customer_address': customerAddress.trim(), 'customer_state': customerState.trim(), 'payment_status': paymentStatus, 'notes': notes.trim(), 'subtotal_amount': subtotal.toStringAsFixed(2), 'items': items};
    final localId = await local.createLocalSale(payload, items);
    await enqueue('create_sale', payload, localSaleId: '$localId');
    return localId;
  }

  Future<void> saveStockAdjustment({required int productId, required int changeQty, required String reason}) async {
    final op = _uuid.v4(); final payload = {'operation_id': op, 'product_id': productId, 'change_qty': changeQty, 'reason': reason.trim()};
    final db = await local.db;
    await db.transaction((txn) async {
      final rows = await txn.query('products', columns: ['stock'], where: 'id = ?', whereArgs: [productId], limit: 1);
      if (rows.isEmpty) throw Exception('Product not found locally.');
      final current = rows.first['stock'] as int? ?? 0;
      if (current + changeQty < 0) throw Exception('Stock cannot go below zero.');
      await txn.rawUpdate('UPDATE products SET stock = stock + ? WHERE id = ?', [changeQty, productId]);
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.insert('sync_queue', {'operation_id': op, 'operation_type': 'stock_adjust', 'payload_json': jsonEncode(payload), 'status': 'pending', 'attempts': 0, 'created_at': now, 'updated_at': now});
    });
  }

  Future<String> queueCreateBatch(String name, String notes) => enqueue('create_batch', {'name': name.trim(), 'notes': notes.trim()});
  Future<String> queueBatchSale(int batchId, int saleId) => enqueue('batch_sale', {'batch_id': batchId, 'sale_id': saleId});
  Future<String> queueBatchArrive(int batchId) => enqueue('batch_arrive', {'batch_id': batchId});
  Future<String> queueSaleStatus(int saleId, String status) => enqueue('sale_status', {'sale_id': saleId, 'status': status});
  Future<String> queueSettleShipping(int saleId) => enqueue('settle_shipping', {'sale_id': saleId});
  Future<String> queueCreateDelivery({required List<int> saleIds, required String method, String? consolidationType, String? address, String? notes}) => enqueue('create_delivery', {'sale_ids': saleIds, 'method': method, 'consolidation_type': consolidationType, 'delivery_address': address, 'notes': notes});
  Future<String> queueDeliveryStatus(int deliveryId, String status) => enqueue('delivery_status', {'delivery_id': deliveryId, 'status': status});
  Future<String> queueCreateShipping({required int saleId, required String courier, required String trackingNumber, String? notes}) => enqueue('create_shipping', {'sale_id': saleId, 'courier': courier, 'tracking_number': trackingNumber, 'notes': notes});
  Future<String> queueUpdateShipping(int shippingId, Map<String, dynamic> fields) => enqueue('update_shipping', {'shipping_id': shippingId, ...fields});

  Future<SyncResult> syncOnce() async {
    await bootstrapIfNeeded();
    final db = await local.db;
    final now = DateTime.now().toUtc();
    final rows = await db.query('sync_queue', where: "status IN ('pending','retry') AND (next_attempt_at IS NULL OR next_attempt_at <= ?)", whereArgs: [now.toIso8601String()], orderBy: 'local_id ASC', limit: 50);
    int completed = 0;
    for (final row in rows) {
      final op = row['operation_id'].toString();
      final dependency = row['depends_on_operation_id']?.toString();
      if (dependency != null && dependency.isNotEmpty) {
        final dep = await db.query('sync_queue', columns: ['status'], where: 'operation_id = ?', whereArgs: [dependency], limit: 1);
        if (dep.isNotEmpty && dep.first['status'] != 'synced') continue;
      }
      final type = row['operation_type'].toString();
      final payload = Map<String, dynamic>.from(jsonDecode(row['payload_json'] as String) as Map);
      try {
        dynamic response;
        if (type == 'create_sale') response = await api.createSale(payload);
        else if (type == 'stock_adjust') response = await api.stockAdjust(payload);
        else if (type == 'create_batch') response = await api.createBatch(payload);
        else if (type == 'batch_sale') response = await api.addSaleToBatch(payload['batch_id'] as int, payload['sale_id'] as int, {'operation_id': op});
        else if (type == 'batch_arrive') response = await api.arriveBatch(payload['batch_id'] as int, {'operation_id': op});
        else if (type == 'sale_status') response = await api.updateSaleStatus(payload['sale_id'] as int, payload);
        else if (type == 'settle_shipping') response = await api.settleShipping(payload['sale_id'] as int, {'operation_id': op});
        else if (type == 'create_delivery') response = await api.createDelivery(payload);
        else if (type == 'delivery_status') response = await api.updateDeliveryStatus(payload['delivery_id'] as int, payload);
        else if (type == 'create_shipping') response = await api.createShipping(payload);
        else if (type == 'update_shipping') response = await api.updateShipping(payload['shipping_id'] as int, payload);
        else throw Exception('Unsupported queued operation: $type');

        if (response is Map) {
          final m = Map<String, dynamic>.from(response);
          final entityType = type.contains('delivery') ? 'delivery' : type.contains('shipping') || type.contains('settle_shipping') ? (type == 'settle_shipping' ? 'sale' : 'shipping') : type.contains('batch') ? 'shipment_batch' : type == 'stock_adjust' ? 'product' : type.contains('sale') ? 'sale' : null;
          if (entityType != null) await local.applyChanges([{'entity_type': entityType, 'entity_id': m['id']?.toString() ?? '', 'operation': 'upsert', 'payload': m}]);
          await db.update('sync_queue', {'status': 'synced', 'last_error': null, 'response_json': jsonEncode(m), 'updated_at': DateTime.now().toUtc().toIso8601String()}, where: 'operation_id = ?', whereArgs: [op]);
        } else {
          await db.update('sync_queue', {'status': 'synced', 'last_error': null, 'updated_at': DateTime.now().toUtc().toIso8601String()}, where: 'operation_id = ?', whereArgs: [op]);
        }
        completed++;
      } catch (e) {
        final attempts = (row['attempts'] as int? ?? 0) + 1;
        final permanent = e is ApiException && e.statusCode >= 400 && e.statusCode < 500;
        final delay = attempts <= 1 ? 15 : attempts <= 3 ? 60 : attempts <= 6 ? 300 : 900;
        await db.update('sync_queue', {'status': permanent ? 'failed' : 'retry', 'attempts': attempts, 'last_error': e.toString(), 'next_attempt_at': DateTime.now().toUtc().add(Duration(seconds: delay)).toIso8601String(), 'updated_at': DateTime.now().toUtc().toIso8601String()}, where: 'operation_id = ?', whereArgs: [op]);
        final localSaleId = row['local_sale_id'] as int?;
        if (permanent && localSaleId != null) await local.markLocalSaleError(localSaleId, e.toString());
        if (!permanent) break;
      }
    }
    var cursor = int.tryParse(await local.getMeta('sync_cursor') ?? '') ?? 0;
    var downloaded = 0; var more = true;
    while (more) {
      final result = await api.sync(cursor);
      final changes = List<dynamic>.from(result['changes'] as List? ?? const []);
      if (changes.isNotEmpty) { await local.applyChanges(changes); downloaded += changes.length; }
      cursor = int.tryParse('${result['next_cursor'] ?? result['cursor'] ?? cursor}') ?? cursor;
      await local.setMeta('sync_cursor', '$cursor');
      more = result['has_more'] == true;
    }
    return SyncResult(completed: completed, downloaded: downloaded, cursor: cursor);
  }

  Future<int> pendingCount() async => _count("status IN ('pending','retry')");
  Future<int> failedCount() async => _count("status = 'failed'");
  Future<int> _count(String where) async { final db = await local.db; final r = await db.rawQuery('SELECT COUNT(*) c FROM sync_queue WHERE $where'); return (r.first['c'] as int?) ?? 0; }
  Future<void> retryFailed() async { final db = await local.db; await db.update('sync_queue', {'status':'pending','next_attempt_at':null,'updated_at':DateTime.now().toUtc().toIso8601String()}, where:"status='failed'"); }
}

class SyncResult { const SyncResult({required this.completed, required this.downloaded, required this.cursor}); final int completed, downloaded, cursor; }
