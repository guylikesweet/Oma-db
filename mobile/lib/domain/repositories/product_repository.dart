abstract interface class ProductRepository {
  Future<List<Map<String, dynamic>>> list({
    required bool stockedOnly,
  });
}
