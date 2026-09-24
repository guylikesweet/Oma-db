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

  Future<String?> token() {
    return _storage.read(key: 'api_token');
  }

  Future<void> saveToken(String value) {
    return _storage.write(
      key: 'api_token',
      value: value,
    );
  }

  Future<void> clearToken() {
    return _storage.delete(key: 'api_token');
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final savedToken = await token();

    final headers = <String, String>{
      'Accept': 'application/json',
    };

    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }

    if (savedToken != null && savedToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $savedToken';
    }

    final base = Uri.parse(AppConfig.apiBaseUrl);

    final basePath = base.path.replaceFirst(
      RegExp(r'/$'),
      '',
    );

    final uri = base.replace(
      path: '$basePath$path',
      queryParameters: query,
    );

    late http.Response response;

    final timeout = const Duration(seconds: 20);

    final encodedBody = body == null ? null : jsonEncode(body);

    switch (method.toUpperCase()) {
      case 'GET':
        response = await _client
            .get(
              uri,
              headers: headers,
            )
            .timeout(timeout);
        break;

      case 'POST':
        response = await _client
            .post(
              uri,
              headers: headers,
              body: encodedBody,
            )
            .timeout(timeout);
        break;

      case 'PUT':
        response = await _client
            .put(
              uri,
              headers: headers,
              body: encodedBody,
            )
            .timeout(timeout);
        break;

      case 'PATCH':
        response = await _client
            .patch(
              uri,
              headers: headers,
              body: encodedBody,
            )
            .timeout(timeout);
        break;

      case 'DELETE':
        response = await _client
            .delete(
              uri,
              headers: headers,
              body: encodedBody,
            )
            .timeout(timeout);
        break;

      default:
        throw ArgumentError(
          'Unsupported HTTP method: $method',
        );
    }

    dynamic decoded;

    if (response.body.isEmpty) {
      decoded = null;
    } else {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = null;
      }
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      String message = 'Request failed';

      if (decoded is Map &&
          decoded['error'] != null) {
        message = decoded['error'].toString();
      } else if (decoded is Map &&
          decoded['message'] != null) {
        message = decoded['message'].toString();
      } else if (response.body.trim().isNotEmpty) {
        message = response.body.trim();
      }

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
    final result = await _request(
      method,
      path,
      body: body,
      query: query,
    );

    if (result is! Map) {
      throw ApiException(
        500,
        'Server returned an unexpected response.',
      );
    }

    return Map<String, dynamic>.from(result);
  }

  Future<List<dynamic>> _list(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final result = await _request(
      method,
      path,
      body: body,
      query: query,
    );

    if (result is! List) {
      throw ApiException(
        500,
        'Server returned an unexpected list response.',
      );
    }

    return List<dynamic>.from(result);
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
    String currentPassword,
    String newPassword,
  ) {
    return _map(
      'POST',
      '/v1/auth/change-password',
      body: {
        'current_password': currentPassword,
        'new_password': newPassword,
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
  // DASHBOARD
  // ============================================================

  Future<Map<String, dynamic>> dashboard() {
    return _map(
      'GET',
      '/v1/dashboard',
    );
  }

  // ============================================================
  // PRODUCTS
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
    int id, [
    Map<String, dynamic>? payload,
  ]) {
    return _map(
      'DELETE',
      '/v1/products/$id',
      body: payload ?? <String, dynamic>{},
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
    int id, [
    Map<String, dynamic>? payload,
  ]) {
    return _map(
      'POST',
      '/v1/sales/$id/settle-shipping',
      body: payload ?? <String, dynamic>{},
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

  Future<Map<String, dynamic>> batch(
    int id,
  ) {
    return _map(
      'GET',
      '/v1/batches/$id',
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
    int saleId, [
    Map<String, dynamic>? payload,
  ]) {
    return _map(
      'POST',
      '/v1/batches/$batchId/sales/$saleId',
      body: {
        ...(payload ?? <String, dynamic>{}),
        'action': 'add',
      },
    );
  }

  Future<Map<String, dynamic>> removeSaleFromBatch(
    int batchId,
    int saleId, [
    Map<String, dynamic>? payload,
  ]) {
    return _map(
      'POST',
      '/v1/batches/$batchId/sales/$saleId',
      body: {
        ...(payload ?? <String, dynamic>{}),
        'action': 'remove',
      },
    );
  }

  Future<Map<String, dynamic>> arriveBatch(
    int id, [
    Map<String, dynamic>? payload,
  ]) {
    return _map(
      'POST',
      '/v1/batches/$id/arrive',
      body: payload ?? <String, dynamic>{},
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

  Future<Map<String, dynamic>> readyDeliveries() {
    return _map(
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

  Future<Map<String, dynamic>> saveLabelData(
    int id,
    Map<String, dynamic> payload,
  ) {
    return prepareLabel(
      id,
      payload,
    );
  }

  Future<Uint8List> labelPdf(
    int id,
  ) async {
    final savedToken = await token();

    final base = Uri.parse(
      AppConfig.apiBaseUrl,
    );

    final basePath = base.path.replaceFirst(
      RegExp(r'/$'),
      '',
    );

    final uri = base.replace(
      path: '$basePath/v1/deliveries/$id/label.pdf',
    );

    final headers = <String, String>{
      'Accept': 'application/pdf',
    };

    if (savedToken != null &&
        savedToken.isNotEmpty) {
      headers['Authorization'] =
          'Bearer $savedToken';
    }

    final response = await _client
        .get(
          uri,
          headers: headers,
        )
        .timeout(
          const Duration(seconds: 30),
        );

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      String message =
          'Could not generate label.';

      try {
        final decoded =
            jsonDecode(response.body);

        if (decoded is Map &&
            decoded['error'] != null) {
          message =
              decoded['error'].toString();
        }
      } catch (_) {}

      throw ApiException(
        response.statusCode,
        message,
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
    final query = <String, String>{};

    if (trackingNumber != null &&
        trackingNumber.trim().isNotEmpty) {
      query['tracking_number'] =
          trackingNumber.trim();
    }

    if (state != null &&
        state.trim().isNotEmpty) {
      query['state'] = state.trim();
    }

    return _list(
      'GET',
      '/v1/shipping',
      query: query.isEmpty ? null : query,
    );
  }

  Future<List<dynamic>> searchShipping({
    String? trackingNumber,
    String? state,
  }) {
    return shipping(
      trackingNumber: trackingNumber,
      state: state,
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
    int id, [
    Map<String, dynamic>? payload,
  ]) {
    return _map(
      'DELETE',
      '/v1/courier-rates/$id',
      body: payload ?? <String, dynamic>{},
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
    int id, [
    Map<String, dynamic>? payload,
  ]) {
    return _map(
      'DELETE',
      '/v1/monthly-shipping-rates/$id',
      body: payload ?? <String, dynamic>{},
    );
  }

  // ============================================================
  // SETTINGS
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

  // ============================================================
  // USERS
  // ============================================================

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

  Future<Map<String, dynamic>> deleteUser(
    int id, [
    Map<String, dynamic>? payload,
  ]) {
    return _map(
      'DELETE',
      '/v1/users/$id',
      body: payload ?? <String, dynamic>{},
    );
  }

  // ============================================================
  // REPORTS
  // ============================================================

  Future<Map<String, dynamic>> salesReport({
    String? startDate,
    String? endDate,
  }) {
    final query = <String, String>{};

    if (startDate != null &&
        startDate.isNotEmpty) {
      query['start_date'] = startDate;
    }

    if (endDate != null &&
        endDate.isNotEmpty) {
      query['end_date'] = endDate;
    }

    return _map(
      'GET',
      '/v1/reports/sales',
      query: query.isEmpty ? null : query,
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
  // ADMIN / TEST DATA
  // ============================================================

  Future<Map<String, dynamic>> clearTestDataInfo() {
    return _map(
      'GET',
      '/v1/admin/clear-test-data',
    );
  }

  Future<Map<String, dynamic>> clearTestData({
    String confirmation = '',
  }) {
    return _map(
      'POST',
      '/v1/admin/clear-test-data',
      body: {
        'confirmation': confirmation,
      },
    );
  }
}
