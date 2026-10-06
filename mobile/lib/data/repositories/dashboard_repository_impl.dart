import '../../domain/entities/dashboard_snapshot.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../api_client.dart';
import '../local_database.dart';
import '../sync_repository.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  const DashboardRepositoryImpl(this.api, this.local, this.sync);

  final ApiClient api;
  final LocalDatabase local;
  final SyncRepository sync;

  @override
  Future<DashboardSnapshot> load() async {
    final db = await local.db;

    // Local state is read first, so the UI never has to wait for the network
    // before it can render useful inventory/sales information.
    final productCountRows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM products',
    );
    final saleCountRows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM sales',
    );
    final low = await db.query(
      'products',
      where: 'stock <= ?',
      whereArgs: [5],
      orderBy: 'stock ASC, name ASC',
      limit: 8,
    );
    final productCount =
        (productCountRows.first['count'] as num?)?.toInt() ?? 0;
    final saleCount =
        (saleCountRows.first['count'] as num?)?.toInt() ?? 0;
    final pending = await sync.pendingCount();

    final localData = <String, dynamic>{
      'sales_today': 0,
      'profit_today': 0,
      'pending_shipments': 0,
      'shipping_owed': 0,
      'batches_in_transit': 0,
      'sync_exceptions': 0,
      'low_stock_count': low.length,
      'low_stock_products': low,
      'local_counts': {
        'products': productCount,
        'sales': saleCount,
      },
    };

    try {
      final remote = await api.dashboard();
      return DashboardSnapshot(
        data: {
          ...localData,
          ...remote,
          'low_stock_products': low,
          'local_counts': {
            'products': productCount,
            'sales': saleCount,
          },
        },
        pendingOperations: pending,
        fromLocalData: false,
      );
    } catch (_) {
      return DashboardSnapshot(
        data: localData,
        pendingOperations: pending,
        fromLocalData: true,
      );
    }
  }
}
