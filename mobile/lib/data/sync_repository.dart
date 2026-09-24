import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'local_database.dart';

class SyncRepository {
  SyncRepository(
    this.api,
    this.local,
  );

  final ApiClient api;
  final LocalDatabase local;

  final Uuid _uuid = const Uuid();

  // ============================================================
  // QUEUE
  // ============================================================

  Future<String> enqueue(
    String type,
    Map<String, dynamic> payload, {
    String? localSaleId,
    String? dependsOn,
  }) async {
    final existingOperationId =
        payload['operation_id']?.toString();

    final operationId =
        existingOperationId != null &&
                existingOperationId.isNotEmpty
            ? existingOperationId
            : _uuid.v4();

    payload = {
      ...payload,
      'operation_id': operationId,
    };

    final db = await local.db;

    final now =
        DateTime.now().toUtc().toIso8601String();

    await db.insert(
      'sync_queue',
      {
        'operation_id': operationId,
        'operation_type': type,
        'payload_json': jsonEncode(payload),
        'local_sale_id': localSaleId == null
            ? null
            : int.tryParse(localSaleId),
        'status': 'pending',
        'attempts': 0,
        'created_at': now,
        'updated_at': now,
        'depends_on_operation_id': dependsOn,
      },
    );

    return operationId;
  }

  // ============================================================
  // BOOTSTRAP
  // ============================================================

  Future<void> bootstrapIfNeeded() async {
    final bootstrapped =
        await local.getMeta('bootstrapped');

    if (bootstrapped == '1') {
      return;
    }

    final data = await api.bootstrap();

    await local.applyBootstrap(data);

    await local.setMeta(
      'bootstrapped',
      '1',
    );
  }

  // ============================================================
  // OFFLINE SALES
  // ============================================================

  Future<int> saveSaleOffline({
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    required String customerState,
    required String paymentStatus,
    required String notes,
    required List<Map<String, dynamic>> items,
  }) async {
    final operationId = _uuid.v4();

    var subtotal = 0.0;

    for (final item in items) {
      final unitPrice =
          double.tryParse(
                '${item['unit_price']}',
              ) ??
              0;

      final qty =
          item['qty'] as int;

      subtotal += unitPrice * qty;
    }

    final payload = {
      'operation_id': operationId,
      'customer_name': customerName.trim(),
      'customer_phone': customerPhone.trim(),
      'customer_address': customerAddress.trim(),
      'customer_state': customerState.trim(),
      'payment_status': paymentStatus,
      'notes': notes.trim(),
      'subtotal_amount':
          subtotal.toStringAsFixed(2),
      'items': items,
    };

    final localId =
        await local.createLocalSale(
      payload,
      items,
    );

    await enqueue(
      'create_sale',
      payload,
      localSaleId: '$localId',
    );

    return localId;
  }

  // ============================================================
  // STOCK
  // ============================================================

  Future<void> saveStockAdjustment({
    required int productId,
    required int changeQty,
    required String reason,
  }) async {
    final operationId = _uuid.v4();

    final payload = {
      'operation_id': operationId,
      'product_id': productId,
      'change_qty': changeQty,
      'reason': reason.trim(),
    };

    final db = await local.db;

    await db.transaction(
      (txn) async {
        final rows = await txn.query(
          'products',
          columns: ['stock'],
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );

        if (rows.isEmpty) {
          throw Exception(
            'Product not found locally.',
          );
        }

        final current =
            rows.first['stock'] as int? ?? 0;

        if (current + changeQty < 0) {
          throw Exception(
            'Stock cannot go below zero.',
          );
        }

        await txn.rawUpdate(
          '''
          UPDATE products
          SET stock = stock + ?
          WHERE id = ?
          ''',
          [
            changeQty,
            productId,
          ],
        );

        final now =
            DateTime.now()
                .toUtc()
                .toIso8601String();

        await txn.insert(
          'sync_queue',
          {
            'operation_id': operationId,
            'operation_type': 'stock_adjust',
            'payload_json':
                jsonEncode(payload),
            'status': 'pending',
            'attempts': 0,
            'created_at': now,
            'updated_at': now,
          },
        );
      },
    );
  }

  // ============================================================
  // BATCH QUEUES
  // ============================================================

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

  // ============================================================
  // SALE STATUS
  // ============================================================

  Future<String> queueSaleStatus(
    int saleId,
    String status,
  ) async {
    final db = await local.db;

    String? dependency;

    final saleRows = await db.query(
      'sales',
      columns: [
        'client_operation_id',
        'order_status',
      ],
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    );

    if (saleRows.isEmpty) {
      throw Exception(
        'Sale not found locally.',
      );
    }

    final clientOperationId =
        saleRows.first['client_operation_id']
            ?.toString();

    if (clientOperationId != null &&
        clientOperationId.isNotEmpty) {
      final queueRows = await db.query(
        'sync_queue',
        columns: ['operation_id'],
        where: 'operation_id = ?',
        whereArgs: [clientOperationId],
        limit: 1,
      );

      if (queueRows.isNotEmpty) {
        dependency = clientOperationId;
      }
    }

    final operationId = await enqueue(
      'sale_status',
      {
        'sale_id': saleId,
        'status': status,
      },
      dependsOn: dependency,
    );

    await db.transaction(
      (txn) async {
        if (status == 'Cancelled' &&
            saleRows.first['order_status'] !=
                'Cancelled') {
          final items = await txn.query(
            'sale_items',
            where: 'sale_id = ?',
            whereArgs: [saleId],
          );

          for (final item in items) {
            await txn.rawUpdate(
              '''
              UPDATE products
              SET stock = stock + ?
              WHERE id = ?
              ''',
              [
                item['qty'],
                item['product_id'],
              ],
            );
          }
        }

        await txn.update(
          'sales',
          {
            'order_status': status,
            'sync_error': null,
          },
          where: 'id = ?',
          whereArgs: [saleId],
        );
      },
    );

    return operationId;
  }

  // ============================================================
  // OTHER QUEUED OPERATIONS
  // ============================================================

  Future<String> queueSettleShipping(
    int saleId,
  ) {
    return enqueue(
      'settle_shipping',
      {
        'sale_id': saleId,
      },
    );
  }

  Future<String> queueCreateDelivery({
    required List<int> saleIds,
    required String method,
    String? consolidationType,
    String? address,
    String? notes,
  }) {
    return enqueue(
      'create_delivery',
      {
        'sale_ids': saleIds,
        'method': method,
        'consolidation_type':
            consolidationType,
        'delivery_address': address,
        'notes': notes,
      },
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

  // ============================================================
  // ONLINE PRODUCT OPERATIONS
  // ============================================================

  Future<Map<String, dynamic>>
      createProductOnline({
    required String name,
    String? sku,
    String? cost,
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
      'length_cm': lengthCm,
      'width_cm': widthCm,
      'height_cm': heightCm,
      'actual_weight_kg':
          actualWeightKg,
      'stock': stock,
    };

    final result =
        await api.createProduct(payload);

    await local.applyChanges(
      [
        {
          'entity_type': 'product',
          'entity_id': result['id'],
          'operation': 'upsert',
          'payload': result,
        },
      ],
    );

    return result;
  }

  Future<Map<String, dynamic>>
      updateProductOnline(
    int id,
    Map<String, dynamic> fields,
  ) async {
    final result =
        await api.updateProduct(
      id,
      {
        'operation_id': _uuid.v4(),
        ...fields,
      },
    );

    await local.applyChanges(
      [
        {
          'entity_type': 'product',
          'entity_id': result['id'],
          'operation': 'upsert',
          'payload': result,
        },
      ],
    );

    return result;
  }

  // ============================================================
  // SYNC
  // ============================================================

  Future<SyncResult> syncOnce() async {
    await bootstrapIfNeeded();

    final db = await local.db;

    final now =
        DateTime.now().toUtc();

    final rows = await db.query(
      'sync_queue',
      where:
          "status IN ('pending','retry') "
          'AND (next_attempt_at IS NULL '
          'OR next_attempt_at <= ?)',
      whereArgs: [
        now.toIso8601String(),
      ],
      orderBy: 'local_id ASC',
      limit: 50,
    );

    var completed = 0;

    for (final row in rows) {
      final operationId =
          row['operation_id'].toString();

      final dependency =
          row['depends_on_operation_id']
              ?.toString();

      if (dependency != null &&
          dependency.isNotEmpty) {
        final dependencyRows =
            await db.query(
          'sync_queue',
          columns: ['status'],
          where: 'operation_id = ?',
          whereArgs: [dependency],
          limit: 1,
        );

        if (dependencyRows.isNotEmpty &&
            dependencyRows.first['status'] !=
                'synced') {
          continue;
        }
      }

      final type =
          row['operation_type'].toString();

      var payload =
          Map<String, dynamic>.from(
        jsonDecode(
          row['payload_json'] as String,
        ) as Map,
      );

      final dependencyId =
          row['depends_on_operation_id']
              ?.toString();

      if (dependencyId != null &&
          dependencyId.isNotEmpty &&
          type == 'sale_status') {
        final dependencyRows =
            await db.query(
          'sync_queue',
          columns: [
            'response_json',
            'status',
          ],
          where: 'operation_id = ?',
          whereArgs: [dependencyId],
          limit: 1,
        );

        if (dependencyRows.isNotEmpty &&
            dependencyRows.first['status'] ==
                'synced' &&
            dependencyRows.first[
                    'response_json'] !=
                null) {
          final dependencyResponse =
              jsonDecode(
            dependencyRows.first[
                    'response_json']
                as String,
          );

          if (dependencyResponse is Map &&
              dependencyResponse['id'] !=
                  null) {
            payload['sale_id'] =
                dependencyResponse['id'];
          }
        }
      }

      try {
        dynamic response;

        if (type == 'create_sale') {
          response =
              await api.createSale(
            payload,
          );
        } else if (type ==
            'stock_adjust') {
          response =
              await api.stockAdjust(
            payload,
          );
        } else if (type ==
            'create_batch') {
          response =
              await api.createBatch(
            payload,
          );
        } else if (type ==
            'batch_sale') {
          response =
              await api.addSaleToBatch(
            payload['batch_id'] as int,
            payload['sale_id'] as int,
            {
              'operation_id':
                  operationId,
            },
          );
        } else if (type ==
            'batch_arrive') {
          response =
              await api.arriveBatch(
            payload['batch_id'] as int,
            {
              'operation_id':
                  operationId,
            },
          );
        } else if (type ==
            'sale_status') {
          response =
              await api.updateSaleStatus(
            payload['sale_id'] as int,
            payload,
          );
        } else if (type ==
            'settle_shipping') {
          response =
              await api.settleShipping(
            payload['sale_id'] as int,
            {
              'operation_id':
                  operationId,
            },
          );
        } else if (type ==
            'create_delivery') {
          response =
              await api.createDelivery(
            payload,
          );
        } else if (type ==
            'delivery_status') {
          response =
              await api.updateDeliveryStatus(
            payload['delivery_id'] as int,
            payload,
          );
        } else if (type ==
            'create_shipping') {
          response =
              await api.createShipping(
            payload,
          );
        } else if (type ==
            'update_shipping') {
          response =
              await api.updateShipping(
            payload['shipping_id'] as int,
            payload,
          );
        } else {
          throw Exception(
            'Unsupported queued operation: '
            '$type',
          );
        }

        if (response is Map) {
          final map =
              Map<String, dynamic>.from(
            response,
          );

          String? entityType;

          if (type.contains('delivery')) {
            entityType = 'delivery';
          } else if (type.contains('shipping')) {
            entityType =
                type == 'settle_shipping'
                    ? 'sale'
                    : 'shipping';
          } else if (type.contains('batch')) {
            entityType =
                'shipment_batch';
          } else if (type == 'stock_adjust') {
            entityType = 'product';
          } else if (type.contains('sale')) {
            entityType = 'sale';
          }

          if (entityType != null) {
            await local.applyChanges(
              [
                {
                  'entity_type':
                      entityType,
                  'entity_id':
                      map['id']
                              ?.toString() ??
                          '',
                  'operation':
                      'upsert',
                  'payload': map,
                },
              ],
            );
          }

          await db.update(
            'sync_queue',
            {
              'status': 'synced',
              'last_error': null,
              'response_json':
                  jsonEncode(map),
              'updated_at':
                  DateTime.now()
                      .toUtc()
                      .toIso8601String(),
            },
            where:
                'operation_id = ?',
            whereArgs: [
              operationId,
            ],
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
            where:
                'operation_id = ?',
            whereArgs: [
              operationId,
            ],
          );
        }

        completed++;
      } catch (e) {
        final attempts =
            (row['attempts'] as int? ??
                    0) +
                1;

        final permanent =
            e is ApiException &&
                e.statusCode >= 400 &&
                e.statusCode < 500;

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
            'status': permanent
                ? 'failed'
                : 'retry',
            'attempts': attempts,
            'last_error':
                e.toString(),
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
          where:
              'operation_id = ?',
          whereArgs: [
            operationId,
          ],
        );

        final localSaleId =
            row['local_sale_id'] as int?;

        if (permanent &&
            localSaleId != null) {
          await local.markLocalSaleError(
            localSaleId,
            e.toString(),
          );
        }

        if (!permanent) {
          break;
        }
      }
    }

    var cursor =
        int.tryParse(
              await local.getMeta(
                    'sync_cursor',
                  ) ??
                  '',
            ) ??
            0;

    var downloaded = 0;
    var more = true;

    while (more) {
      final result =
          await api.sync(cursor);

      final changes =
          List<dynamic>.from(
        result['changes']
                as List? ??
            const [],
      );

      if (changes.isNotEmpty) {
        await local.applyChanges(
          changes,
        );

        downloaded +=
            changes.length;
      }

      cursor =
          int.tryParse(
                '${result['cursor'] ?? result['next_cursor'] ?? cursor}',
              ) ??
              cursor;

      await local.setMeta(
        'sync_cursor',
        '$cursor',
      );

      more =
          result['has_more'] == true;
    }

    return SyncResult(
      completed: completed,
      downloaded: downloaded,
      cursor: cursor,
    );
  }

  // ============================================================
  // QUEUE STATUS
  // ============================================================

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

  Future<int> _count(
    String where,
  ) async {
    final db = await local.db;

    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) c
      FROM sync_queue
      WHERE $where
      ''',
    );

    return (rows.first['c'] as int?) ?? 0;
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
