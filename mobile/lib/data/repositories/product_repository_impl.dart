import '../../domain/repositories/product_repository.dart';
import '../local_database.dart';

class ProductRepositoryImpl implements ProductRepository {
  const ProductRepositoryImpl(this.local);

  final LocalDatabase local;

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
