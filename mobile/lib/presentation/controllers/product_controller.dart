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

class ProductRepositoryImplAdapter implements ProductRepository {
  const ProductRepositoryImplAdapter(this.local);

  final dynamic local;

  @override
  Future<List<Map<String, dynamic>>> list({
    required bool stockedOnly,
  }) async {
    final db = await local.db;
    return db.query(
      'products',
      where: stockedOnly ? 'stock > 0' : null,
      orderBy: 'name ASC',
    );
  }
}
