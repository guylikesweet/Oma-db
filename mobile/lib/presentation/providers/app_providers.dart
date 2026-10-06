import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/local_database.dart';
import '../../data/repositories/dashboard_repository_impl.dart';
import '../../data/repositories/product_repository_impl.dart';
import '../../data/repositories/sales_repository_impl.dart';
import '../../data/repositories/session_repository_impl.dart';
import '../../data/sync_repository.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/sales_repository.dart';
import '../../domain/repositories/session_repository.dart';
import '../../domain/usecases/create_sale.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final localDatabaseProvider =
    Provider<LocalDatabase>((ref) => LocalDatabase.instance);

final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  return SyncRepository(
    ref.watch(apiClientProvider),
    ref.watch(localDatabaseProvider),
  );
});

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return SessionRepositoryImpl(ref.watch(apiClientProvider));
});

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepositoryImpl(
    ref.watch(apiClientProvider),
    ref.watch(localDatabaseProvider),
    ref.watch(syncRepositoryProvider),
  );
});

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  return SalesRepositoryImpl(ref.watch(syncRepositoryProvider));
});

final createSaleProvider = Provider<CreateSale>((ref) {
  return CreateSale(ref.watch(salesRepositoryProvider));
});


final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepositoryImpl(ref.watch(localDatabaseProvider));
});
