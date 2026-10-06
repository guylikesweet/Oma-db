import 'package:flutter_test/flutter_test.dart';

import '../lib/domain/repositories/sales_repository.dart';
import '../lib/domain/usecases/create_sale.dart';

class _FakeSalesRepository implements SalesRepository {
  Map<String, dynamic>? lastOnline;
  int calls = 0;

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
  }) async {
    calls++;
    return 42;
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
  }) async {
    lastOnline = {
      'customer_name': customerName,
      'customer_city': customerCity,
      'sale_type': saleType,
    };
    return lastOnline!;
  }
}

void main() {
  test('CreateSale delegates offline writes to the repository boundary', () async {
    final repo = _FakeSalesRepository();
    final useCase = CreateSale(repo);

    final id = await useCase.offline(
      customerName: 'Test Customer',
      customerPhone: '08000000000',
      customerAddress: 'Test address',
      customerState: 'Enugu',
      paymentStatus: 'paid',
      notes: 'Offline test',
      items: const [
        {'product_id': 1, 'qty': 2, 'unit_price': 1000},
      ],
      saleType: 'stock',
    );

    expect(id, 42);
    expect(repo.calls, 1);
  });

  test('CreateSale preserves online sale input through the repository boundary', () async {
    final repo = _FakeSalesRepository();
    final useCase = CreateSale(repo);

    final result = await useCase.online(
      customerName: 'Jane',
      customerPhone: '08100000000',
      customerAddress: 'Address',
      customerCity: 'Enugu',
      customerState: 'Enugu',
      paymentStatus: 'pending',
      notes: 'Online test',
      items: const [],
      saleType: 'preorder',
    );

    expect(result['customer_name'], 'Jane');
    expect(result['customer_city'], 'Enugu');
    expect(result['sale_type'], 'preorder');
  });
}
