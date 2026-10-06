import '../repositories/sales_repository.dart';

class CreateSale {
  const CreateSale(this.repository);

  final SalesRepository repository;

  Future<int> offline({
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    String customerCity = '',
    required String customerState,
    required String paymentStatus,
    required String notes,
    required List<Map<String, dynamic>> items,
    String saleType = 'preorder',
  }) {
    return repository.createOfflineSale(
      customerName: customerName,
      customerPhone: customerPhone,
      customerAddress: customerAddress,
      customerCity: customerCity,
      customerState: customerState,
      paymentStatus: paymentStatus,
      notes: notes,
      items: items,
      saleType: saleType,
    );
  }

  Future<Map<String, dynamic>> online({
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    String customerCity = '',
    required String customerState,
    required String paymentStatus,
    required String notes,
    required List<Map<String, dynamic>> items,
    String saleType = 'preorder',
  }) {
    return repository.createOnlineSale(
      customerName: customerName,
      customerPhone: customerPhone,
      customerAddress: customerAddress,
      customerCity: customerCity,
      customerState: customerState,
      paymentStatus: paymentStatus,
      notes: notes,
      items: items,
      saleType: saleType,
    );
  }
}
