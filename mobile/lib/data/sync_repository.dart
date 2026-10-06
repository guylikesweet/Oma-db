import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'local_database.dart';

class SyncRepository {
  SyncRepository(this.api, this.local);

  final ApiClient api;
  final LocalDatabase local;
  final _uuid = const Uuid();

  Future<String> enqueue(
    String type,
    Map<String, dynamic> payload, {
    String? localSaleId,
    String? dependsOn,
  }) async {
    final op =
        (payload['operation_id']?.toString().isNotEmpty ?? false)
            ? payload['operation_id'].toString()
            : _uuid.v4();

    payload = {
      ...payload,
      'operation_id': op,
      // This marker is sent only by queued offline writes. The server uses it
      // to send a confirmation push after the operation is committed.
      'offline_origin': true,
    };

    final db = await local.db;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.insert('sync_queue', {
      'operation_id': op,
      'operation_type': type,
      'payload_json': jsonEncode(payload),
      'local_sale_id':
          localSaleId == null ? null : int.tryParse(localSaleId),
      'status': 'pending',
      'attempts': 0,
      'created_at': now,
      'updated_at': now,
      'depends_on_operation_id': dependsOn,
    });

    return op;
  }

  Future<void> bootstrapIfNeeded() async {
    if (await local.getMeta('bootstrapped') == '1') {
      return;
    }

    // A bootstrap replaces the server-owned local snapshot. Never do that
    // while offline work is queued: doing so can erase local sales/stock
    // state before those operations reach the server.
    final db = await local.db;
    final pending = await db.query(
      'sync_queue',
      columns: ['local_id'],
      where: "status IN ('pending', 'retry', 'failed')",
      limit: 1,
    );
    if (pending.isNotEmpty) {
      return;
    }

    final data = await api.bootstrap();

    // applyBootstrap is transactional and advances the cursor only after the
    // snapshot has been committed successfully.
    await local.applyBootstrap(data);
    await local.setMeta('bootstrapped', '1');
  }

  Future<int> saveSaleOffline({
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    String customerCity = '',
    required String customerState,
    required String paymentStatus,
    required String notes,
    required List<Map<String, dynamic>> items,
    String saleType = 'preorder',
  }) async {
    final op = _uuid.v4();

    var subtotal = 0.0;

    for (final item in items) {
      subtotal +=
          (double.tryParse('${item['unit_price']}') ?? 0) *
          (item['qty'] as int);
    }

    final payload = {
      'operation_id': op,
      'customer_name': customerName.trim(),
      'customer_phone': customerPhone.trim(),
      'customer_address': customerAddress.trim(),
      'customer_city': customerCity.trim(),
      'customer_state': customerState.trim(),
      'payment_status': paymentStatus,
      'notes': notes.trim(),
      'subtotal_amount': subtotal.toStringAsFixed(2),
      'sale_type': saleType,
      'items': items,
    };

    // Persist the optimistic sale and its durable sync operation in the
    // same SQLite transaction. A process kill between two separate writes
    // must never leave a local sale without a queue entry.
    final localId = await local.createLocalSale(
      payload,
      items,
      queuePayload: payload,
      queueOperationType: 'create_sale',
    );

    return localId;
  }

  /// Used on the web build instead of [saveSaleOffline]. The web app has no
  /// real offline mode — every "local" write there just lives in the
  /// browser tab's IndexedDB, which isn't a database anyone should rely on,
  /// so instead of queuing a placeholder sale (OFF-/OFFSTK-) and reconciling
  /// it later, this posts straight to the server and writes the real,
  /// final sale record locally the moment it comes back — nothing
  /// placeholder-shaped ever exists on screen.
  Future<Map<String, dynamic>> createSaleOnline({
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    String customerCity = '',
    required String customerState,
    required String paymentStatus,
    required String notes,
    required List<Map<String, dynamic>> items,
    String saleType = 'preorder',
  }) async {
    final payload = {
      'operation_id': _uuid.v4(),
      'customer_name': customerName.trim(),
      'customer_phone': customerPhone.trim(),
      'customer_address': customerAddress.trim(),
      'customer_city': customerCity.trim(),
      'customer_state': customerState.trim(),
      'payment_status': paymentStatus,
      'notes': notes.trim(),
      'sale_type': saleType,
      'items': items,
    };

    final sale = await api.createSale(payload);
    await local.upsertSaleFromResponse(sale);
    return sale;
  }

  Future<void> saveStockAdjustment({
    required int productId,
    required int changeQty,
    required String reason,
  }) async {
    final op = _uuid.v4();

    final payload = {
      'operation_id': op,
      'product_id': productId,
      'change_qty': changeQty,
      'reason': reason.trim(),
      'offline_origin': true,
    };

    final db = await local.db;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'products',
        columns: ['stock'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw Exception('Product not found locally.');
      }

      final current = rows.first['stock'] as int? ?? 0;

      if (current + changeQty < 0) {
        throw Exception('Stock cannot go below zero.');
      }

      await txn.rawUpdate(
        'UPDATE products SET stock = stock + ? WHERE id = ?',
        [
          changeQty,
          productId,
        ],
      );

      final now = DateTime.now().toUtc().toIso8601String();

      await txn.insert(
        'sync_queue',
        {
          'operation_id': op,
          'operation_type': 'stock_adjust',
          'payload_json': jsonEncode(payload),
          'status': 'pending',
          'attempts': 0,
          'created_at': now,
          'updated_at': now,
        },
      );
    });
  }

  Future<String> queueCreateBatch(
    String name,
    String notes,
  ) {
    return enqueue(
      'create_batch',
      {
        'name': name.trim(),
        'notes': notes.trim(),
      },
    );
  }

  Future<String> queueBatchSale(
    int batchId,
    int saleId,
  ) {
    return enqueue(
      'batch_sale',
      {
        'batch_id': batchId,
        'sale_id': saleId,
      },
    );
  }

  Future<String> queueBatchArrive(
    int batchId,
  ) {
    return enqueue(
      'batch_arrive',
      {
        'batch_id': batchId,
      },
    );
  }

  Future<String> queueSaleStatus(
    int saleId,
    String status,
  ) async {
    return _queueSaleMutation(
      saleId,
      {
        'sale_id': saleId,
        'status': status,
      },
      localFields: {'order_status': status},
    );
  }

  Future<String> queuePaymentStatus(
    int saleId,
    String paymentStatus,
  ) async {
    // Payment status is part of the same server mutation endpoint, but it
    // must also be reflected locally immediately when the sale has not
    // reached the server yet.
    return _queueSaleMutation(
      saleId,
      {
        'sale_id': saleId,
        'payment_status': paymentStatus,
      },
      localFields: {'payment_status': paymentStatus},
    );
  }

  Future<String> queueSettleShipping(
    int saleId,
  ) async {
    return _queueSaleMutation(
      saleId,
      {
        'sale_id': saleId,
      },
      localFields: {'shipping_payment_settled': 1},
    );
  }

  /// Queue a sale mutation against a possibly-temporary negative local sale
  /// ID. The create_sale operation is recorded as a dependency so the child
  /// operation cannot reach the server until its parent has produced a real
  /// sale ID. The payload is rebound to that real ID during reconciliation.
  Future<String> _queueSaleMutation(
    int saleId,
    Map<String, dynamic> payload, {
    required Map<String, dynamic> localFields,
  }) async {
    String? dependency;
    int? localSaleId;

    if (saleId < 0) {
      final db = await local.db;
      final rows = await db.query(
        'sales',
        columns: ['client_operation_id'],
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('The local sale no longer exists.');
      }
      dependency = rows.first['client_operation_id']?.toString();
      if (dependency == null || dependency.isEmpty) {
        throw StateError('The local sale has no sync operation.');
      }
      localSaleId = saleId;
    }

    final op = await enqueue(
      payload.containsKey('status') ? 'sale_status' : 'sale_status',
      payload,
      localSaleId: localSaleId,
      dependsOn: dependency,
    );

    final db = await local.db;
    await db.update(
      'sales',
      localFields,
      where: 'id = ?',
      whereArgs: [saleId],
    );

    return op;
  }

  Future<String> queueCreateDelivery({
    required List<int> saleIds,
    required String method,
    String? consolidationType,
    String? address,
    String? notes,
  }) async {
    final dependencies = <String>[];
    final localSaleIds = <int>[];
    final db = await local.db;

    for (final saleId in saleIds) {
      if (saleId >= 0) continue;
      final rows = await db.query(
        'sales',
        columns: ['client_operation_id'],
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('A selected local sale no longer exists.');
      }
      final dep = rows.first['client_operation_id']?.toString();
      if (dep == null || dep.isEmpty) {
        throw StateError('A selected local sale has no sync operation.');
      }
      dependencies.add(dep);
      localSaleIds.add(saleId);
    }

    // The queue schema has one dependency slot. A delivery involving
    // multiple unsynced sales depends on the latest parent; all earlier
    // parents are already ordered before it in the queue and therefore must
    // complete first.
    final dependency = dependencies.isEmpty ? null : dependencies.last;
    return enqueue(
      'create_delivery',
      {
        'sale_ids': saleIds,
        'method': method,
        'consolidation_type': consolidationType,
        'delivery_address': address,
        'notes': notes,
      },
      dependsOn: dependency,
    );
  }

  Future<String> queueDeliveryStatus(
    int deliveryId,
    String status,
  ) {
    return enqueue(
      'delivery_status',
      {
        'delivery_id': deliveryId,
        'status': status,
      },
    );
  }

  Future<String> queueCreateShipping({
    required int saleId,
    required String courier,
    required String trackingNumber,
    String? notes,
  }) {
    return enqueue(
      'create_shipping',
      {
        'sale_id': saleId,
        'courier': courier,
        'tracking_number': trackingNumber,
        'notes': notes,
      },
    );
  }

  Future<String> queueUpdateShipping(
    int shippingId,
    Map<String, dynamic> fields,
  ) {
    return enqueue(
      'update_shipping',
      {
        'shipping_id': shippingId,
        ...fields,
      },
    );
  }

  Future<Map<String, dynamic>> createProductOnline({
    required String name,
    String? sku,
    String? cost,
    String? supplierCost,
    String? inboundShippingCost,
    String? markupPercent,
    String? sellingPrice,
    String? lengthCm,
    String? widthCm,
    String? heightCm,
    String? actualWeightKg,
    int stock = 0,
  }) async {
    final payload = {
      'operation_id': _uuid.v4(),
      'name': name.trim(),
      'sku': sku?.trim(),
      'cost': cost,
      'supplier_cost': supplierCost ?? cost,
      'inbound_shipping_cost': inboundShippingCost ?? '0',
      'markup_percent': markupPercent ?? '0',
      'selling_price': sellingPrice ?? '0',
      'length_cm': lengthCm,
      'width_cm': widthCm,
      'height_cm': heightCm,
      'actual_weight_kg': actualWeightKg,
      'stock': stock,
    };

    final result = await api.createProduct(payload);

    await local.applyChanges([
      {
        'entity_type': 'product',
        'entity_id': result['id']?.toString() ?? '',
        'operation': 'upsert',
        'payload': result,
      },
    ]);

    return result;
  }

  Future<Map<String, dynamic>> updateProductOnline(
    int id,
    Map<String, dynamic> fields,
  ) async {
    final result = await api.updateProduct(
      id,
      {
        'operation_id': _uuid.v4(),
        ...fields,
      },
    );

    await local.applyChanges([
      {
        'entity_type': 'product',
        'entity_id': result['id']?.toString() ?? '',
        'operation': 'upsert',
        'payload': result,
      },
    ]);

    return result;
  }

  Future<SyncResult> syncOnce() async {
    await bootstrapIfNeeded();

    final db = await local.db;

    final now = DateTime.now().toUtc();

    final rows = await db.query(
      'sync_queue',
      where:
          "status IN ('pending','retry') "
          "AND (next_attempt_at IS NULL OR next_attempt_at <= ?)",
      whereArgs: [
        now.toIso8601String(),
      ],
      orderBy: 'local_id ASC',
      limit: 50,
    );

    int completed = 0;

    for (final queuedRow in rows) {
      final op = queuedRow['operation_id'].toString();

      final currentRows = await db.query(
        'sync_queue',
        where: 'operation_id = ?',
        whereArgs: [op],
        limit: 1,
      );
      if (currentRows.isEmpty) continue;
      final row = currentRows.first;
      if (row['status'] == 'synced') continue;

      final dependency =
          row['depends_on_operation_id']?.toString();

      if (dependency != null && dependency.isNotEmpty) {
        final dep = await db.query(
          'sync_queue',
          columns: ['status'],
          where: 'operation_id = ?',
          whereArgs: [dependency],
          limit: 1,
        );

        // A dependent operation must never be sent if its prerequisite is
        // missing or has not completed. A missing prerequisite is normally
        // only possible after local data was cleared, and sending the child
        // anyway could create a server-side record with invalid references.
        if (dep.isEmpty || dep.first['status'] != 'synced') {
          continue;
        }
      }

      final type = row['operation_type'].toString();

      final payload = Map<String, dynamic>.from(
        jsonDecode(
          row['payload_json'] as String,
        ) as Map,
      );

      try {
        dynamic response;

        if (type == 'create_sale') {
          response = await api.createSale(payload);
        } else if (type == 'stock_adjust') {
          response = await api.stockAdjust(payload);
        } else if (type == 'create_batch') {
          response = await api.createBatch(payload);
                } else if (type == 'batch_sale') {
          response = await api.addSaleToBatch(
            payload['batch_id'] as int,
            payload['sale_id'] as int,
            {
              'operation_id': op,
            },
          );
        } else if (type == 'batch_arrive') {
          response = await api.arriveBatch(
            payload['batch_id'] as int,
            {
              'operation_id': op,
            },
          );
        } else if (type == 'sale_status') {
          response = await api.updateSaleStatus(
            payload['sale_id'] as int,
            payload,
          );
        } else if (type == 'settle_shipping') {
          response = await api.settleShipping(
            payload['sale_id'] as int,
            {
              'operation_id': op,
            },
          );
        } else if (type == 'create_delivery') {
          response = await api.createDelivery(payload);
        } else if (type == 'delivery_status') {
          response = await api.updateDeliveryStatus(
            payload['delivery_id'] as int,
            payload,
          );
        } else if (type == 'create_shipping') {
          response = await api.createShipping(payload);
        } else if (type == 'update_shipping') {
          response = await api.updateShipping(
            payload['shipping_id'] as int,
            payload,
          );
        } else {
          throw Exception(
            'Unsupported queued operation: $type',
          );
        }

        if (response is Map) {
          final m = Map<String, dynamic>.from(response);

          final entityType =
              type.contains('delivery')
                  ? 'delivery'
                  : type.contains('shipping') ||
                          type.contains('settle_shipping')
                      ? (type == 'settle_shipping'
                          ? 'sale'
                          : 'shipping')
                      : type.contains('batch')
                          ? 'shipment_batch'
                          : type == 'stock_adjust'
                              ? 'product'
                              : type.contains('sale')
                                  ? 'sale'
                                  : null;

          if (entityType != null) {
            await local.applyChanges([
              {
                'entity_type': entityType,
                'entity_id':
                    m['id']?.toString() ?? '',
                'operation': 'upsert',
                'payload': m,
              },
            ]);
          }

          await db.update(
            'sync_queue',
            {
              'status': 'synced',
              'last_error': null,
              'response_json': jsonEncode(m),
              'updated_at':
                  DateTime.now()
                      .toUtc()
                      .toIso8601String(),
            },
            where: 'operation_id = ?',
            whereArgs: [op],
          );
        } else {
          await db.update(
            'sync_queue',
            {
              'status': 'synced',
              'last_error': null,
              'updated_at':
                  DateTime.now()
                      .toUtc()
                      .toIso8601String(),
            },
            where: 'operation_id = ?',
            whereArgs: [op],
          );
        }

        completed++;
      } catch (e) {
        final attempts =
            (row['attempts'] as int? ?? 0) + 1;

        final errorText = e.toString();

        final permanent =
            errorText.startsWith('API 4');

        final delay =
            attempts <= 1
                ? 15
                : attempts <= 3
                    ? 60
                    : attempts <= 6
                        ? 300
                        : 900;

        await db.update(
          'sync_queue',
          {
            'status':
                permanent ? 'failed' : 'retry',
            'attempts': attempts,
            'last_error': errorText,
            'next_attempt_at':
                DateTime.now()
                    .toUtc()
                    .add(
                      Duration(
                        seconds: delay,
                      ),
                    )
                    .toIso8601String(),
            'updated_at':
                DateTime.now()
                    .toUtc()
                    .toIso8601String(),
          },
          where: 'operation_id = ?',
          whereArgs: [op],
        );

        final localSaleId =
            row['local_sale_id'] as int?;

        if (permanent && localSaleId != null) {
          await local.markLocalSaleError(
            localSaleId,
            errorText,
          );
        }

        // A queued stock adjustment is applied optimistically to the local
        // inventory before it reaches the server. If the server permanently
        // rejects it, undo that optimistic change; otherwise local stock can
        // remain wrong until a later full bootstrap.
        if (permanent && type == 'stock_adjust') {
          await rollbackFailedStockAdjustment(payload);
        }

        if (!permanent) {
          break;
        }
      }
    }

    var cursor =
        int.tryParse(
              await local.getMeta('sync_cursor') ?? '',
            ) ??
            0;

    var downloaded = 0;
    var more = true;

    while (more) {
      final result = await api.sync(cursor);

      final changes = List<dynamic>.from(
        result['changes'] as List? ?? const [],
      );

      if (changes.isNotEmpty) {
        await local.applyChanges(changes);
        downloaded += changes.length;
      }

      cursor =
          int.tryParse(
                '${result['next_cursor'] ?? result['cursor'] ?? cursor}',
              ) ??
              cursor;

      await local.setMeta(
        'sync_cursor',
        '$cursor',
      );

      more = result['has_more'] == true;
    }

    return SyncResult(
      completed: completed,
      downloaded: downloaded,
      cursor: cursor,
    );
  }

  Future<int> pendingCount() async {
    return _count(
      "status IN ('pending','retry')",
    );
  }

  Future<int> failedCount() async {
    return _count(
      "status = 'failed'",
    );
  }

  Future<int> _count(String where) async {
    final db = await local.db;

    final result = await db.rawQuery(
      'SELECT COUNT(*) c '
      'FROM sync_queue '
      'WHERE $where',
    );

    return (result.first['c'] as int?) ?? 0;
  }

  Future<void> rollbackFailedStockAdjustment(Map<String, dynamic> payload) async {
    final productId = int.tryParse('${payload['product_id']}');
    final changeQty = int.tryParse('${payload['change_qty']}');
    if (productId == null || changeQty == null || changeQty == 0) return;

    final db = await local.db;
    await db.rawUpdate(
      'UPDATE products SET stock = stock - ? WHERE id = ?',
      [changeQty, productId],
    );
  }

  Future<void> retryFailed() async {
    final db = await local.db;

    await db.update(
      'sync_queue',
      {
        'status': 'pending',
        'next_attempt_at': null,
        'updated_at':
            DateTime.now()
                .toUtc()
                .toIso8601String(),
      },
      where: "status = 'failed'",
    );
  }
}

class SyncResult {
  const SyncResult({
    required this.completed,
    required this.downloaded,
    required this.cursor,
  });

  final int completed;
  final int downloaded;
  final int cursor;
}
