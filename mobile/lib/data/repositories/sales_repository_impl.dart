import '../sync_repository.dart';
import '../../domain/repositories/sales_repository.dart';

class SalesRepositoryImpl implements SalesRepository {
  const SalesRepositoryImpl(this.repository);

  final SyncRepository repository;

  @override
  Future<int> createOfflineSale({
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
    return repository.saveSaleOffline(
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

  @override
  Future<Map<String, dynamic>> createOnlineSale({
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
    return repository.createSaleOnline(
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
