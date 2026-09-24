import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';

class ApiClient {
  ApiClient();

  final FlutterSecureStorage _storage =
      const FlutterSecureStorage();

  String get baseUrl => AppConfig.apiBaseUrl;

  Future<String?> token() async {
    return _storage.read(key: 'api_token');
  }

  Future<void> saveToken(String value) async {
    await _storage.write(
      key: 'api_token',
      value: value,
    );
  }

  Future<void> clearToken() async {
    await _storage.delete(
      key: 'api_token',
    );
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    final uri = Uri.parse(
      '$baseUrl$path',
    );

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (authenticated) {
      final t = await token();

      if (t != null && t.isNotEmpty) {
        headers['Authorization'] = 'Bearer $t';
      }
    }

    late http.Response response;

    switch (method.toUpperCase()) {
      case 'GET':
        response = await http.get(
          uri,
          headers: headers,
        );
        break;

      case 'POST':
        response = await http.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
        break;

      case 'PUT':
        response = await http.put(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
        break;

      case 'PATCH':
        response = await http.patch(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
        break;

      case 'DELETE':
        response = await http.delete(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
        break;

      default:
        throw Exception(
          'Unsupported HTTP method: $method',
        );
    }

    dynamic decoded;

    if (response.body.isEmpty) {
      decoded = <String, dynamic>{};
    } else {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = response.body;
      }
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      String message = 'Request failed (${response.statusCode})';

      if (decoded is Map<String, dynamic>) {
        message =
            decoded['error']?.toString() ??
            decoded['message']?.toString() ??
            message;
      } else if (decoded is String &&
          decoded.trim().isNotEmpty) {
        message = decoded;
      }

      throw Exception(message);
    }

    return decoded;
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return <String, dynamic>{};
  }

  List<dynamic> _list(dynamic value) {
    if (value is List) {
      return value;
    }

    if (value is Map<String, dynamic>) {
      final data = value['data'];

      if (data is List) {
        return data;
      }

      final items = value['items'];

      if (items is List) {
        return items;
      }
    }

    return <dynamic>[];
  }

  // ============================================================
  // AUTH
  // ============================================================

  Future<Map<String, dynamic>> login(
    String username,
    String password,
  ) async {
    final result = _map(
      await _request(
        'POST',
        '/v1/auth/login',
        body: {
          'username': username,
          'password': password,
        },
        authenticated: false,
      ),
    );

    final tokenValue =
        result['token']?.toString();

    if (tokenValue != null &&
        tokenValue.isNotEmpty) {
      await saveToken(tokenValue);
    }

    return result;
  }

  Future<Map<String, dynamic>> me() async {
    return _map(
      await _request(
        'GET',
        '/v1/auth/me',
      ),
    );
  }

  Future<Map<String, dynamic>> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    return _map(
      await _request(
        'POST',
        '/v1/auth/change-password',
        body: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      ),
    );
  }

  Future<void> logout() async {
    try {
      await _request(
        'POST',
        '/v1/auth/logout',
      );
    } finally {
      await clearToken();
    }
  }

  // ============================================================
  // SYNC
  // ============================================================

  Future<Map<String, dynamic>> bootstrap() async {
    return _map(
      await _request(
        'GET',
        '/v1/bootstrap',
      ),
    );
  }

  Future<Map<String, dynamic>> sync(
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'POST',
        '/v1/sync',
        body: payload,
      ),
    );
  }

  // ============================================================
  // DASHBOARD
  // ============================================================

  Future<Map<String, dynamic>> dashboard() async {
    return _map(
      await _request(
        'GET',
        '/v1/dashboard',
      ),
    );
  }

  // ============================================================
  // PRODUCTS
  // ============================================================

  Future<List<dynamic>> products() async {
    return _list(
      await _request(
        'GET',
        '/v1/products',
      ),
    );
  }

  Future<Map<String, dynamic>> createProduct(
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'POST',
        '/v1/products',
        body: payload,
      ),
    );
  }

  Future<Map<String, dynamic>> updateProduct(
    int id,
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'PUT',
        '/v1/products/$id',
        body: payload,
      ),
    );
  }

  Future<Map<String, dynamic>> deleteProduct(
    int id,
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'DELETE',
        '/v1/products/$id',
        body: payload,
      ),
    );
  }

  Future<Map<String, dynamic>> stockAdjust(
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'POST',
        '/v1/products/stock-adjust',
        body: payload,
      ),
    );
  }

  Future<List<dynamic>> stockLogs({
    int? productId,
  }) async {
    final path = productId == null
        ? '/v1/stock-log'
        : '/v1/stock-log?product_id=$productId';

    return _list(
      await _request(
        'GET',
        path,
      ),
    );
  }

  Future<List<dynamic>> stockLog() async {
    return stockLogs();
  }

  // ============================================================
  // SALES
  // ============================================================

  Future<List<dynamic>> sales() async {
    return _list(
      await _request(
        'GET',
        '/v1/sales',
      ),
    );
  }

  Future<Map<String, dynamic>> sale(
    int id,
  ) async {
    return saleDetail(id);
  }

  Future<Map<String, dynamic>> saleDetail(
    int id,
  ) async {
    return _map(
      await _request(
        'GET',
        '/v1/sales/$id',
      ),
    );
  }

  Future<Map<String, dynamic>> createSale(
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'POST',
        '/v1/sales',
        body: payload,
      ),
    );
  }

  Future<Map<String, dynamic>> updateSaleStatus(
    int id,
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'PUT',
        '/v1/sales/$id/status',
        body: payload,
      ),
    );
  }

  Future<Map<String, dynamic>> settleShipping(
    int id,
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'POST',
        '/v1/sales/$id/settle-shipping',
        body: payload,
      ),
    );
  }

  // ============================================================
  // BATCHES
  // ============================================================

  Future<List<dynamic>> batches() async {
    return _list(
      await _request(
        'GET',
        '/v1/batches',
      ),
    );
  }

  Future<Map<String, dynamic>> batch(
    int id,
  ) async {
    return _map(
      await _request(
        'GET',
        '/v1/batches/$id',
      ),
    );
  }

  Future<Map<String, dynamic>> createBatch(
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'POST',
        '/v1/batches',
        body: payload,
      ),
    );
  }

  Future<Map<String, dynamic>> addSaleToBatch(
    int batchId,
    int saleId,
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'POST',
        '/v1/batches/$batchId/sales/$saleId',
        body: payload,
      ),
    );
  }

  Future<Map<String, dynamic>> removeSaleFromBatch(
    int batchId,
    int saleId,
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'DELETE',
        '/v1/batches/$batchId/sales/$saleId',
        body: payload,
      ),
    );
  }

  Future<Map<String, dynamic>> arriveBatch(
    int id,
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'POST',
        '/v1/batches/$id/arrive',
        body: payload,
      ),
    );
  }

  // ============================================================
  // DELIVERIES / LABELS
  // ============================================================

  Future<List<dynamic>> deliveries() async {
    return _list(
      await _request(
        'GET',
        '/v1/deliveries',
      ),
    );
  }

  Future<List<dynamic>> readyDeliveries() async {
    return _list(
      await _request(
        'GET',
        '/v1/deliveries/ready',
      ),
    );
  }

  Future<Map<String, dynamic>> createDelivery(
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'POST',
        '/v1/deliveries',
        body: payload,
      ),
    );
  }

  Future<Map<String, dynamic>> updateDeliveryStatus(
    int id,
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'PUT',
        '/v1/deliveries/$id/status',
        body: payload,
      ),
    );
  }

  Future<Map<String, dynamic>> prepareLabel(
    int id,
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'POST',
        '/v1/deliveries/$id/prepare-label',
        body: payload,
      ),
    );
  }

  Future<dynamic> labelPdf(
    int id,
  ) async {
    return _request(
      'GET',
      '/v1/deliveries/$id/label.pdf',
    );
  }

  Future<Map<String, dynamic>> saveLabelData(
    int id,
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'PUT',
        '/v1/deliveries/$id/label',
        body: payload,
      ),
    );
  }

  // ============================================================
  // SHIPPING
  // ============================================================

  Future<List<dynamic>> shipping({
    String? trackingNumber,
    String? state,
  }) async {
    final params = <String, String>{};

    if (trackingNumber != null &&
        trackingNumber.trim().isNotEmpty) {
      params['tracking_number'] =
          trackingNumber.trim();
    }

    if (state != null &&
        state.trim().isNotEmpty) {
      params['state'] = state.trim();
    }

    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');

    return _list(
      await _request(
        'GET',
        query.isEmpty
            ? '/v1/shipping'
            : '/v1/shipping?$query',
      ),
    );
  }

  Future<List<dynamic>> searchShipping(
    String query,
  ) async {
    return shipping(
      trackingNumber: query,
    );
  }

  Future<Map<String, dynamic>> createShipping(
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'POST',
        '/v1/shipping',
        body: payload,
      ),
    );
  }

  Future<Map<String, dynamic>> updateShipping(
    int id,
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'PUT',
        '/v1/shipping/$id',
        body: payload,
      ),
    );
  }

  // ============================================================
  // COURIER RATES
  // ============================================================

  Future<List<dynamic>> courierRates() async {
    return _list(
      await _request(
        'GET',
        '/v1/courier-rates',
      ),
    );
  }

  Future<Map<String, dynamic>> createCourierRate(
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'POST',
        '/v1/courier-rates',
        body: payload,
      ),
    );
  }

  Future<Map<String, dynamic>> updateCourierRate(
    int id,
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'PUT',
        '/v1/courier-rates/$id',
        body: payload,
      ),
    );
  }

  Future<Map<String, dynamic>> deleteCourierRate(
    int id,
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'DELETE',
        '/v1/courier-rates/$id',
        body: payload,
      ),
    );
  }

  // ============================================================
  // MONTHLY SHIPPING RATES
  // ============================================================

  Future<List<dynamic>> monthlyRates() async {
    return _list(
      await _request(
        'GET',
        '/v1/monthly-rates',
      ),
    );
  }

  Future<Map<String, dynamic>> createMonthlyRate(
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'POST',
        '/v1/monthly-rates',
        body: payload,
      ),
    );
  }

  Future<Map<String, dynamic>> updateMonthlyRate(
    int id,
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'PUT',
        '/v1/monthly-rates/$id',
        body: payload,
      ),
    );
  }

  Future<Map<String, dynamic>> deleteMonthlyRate(
    int id,
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'DELETE',
        '/v1/monthly-rates/$id',
        body: payload,
      ),
    );
  }

  // ============================================================
  // SETTINGS
  // ============================================================

  Future<Map<String, dynamic>> settings() async {
    return _map(
      await _request(
        'GET',
        '/v1/settings',
      ),
    );
  }

  Future<Map<String, dynamic>> updateSettings(
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'PUT',
        '/v1/settings',
        body: payload,
      ),
    );
  }

  // ============================================================
  // USERS
  // ============================================================

  Future<List<dynamic>> users() async {
    return _list(
      await _request(
        'GET',
        '/v1/users',
      ),
    );
  }

  Future<Map<String, dynamic>> createUser(
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'POST',
        '/v1/users',
        body: payload,
      ),
    );
  }

  Future<Map<String, dynamic>> updateUser(
    int id,
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'PUT',
        '/v1/users/$id',
        body: payload,
      ),
    );
  }

  Future<Map<String, dynamic>> deleteUser(
    int id,
    Map<String, dynamic> payload,
  ) async {
    return _map(
      await _request(
        'DELETE',
        '/v1/users/$id',
        body: payload,
      ),
    );
  }

  // ============================================================
  // REPORTS
  // ============================================================

  Future<Map<String, dynamic>> salesReport() async {
    return _map(
      await _request(
        'GET',
        '/v1/reports/sales',
      ),
    );
  }

  Future<List<dynamic>> shippingReport() async {
    return _list(
      await _request(
        'GET',
        '/v1/reports/shipping',
      ),
    );
  }

  Future<List<dynamic>> inventoryReport() async {
    return _list(
      await _request(
        'GET',
        '/v1/reports/inventory',
      ),
    );
  }

  // ============================================================
  // ADMIN / TEST DATA
  // ============================================================

  Future<Map<String, dynamic>> clearTestDataInfo() async {
    return _map(
      await _request(
        'GET',
        '/v1/admin/clear-test-data',
      ),
    );
  }

  Future<Map<String, dynamic>> clearTestData(
    String confirmation,
  ) async {
    return _map(
      await _request(
        'POST',
        '/v1/admin/clear-test-data',
        body: {
          'confirmation': confirmation,
        },
      ),
    );
  }
}
