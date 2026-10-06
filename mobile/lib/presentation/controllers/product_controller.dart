import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/product_repository.dart';
import '../providers/app_providers.dart';

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepositoryImplAdapter(ref.watch(localDatabaseProvider));
});

final productsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, bool>((ref, stockedOnly) {
  return ref.watch(productRepositoryProvider).list(
        stockedOnly: stockedOnly,
      );
});

final productsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, bool>((ref, stockedOnly) {
  return ref.watch(productRepositoryProvider).list(
        stockedOnly: stockedOnly,
      );
});
