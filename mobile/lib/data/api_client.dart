import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'API $statusCode: $message';
}

class ApiClient {
  ApiClient({
    http.Client? client,
    FlutterSecureStorage? storage,
  })  : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;

  Future<String?> token() => _storage.read(key: 'api_token');

  Future<void> saveToken(String value) =>
      _storage.write(key: 'api_token', value: value);

  Future<void> clearToken() => _storage.delete(key: 'api_token');

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final token = await this.token();

    final headers = <String, String>{
      'Accept': 'application/json',
    };

    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }

    if (token?.isNotEmpty == true) {
      headers['Authorization'] = 'Bearer $token';
    }

    final base = Uri.parse(AppConfig.apiBaseUrl);

    final uri = base.replace(
      path:
          '${base.path.replaceFirst(RegExp(r'/$'), '')}$path',
      queryParameters: query,
    );

    late http.Response response;

    const timeout = Duration(seconds: 20);

    final encoded = body == null ? null : jsonEncode(body);

    switch (method) {
      case 'GET':
        response = await _client
            .get(uri, headers: headers)
            .timeout(timeout);
        break;

      case 'POST':
        response = await _client
            .post(
              uri,
              headers: headers,
              body: encoded,
            )
            .timeout(timeout);
        break;

      case 'PUT':
        response = await _client
            .put(
              uri,
              headers: headers,
              body: encoded,
            )
            .timeout(timeout);
        break;

      case 'PATCH':
        response = await _client
            .patch(
              uri,
              headers: headers,
              body: encoded,
            )
            .timeout(timeout);
        break;

      case 'DELETE':
        response = await _client
            .delete(
              uri,
              headers: headers,
              body: encoded,
            )
            .timeout(timeout);
        break;

      default:
        throw ArgumentError(
          'Unsupported method: $method',
        );
    }

    dynamic decoded;

    try {
      decoded = response.body.isEmpty
          ? null
          : jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      final message = decoded is Map &&
              decoded['error'] != null
          ? decoded['error'].toString()
          : 'Request failed';

      throw ApiException(
        response.statusCode,
        message,
      );
    }

    return decoded;
  }

  Future<Map<String, dynamic>> _map(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    return Map<String, dynamic>.from(
      await _request(
        method,
        path,
        body: body,
        query: query,
      ) as Map,
    );
  }

  Future<List<dynamic>> _list(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    return List<dynamic>.from(
      await _request(
        method,
        path,
        body: body,
        query: query,
      ) as List,
    );
  }

  // ============================================================
  // AUTH
  // ============================================================

  Future<Map<String, dynamic>> login(
    String username,
    String password,
  ) {
    return _map(
      'POST',
      '/v1/auth/login',
      body: {
        'username': username,
        'password': password,
      },
    );
  }

  Future<Map<String, dynamic>> me() {
    return _map(
      'GET',
      '/v1/auth/me',
    );
  }

  Future<void> logout() async {
    await _request(
      'POST',
      '/v1/auth/logout',
    );
  }

  Future<Map<String, dynamic>> changePassword(
    String current,
    String next,
  ) {
    return _map(
      'POST',
      '/v1/auth/change-password',
      body: {
        'current_password': current,
        'new_password': next,
      },
    );
  }

  // ============================================================
  // SYNC
  // ============================================================

  Future<Map<String, dynamic>> bootstrap() {
    return _map(
      'GET',
      '/v1/bootstrap',
    );
  }

  Future<Map<String, dynamic>> sync(
    int cursor, {
    int limit = 500,
  }) {
    return _map(
      'GET',
      '/v1/sync',
      query: {
        'cursor': '$cursor',
        'limit': '$limit',
      },
    );
  }

  // ============================================================
  // PRODUCTS / STOCK
  // ============================================================

  Future<List<dynamic>> products() {
    return _list(
      'GET',
      '/v1/products',
    );
  }

  Future<Map<String, dynamic>> createProduct(
    Map<String, dynamic> payload,
  ) {
    return _map(
      'POST',
      '/v1/products',
      body: payload,
    );
  }

  Future<Map<String, dynamic>> updateProduct(
    int id,
    Map<String, dynamic> payload,
  ) {
    return _map(
      'PUT',
      '/v1/products/$id',
      body: payload,
    );
  }

  Future<Map<String, dynamic>> deleteProduct(
    int id,
    Map<String, dynamic> payload,
  ) {
    return _map(
      'DELETE',
      '/v1/products/$id',
      body: payload,
    );
  }

  Future<Map<String, dynamic>> stockAdjust(
    Map<String, dynamic> payload,
  ) {
    return _map(
      'POST',
      '/v1/stock/adjust',
      body: payload,
    );
  }

  Future<List<dynamic>> stockLog() {
    return _list(
      'GET',
      '/v1/stock-log',
    );
  }

  // ============================================================
  // SALES
  // ============================================================

  Future<List<dynamic>> sales() {
    return _list(
      'GET',
      '/v1/sales',
      query: {
        'limit': '1000',
      },
    );
  }

  Future<Map<String, dynamic>> createSale(
    Map<String, dynamic> payload,
  ) {
    return _map(
      'POST',
      '/v1/sales',
      body: payload,
    );
  }

  Future<Map<String, dynamic>> saleDetail(
    int id,
  ) {
    return _map(
      'GET',
      '/v1/sales/$id',
    );
  }

  Future<Map<String, dynamic>> updateSaleStatus(
    int id,
    Map<String, dynamic> payload,
  ) {
    return _map(
      'POST',
      '/v1/sales/$id/status',
      body: payload,
    );
  }

  Future<Map<String, dynamic>> settleShipping(
    int id,
    Map<String, dynamic> payload,
  ) {
    return _map(
      'POST',
      '/v1/sales/$id/settle-shipping',
      body: payload,
    );
  }

  // ============================================================
  // SHIPMENT BATCHES
  // ============================================================

  Future<List<dynamic>> batches() {
    return _list(
      'GET',
      '/v1/batches',
    );
  }

  Future<Map<String, dynamic>> createBatch(
    Map<String, dynamic> payload,
  ) {
    return _map(
      'POST',
      '/v1/batches',
      body: payload,
    );
  }

  Future<Map<String, dynamic>> addSaleToBatch(
    int batchId,
    int saleId,
    Map<String, dynamic> payload,
  ) {
    return _map(
      'POST',
      '/v1/batches/$batchId/sales/$saleId',
      body: {
        ...payload,
        'action': 'add',
      },
    );
  }

  Future<Map<String, dynamic>> removeSaleFromBatch(
    int batchId,
    int saleId,
    Map<String, dynamic> payload,
  ) {
    return _map(
      'POST',
      '/v1/batches/$batchId/sales/$saleId',
      body: {
        ...payload,
        'action': 'remove',
      },
    );
  }

  Future<Map<String, dynamic>> arriveBatch(
    int id,
    Map<String, dynamic> payload,
  ) {
    return _map(
      'POST',
      '/v1/batches/$id/arrive',
      body: payload,
    );
  }

  // ============================================================
  // DELIVERIES
  // ============================================================

  Future<List<dynamic>> deliveries() {
    return _list(
      'GET',
      '/v1/deliveries',
    );
  }

  Future<List<dynamic>> readyDeliveries() {
    return _list(
      'GET',
      '/v1/deliveries/ready',
    );
  }

  Future<Map<String, dynamic>> createDelivery(
    Map<String, dynamic> payload,
  ) {
    return _map(
      'POST',
      '/v1/deliveries',
      body: payload,
    );
  }

  Future<Map<String, dynamic>> updateDeliveryStatus(
    int id,
    Map<String, dynamic> payload,
  ) {
    return _map(
      'POST',
      '/v1/deliveries/$id/status',
      body: payload,
    );
  }

  Future<Map<String, dynamic>> prepareLabel(
    int id,
    Map<String, dynamic> payload,
  ) {
    return _map(
      'POST',
      '/v1/deliveries/$id/label',
      body: payload,
    );
  }

  Future<Uint8List> labelPdf(int id) async {
    final token = await this.token();

    final base = Uri.parse(
      AppConfig.apiBaseUrl,
    );

    final uri = base.replace(
      path:
          '${base.path.replaceFirst(RegExp(r'/$'), '')}'
          '/v1/deliveries/$id/label.pdf',
    );

    final response = await _client
        .get(
          uri,
          headers: {
            'Accept': 'application/pdf',
            'Authorization':
                'Bearer ${token ?? ''}',
          },
        )
        .timeout(
          const Duration(seconds: 30),
        );

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        'Could not generate label.',
      );
    }

    return response.bodyBytes;
  }

  // ============================================================
  // SHIPPING
  // ============================================================

  Future<List<dynamic>> shipping({
    String? trackingNumber,
    String? state,
  }) {
    return _list(
      'GET',
      '/v1/shipping',
      query: {
        if (trackingNumber?.isNotEmpty == true)
          'tracking_number': trackingNumber!,
        if (state?.isNotEmpty == true)
          'state': state!,
      },
    );
  }

  Future<Map<String, dynamic>> createShipping(
    Map<String, dynamic> payload,
  ) {
    return _map(
      'POST',
      '/v1/shipping',
      body: payload,
    );
  }

  Future<Map<String, dynamic>> updateShipping(
    int id,
    Map<String, dynamic> payload,
  ) {
    return _map(
      'POST',
      '/v1/shipping/$id',
      body: payload,
    );
  }

  // ============================================================
  // COURIER RATES
  // ============================================================

  Future<List<dynamic>> courierRates() {
    return _list(
      'GET',
      '/v1/courier-rates',
    );
  }

  Future<Map<String, dynamic>> createCourierRate(
    Map<String, dynamic> payload,
  ) {
    return _map(
      'POST',
      '/v1/courier-rates',
      body: payload,
    );
  }

  Future<Map<String, dynamic>> updateCourierRate(
    int id,
    Map<String, dynamic> payload,
  ) {
    return _map(
      'PUT',
      '/v1/courier-rates/$id',
      body: payload,
    );
  }

  Future<Map<String, dynamic>> deleteCourierRate(
    int id,
    Map<String, dynamic> payload,
  ) {
    return _map(
      'DELETE',
      '/v1/courier-rates/$id',
      body: payload,
    );
  }

  // ============================================================
  // MONTHLY SHIPPING RATES
  // ============================================================

  Future<List<dynamic>> monthlyRates() {
    return _list(
      'GET',
      '/v1/monthly-shipping-rates',
    );
  }

  Future<Map<String, dynamic>> createMonthlyRate(
    Map<String, dynamic> payload,
  ) {
    return _map(
      'POST',
      '/v1/monthly-shipping-rates',
      body: payload,
    );
  }

  Future<Map<String, dynamic>> updateMonthlyRate(
    int id,
    Map<String, dynamic> payload,
  ) {
    return _map(
      'PUT',
      '/v1/monthly-shipping-rates/$id',
      body: payload,
    );
  }

  Future<Map<String, dynamic>> deleteMonthlyRate(
    int id,
    Map<String, dynamic> payload,
  ) {
    return _map(
      'DELETE',
      '/v1/monthly-shipping-rates/$id',
      body: payload,
    );
  }

  // ============================================================
  // SETTINGS / USERS
  // ============================================================

  Future<Map<String, dynamic>> settings() {
    return _map(
      'GET',
      '/v1/settings',
    );
  }

  Future<Map<String, dynamic>> updateSettings(
    Map<String, dynamic> payload,
  ) {
    return _map(
      'POST',
      '/v1/settings',
      body: payload,
    );
  }

  Future<List<dynamic>> users() {
    return _list(
      'GET',
      '/v1/users',
    );
  }

  Future<Map<String, dynamic>> createUser(
    Map<String, dynamic> payload,
  ) {
    return _map(
      'POST',
      '/v1/users',
      body: payload,
    );
  }

  Future<Map<String, dynamic>> updateUser(
    int id,
    Map<String, dynamic> payload,
  ) {
    return _map(
      'PUT',
      '/v1/users/$id',
      body: payload,
    );
  }

  // ============================================================
  // REPORTS
  // ============================================================

  Future<Map<String, dynamic>> salesReport({
    String? startDate,
    String? endDate,
  }) {
    return _map(
      'GET',
      '/v1/reports/sales',
      query: {
        if (startDate != null)
          'start_date': startDate,
        if (endDate != null)
          'end_date': endDate,
      },
    );
  }

  Future<List<dynamic>> shippingReport() {
    return _list(
      'GET',
      '/v1/reports/shipping',
    );
  }

  Future<List<dynamic>> inventoryReport() {
    return _list(
      'GET',
      '/v1/reports/inventory',
    );
  }

  // ============================================================
  // ADMIN
  // ============================================================

  Future<Map<String, dynamic>> clearTestData(
    String confirmation,
  ) {
    return _map(
      'POST',
      '/v1/admin/clear-test-data',
      body: {
        'confirmation': confirmation,
      },
    );
  }
}
