abstract interface class SalesRepository {
  Future<int> createOfflineSale({
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    String customerCity,
    required String customerState,
    required String paymentStatus,
    required String notes,
    required List<Map<String, dynamic>> items,
    String saleType,
  });

  Future<Map<String, dynamic>> createOnlineSale({
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    String customerCity,
    required String customerState,
    required String paymentStatus,
    required String notes,
    required List<Map<String, dynamic>> items,
    String saleType,
  });
}
