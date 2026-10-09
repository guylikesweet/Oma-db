import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/network_errors.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.cause});

  final int statusCode;
  final String message;
  final Object? cause;

  @override
  String toString() {
    final network = cause == null ? null : classifyNetworkError(cause!);
    if (network != null) return network.message;
    return 'API $statusCode: $message';
  }
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

  Future<String?> biometricCredential() {
    return _storage.read(key: 'biometric_credential');
  }

  Future<String?> biometricUsername() {
    return _storage.read(key: 'biometric_username');
  }

  Future<void> saveBiometricCredential(String username, String credential) async {
    await _storage.write(key: 'biometric_username', value: username);
    await _storage.write(key: 'biometric_credential', value: credential);
  }

  Future<void> clearBiometricCredential() async {
    await _storage.delete(key: 'biometric_username');
    await _storage.delete(key: 'biometric_credential');
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

    try {
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
    } on TimeoutException catch (e) {
      throw ApiException(0, 'Network request timed out.', cause: e);
    } on SocketException catch (e) {
      throw ApiException(0, 'Network connection failed.', cause: e);
    } on http.ClientException catch (e) {
      throw ApiException(0, 'Network connection failed.', cause: e);
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

  Future<Map<String, dynamic>> biometricLogin(
    String username,
    String credential,
  ) {
    return _map(
      'POST',
      '/v1/auth/biometric-login',
      body: {
        'username': username,
        'credential': credential,
      },
    );
  }

  Future<void> logout() async {
    await _request(
      'POST',
      '/v1/auth/logout',
    );
  }

  Future<Map<String, dynamic>> registerPushDevice(
    String token,
    String platform, {
    String? notificationChannelVersion,
  }) {
    return _map(
      'POST',
      '/v1/notifications/register-device',
      body: {
        'token': token,
        'platform': platform,
        if (notificationChannelVersion != null &&
            notificationChannelVersion.isNotEmpty)
          'notification_channel_version': notificationChannelVersion,
      },
    );
  }

  Future<Map<String, dynamic>> testPushNotification() {
    return _map(
      'POST',
      '/v1/notifications/test',
    );
  }

  Future<Map<String, dynamic>> unregisterPushDevice(String token) {
    return _map(
      'POST',
      '/v1/notifications/unregister-device',
      body: {'token': token},
    );
  }

  Future<Map<String, dynamic>> verifyPassword(String password) {
    return _map(
      'POST',
      '/v1/auth/verify-password',
      body: {'password': password},
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

  Future<Map<String, dynamic>> changeUsername(
    String newUsername,
  ) {
    return _map(
      'POST',
      '/v1/auth/change-username',
      body: {
        'new_username': newUsername,
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

  Future<List<dynamic>> auditLog({int limit = 200}) {
    return _list(
      'GET',
      '/v1/audit',
      query: {'limit': '$limit'},
    );
  }

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

  Future<Map<String, dynamic>> saleJourney(
    int id,
  ) {
    return _map(
      'GET',
      '/v1/sales/$id/journey',
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

  /// Downloads a PDF invoice/receipt for one sale — same
  /// authenticated-binary-fetch pattern as [labelPdf] below.
  Future<Uint8List> invoicePdf(
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
      path: '$basePath/v1/sales/$id/invoice.pdf',
    );

    final headers = <String, String>{
      'Accept': 'application/pdf',
    };

    if (savedToken != null &&
        savedToken.isNotEmpty) {
      headers['Authorization'] =
          'Bearer $savedToken';
    }

    late http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: headers,
          )
          .timeout(
            const Duration(seconds: 90),
          );
    } on TimeoutException catch (e) {
      throw ApiException(0, 'Network request timed out.', cause: e);
    } on SocketException catch (e) {
      throw ApiException(0, 'Network connection failed.', cause: e);
    } on http.ClientException catch (e) {
      throw ApiException(0, 'Network connection failed.', cause: e);
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      String message =
          'Could not generate invoice.';

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

  Future<Map<String, dynamic>> updateBatchSalesBulk(
    int batchId, {
    List<int> addSaleIds = const [],
    List<int> removeSaleIds = const [],
  }) {
    return _map(
      'POST',
      '/v1/batches/$batchId/sales/bulk',
      body: {
        'add_sale_ids': addSaleIds,
        'remove_sale_ids': removeSaleIds,
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

  Future<Map<String, dynamic>> undoBatchArrival(int id) {
    return _map(
      'POST',
      '/v1/batches/$id/undo-arrival',
      body: <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> deleteSale(int id) {
    return _map(
      'DELETE',
      '/v1/admin/sales/$id',
      body: <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> deleteBatch(int id) {
    return _map(
      'DELETE',
      '/v1/admin/batches/$id',
      body: <String, dynamic>{},
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

  /// Groups of ready sales that could share one courier bag (same phone,
  /// name, city or state). Suggestions only — consolidating is optional.
  Future<List<dynamic>> deliverySuggestions() {
    return _list(
      'GET',
      '/v1/deliveries/suggestions',
    );
  }

  /// The "goods have arrived" WhatsApp message for one sale, already filled
  /// in from the sale and Settings: {phone, message, whatsapp_url}.
  Future<Map<String, dynamic>> arrivalNotice(int saleId) {
    return _map(
      'GET',
      '/v1/sales/$saleId/arrival-notice',
    );
  }

  Future<List<dynamic>> batchArrivalNotices(int batchId) {
    return _list(
      'GET',
      '/v1/batches/$batchId/arrival-notices',
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

    late http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: headers,
          )
          .timeout(
            const Duration(seconds: 30),
          );
    } on TimeoutException catch (e) {
      throw ApiException(0, 'Network request timed out.', cause: e);
    } on SocketException catch (e) {
      throw ApiException(0, 'Network connection failed.', cause: e);
    } on http.ClientException catch (e) {
      throw ApiException(0, 'Network connection failed.', cause: e);
    }

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
  // MONTHLY AIR RATES (NGN per volumetric kg) — the Sea rate is the
  // monthly shipping rate above (NGN per CBM)
  // ============================================================

  Future<List<dynamic>> airRates() {
    return _list(
      'GET',
      '/v1/monthly-air-rates',
    );
  }

  Future<Map<String, dynamic>> createAirRate(
    Map<String, dynamic> payload,
  ) {
    return _map(
      'POST',
      '/v1/monthly-air-rates',
      body: payload,
    );
  }

  Future<Map<String, dynamic>> updateAirRate(
    int id,
    Map<String, dynamic> payload,
  ) {
    return _map(
      'PUT',
      '/v1/monthly-air-rates/$id',
      body: payload,
    );
  }

  Future<Map<String, dynamic>> deleteAirRate(
    int id, [
    Map<String, dynamic>? payload,
  ]) {
    return _map(
      'DELETE',
      '/v1/monthly-air-rates/$id',
      body: payload ?? <String, dynamic>{},
    );
  }

  // ============================================================
  // ORDER JOURNEY
  // ============================================================

  /// Moves several orders to a stage that is set by hand (fulfilled,
  /// CN domestic transit, consolidation; packing for stocked goods).
  /// Returns {updated, unchanged, skipped: [reasons]}.
  Future<Map<String, dynamic>> setJourneyStage(
    List<int> saleIds,
    String stage,
  ) {
    return _map(
      'POST',
      '/v1/sales/journey',
      body: {
        'sale_ids': saleIds,
        'stage': stage,
      },
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

  Future<Map<String, dynamic>> calculateProductCost({
    required String cost,
    required String lengthCm,
    required String widthCm,
    required String heightCm,
    required String actualWeightKg,
    required String markupPercent,
    String mode = 'sea',
  }) {
    return _map(
      'POST',
      '/v1/products/cost-calculator',
      body: {
        'cost': cost,
        'length_cm': lengthCm,
        'width_cm': widthCm,
        'height_cm': heightCm,
        'actual_weight_kg': actualWeightKg,
        'markup_percent': markupPercent,
        'mode': mode,
      },
    );
  }

  Future<Map<String, dynamic>> getProfile() {
    return _map('GET', '/v1/profile');
  }

  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> payload,
  ) {
    return _map('PUT', '/v1/profile', body: payload);
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
  // TEAM CHAT
  // ============================================================

  Future<Map<String, dynamic>> chatDiagnostic() {
    return _map('GET', '/v1/chat/diagnostic');
  }

  Future<List<dynamic>> chatMessages({int limit = 100, int? beforeId}) {
    final query = <String, String>{
      'limit': '$limit',
      if (beforeId != null) 'before_id': '$beforeId',
    };
    return _list(
      'GET',
      '/v1/chat/messages',
      query: query,
    );
  }

  Future<Map<String, dynamic>> chatMessage(int id) {
    return _map('GET', '/v1/chat/messages/$id');
  }

  Future<Map<String, dynamic>> sendChatMessage(
    String content, {
    int? replyToId,
    String? attachmentBase64,
    String? attachmentFilename,
    String? audioBase64,
    String? audioFilename,
    String? audioMimetype,
    String? clientOperationId,
  }) {
    return _map(
      'POST',
      '/v1/chat/messages',
      body: {
        'content': content,
        if (replyToId != null) 'reply_to_id': replyToId,
        if (attachmentBase64 != null) 'attachment_base64': attachmentBase64,
        if (attachmentFilename != null) 'attachment_filename': attachmentFilename,
        if (audioBase64 != null) 'audio_base64': audioBase64,
        if (audioFilename != null) 'audio_filename': audioFilename,
        if (audioMimetype != null) 'audio_mimetype': audioMimetype,
        if (clientOperationId != null) 'client_operation_id': clientOperationId,
      },
    );
  }

  Future<Map<String, dynamic>> updateChatMessage(int id, String content) {
    return _map(
      'PATCH',
      '/v1/chat/messages/$id',
      body: {'content': content},
    );
  }

  Future<Map<String, dynamic>> deleteChatMessage(int id) {
    return _map(
      'DELETE',
      '/v1/chat/messages/$id',
      body: const <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> reactToChatMessage(int id, String emoji) {
    return _map(
      'POST',
      '/v1/chat/messages/$id/react',
      body: {'emoji': emoji},
    );
  }

  Future<String> chatAudioPlaybackUrl(int messageId) async {
    final response = await _map(
      'GET',
      '/v1/chat/messages/$messageId/audio-token',
    );
    return Uri.parse(AppConfig.apiBaseUrl).resolve(
      response['url']?.toString() ?? '',
    ).toString();
  }

  Future<Uint8List> downloadChatAudio(String url) async {
    final tokenValue = await token();
    final response = await _client.get(
      Uri.parse(AppConfig.apiBaseUrl).resolve(url),
      headers: {
        if (tokenValue != null && tokenValue.isNotEmpty)
          'Authorization': 'Bearer $tokenValue',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Unable to download the voice recording.');
    }
    return response.bodyBytes;
  }

  Future<Uint8List> downloadChatAttachment(String url) async {
    final tokenValue = await token();
    final response = await _client.get(
      Uri.parse(AppConfig.apiBaseUrl).resolve(url),
      headers: {
        if (tokenValue != null && tokenValue.isNotEmpty)
          'Authorization': 'Bearer $tokenValue',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Unable to download the photo.');
    }
    return response.bodyBytes;
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
  Future<Uint8List> productImage(int id) async {
    final savedToken = await token();
    final base = Uri.parse(AppConfig.apiBaseUrl);
    final basePath = base.path.replaceFirst(RegExp(r'/$'), '');
    final uri = base.replace(path: '$basePath/v1/products/$id/image');
    final headers = <String, String>{'Accept': 'image/*', 'Cache-Control': 'no-cache', 'Pragma': 'no-cache'};
    if (savedToken != null && savedToken.isNotEmpty) headers['Authorization'] = 'Bearer $savedToken';
    final response = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) throw ApiException(response.statusCode, 'Could not load product photo.');
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> uploadProductImage(int id, Uint8List bytes, {required String mimetype, String? filename}) {
    return _map('POST', '/v1/products/$id/image', body: {
      'image_base64': base64Encode(bytes), 'mimetype': mimetype,
      if (filename != null && filename.isNotEmpty) 'filename': filename,
    });
  }

  Future<Map<String, dynamic>> deleteProductImage(int id) => _map('DELETE', '/v1/products/$id/image');

}
