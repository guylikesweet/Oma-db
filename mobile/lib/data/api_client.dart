import 'dart:convert';
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
  ApiClient({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;

  Future<String?> token() => _storage.read(key: 'api_token');
  Future<void> saveToken(String value) => _storage.write(key: 'api_token', value: value);
  Future<void> clearToken() => _storage.delete(key: 'api_token');

  Future<dynamic> _request(String method, String path, {Map<String, dynamic>? body, Map<String, String>? query}) async {
    final token = await this.token();
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

    final base = Uri.parse(AppConfig.apiBaseUrl);
    final uri = base.replace(path: '${base.path.replaceFirst(RegExp(r'/$'), '')}$path', queryParameters: query);
    late http.Response response;
    switch (method) {
      case 'GET':
        response = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 15));
        break;
      case 'POST':
        response = await _client.post(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 15));
        break;
      default:
        throw ArgumentError('Unsupported method: $method');
    }

    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map && decoded['error'] != null ? decoded['error'].toString() : 'Request failed';
      throw ApiException(response.statusCode, message);
    }
    return decoded;
  }

  Future<Map<String, dynamic>> login(String username, String password) async =>
      Map<String, dynamic>.from(await _request('POST', '/v1/auth/login', body: {'username': username, 'password': password}) as Map);

  Future<Map<String, dynamic>> me() async => Map<String, dynamic>.from(await _request('GET', '/v1/auth/me') as Map);
  Future<void> logout() async { await _request('POST', '/v1/auth/logout'); }

  Future<Map<String, dynamic>> bootstrap() async => Map<String, dynamic>.from(await _request('GET', '/v1/bootstrap') as Map);

  Future<Map<String, dynamic>> sync(int cursor, {int limit = 250}) async =>
      Map<String, dynamic>.from(await _request('GET', '/v1/sync', query: {'cursor': '$cursor', 'limit': '$limit'}) as Map);

  Future<List<dynamic>> products() async => List<dynamic>.from(await _request('GET', '/v1/products') as List);
  Future<List<dynamic>> sales() async => List<dynamic>.from(await _request('GET', '/v1/sales') as List);

  Future<Map<String, dynamic>> createSale(Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _request('POST', '/v1/sales', body: payload) as Map);

  Future<Map<String, dynamic>> stockAdjust(Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _request('POST', '/v1/stock/adjust', body: payload) as Map);
  Future<List<dynamic>> batches() async => List<dynamic>.from(await _request('GET', '/v1/batches') as List);
  Future<List<dynamic>> deliveries() async => List<dynamic>.from(await _request('GET', '/v1/deliveries') as List);
  Future<List<dynamic>> shipping() async => List<dynamic>.from(await _request('GET', '/v1/shipping') as List);
  Future<Map<String, dynamic>> createBatch(Map<String, dynamic> payload) async => Map<String, dynamic>.from(await _request('POST', '/v1/batches', body: payload) as Map);
  Future<Map<String, dynamic>> addSaleToBatch(int batchId, int saleId, Map<String, dynamic> payload) async => Map<String, dynamic>.from(await _request('POST', '/v1/batches/$batchId/sales/$saleId', body: payload) as Map);
  Future<Map<String, dynamic>> removeSaleFromBatch(int batchId, int saleId, Map<String, dynamic> payload) async => Map<String, dynamic>.from(await _request('POST', '/v1/batches/$batchId/sales/$saleId', body: payload) as Map);
  Future<Map<String, dynamic>> arriveBatch(int batchId, Map<String, dynamic> payload) async => Map<String, dynamic>.from(await _request('POST', '/v1/batches/$batchId/arrive', body: payload) as Map);
  Future<Map<String, dynamic>> settleShipping(int saleId, Map<String, dynamic> payload) async => Map<String, dynamic>.from(await _request('POST', '/v1/sales/$saleId/settle-shipping', body: payload) as Map);
  Future<Map<String, dynamic>> updateSaleStatus(int id, Map<String, dynamic> payload) async => Map<String, dynamic>.from(await _request('POST', '/v1/sales/$id/status', body: payload) as Map);
  Future<Map<String, dynamic>> updateDeliveryStatus(int id, Map<String, dynamic> payload) async => Map<String, dynamic>.from(await _request('POST', '/v1/deliveries/$id/status', body: payload) as Map);
  Future<Map<String, dynamic>> createDelivery(Map<String, dynamic> payload) async => Map<String, dynamic>.from(await _request('POST', '/v1/deliveries', body: payload) as Map);
  Future<Map<String, dynamic>> createShipping(Map<String, dynamic> payload) async => Map<String, dynamic>.from(await _request('POST', '/v1/shipping', body: payload) as Map);
  Future<Map<String, dynamic>> updateShipping(int id, Map<String, dynamic> payload) async => Map<String, dynamic>.from(await _request('POST', '/v1/shipping/$id', body: payload) as Map);
}
