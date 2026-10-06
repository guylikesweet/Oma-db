import 'package:flutter_test/flutter_test.dart';

import 'package:oma_mobile/domain/entities/session_state.dart';
import 'package:oma_mobile/domain/repositories/sales_repository.dart';
import 'package:oma_mobile/domain/usecases/create_sale.dart';

class _FakeSalesRepository implements SalesRepository {
  Map<String, dynamic>? onlinePayload;
  Map<String, dynamic>? offlinePayload;

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
    offlinePayload = {
      'customer_name': customerName,
      'items': items,
      'sale_type': saleType,
    };
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
    onlinePayload = {
      'customer_name': customerName,
      'items': items,
      'sale_type': saleType,
    };
    return {'id': 7};
  }
}

void main() {
  test('SessionState exposes role capabilities without UI state', () {
    const state = SessionState(
      userId: 7,
      username: 'francis',
      role: 'admin',
      isPrimaryAdmin: true,
      authenticated: true,
    );

    expect(state.authenticated, isTrue);
    expect(state.isAdmin, isTrue);
    expect(state.isPrimaryAdmin, isTrue);
  });

  test('CreateSale use case delegates offline writes to the domain repository', () async {
    final repository = _FakeSalesRepository();
    final useCase = CreateSale(repository);

    final id = await useCase.offline(
      customerName: 'Customer',
      customerPhone: '08000000000',
      customerAddress: 'Address',
      customerState: 'Enugu',
      paymentStatus: 'Paid',
      notes: '',
      items: [
        {'product_id': 1, 'qty': 2, 'unit_price': '100.00'},
      ],
      saleType: 'stock',
    );

    expect(id, 42);
    expect(repository.offlinePayload?['customer_name'], 'Customer');
    expect(repository.offlinePayload?['sale_type'], 'stock');
  });

  test('CreateSale use case keeps online and offline writes separate', () async {
    final repository = _FakeSalesRepository();
    final useCase = CreateSale(repository);

    final result = await useCase.online(
      customerName: 'Customer',
      customerPhone: '08000000000',
      customerAddress: 'Address',
      customerState: 'Lagos',
      paymentStatus: 'Paid',
      notes: '',
      items: [
        {'product_id': 2, 'qty': 1, 'unit_price': '250.00'},
      ],
    );

    expect(result['id'], 7);
    expect(repository.onlinePayload?['sale_type'], 'preorder');
    expect(repository.offlinePayload, isNull);
  });
}
