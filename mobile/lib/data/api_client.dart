import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../core/config.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override String toString() => 'API $statusCode: $message';
}

class ApiClient {
  ApiClient({http.Client? client, FlutterSecureStorage? storage}) : _client=client??http.Client(), _storage=storage??const FlutterSecureStorage();
  final http.Client _client; final FlutterSecureStorage _storage;
  Future<String?> token()=>_storage.read(key:'api_token');
  Future<void> saveToken(String value)=>_storage.write(key:'api_token',value:value);
  Future<void> clearToken()=>_storage.delete(key:'api_token');

  Future<dynamic> _request(String method,String path,{Map<String,dynamic>? body,Map<String,String>? query}) async {
    final token=await this.token(); final headers=<String,String>{'Accept':'application/json'};
    if(body!=null)headers['Content-Type']='application/json'; if(token?.isNotEmpty==true)headers['Authorization']='Bearer $token';
    final base=Uri.parse(AppConfig.apiBaseUrl); final uri=base.replace(path:'${base.path.replaceFirst(RegExp(r'/$'), '')}$path',queryParameters:query);
    late http.Response response; final timeout=const Duration(seconds:20); final encoded=body==null?null:jsonEncode(body);
    switch(method){case 'GET':response=await _client.get(uri,headers:headers).timeout(timeout);break;case 'POST':response=await _client.post(uri,headers:headers,body:encoded).timeout(timeout);break;case 'PUT':response=await _client.put(uri,headers:headers,body:encoded).timeout(timeout);break;case 'PATCH':response=await _client.patch(uri,headers:headers,body:encoded).timeout(timeout);break;case 'DELETE':response=await _client.delete(uri,headers:headers,body:encoded).timeout(timeout);break;default:throw ArgumentError('Unsupported method: $method');}
    dynamic decoded;try{decoded=response.body.isEmpty?null:jsonDecode(response.body);}catch(_){decoded=null;}
    if(response.statusCode<200||response.statusCode>=300){final msg=decoded is Map&&decoded['error']!=null?decoded['error'].toString():'Request failed';throw ApiException(response.statusCode,msg);}return decoded;
  }
  Future<Map<String,dynamic>> _map(String m,String p,{Map<String,dynamic>? b,Map<String,String>? q})async=>Map<String,dynamic>.from(await _request(m,p,body:b,query:q) as Map);
  Future<List<dynamic>> _list(String m,String p,{Map<String,dynamic>? b,Map<String,String>? q})async=>List<dynamic>.from(await _request(m,p,body:b,query:q) as List);

  Future<Map<String,dynamic>> login(String u,String p)=>_map('POST','/v1/auth/login',b:{'username':u,'password':p});
  Future<Map<String,dynamic>> me()=>_map('GET','/v1/auth/me');
  Future<void> logout()async{await _request('POST','/v1/auth/logout');}
  Future<Map<String,dynamic>> changePassword(String current,String next)=>_map('POST','/v1/auth/change-password',b:{'current_password':current,'new_password':next});
  Future<Map<String,dynamic>> bootstrap()=>_map('GET','/v1/bootstrap');
  Future<Map<String,dynamic>> sync(int cursor,{int limit=500})=>_map('GET','/v1/sync',q:{'cursor':'$cursor','limit':'$limit'});

  Future<List<dynamic>> products()=>_list('GET','/v1/products');
  Future<Map<String,dynamic>> createProduct(Map<String,dynamic> p)=>_map('POST','/v1/products',b:p);
  Future<Map<String,dynamic>> updateProduct(int id,Map<String,dynamic> p)=>_map('PUT','/v1/products/$id',b:p);
  Future<Map<String,dynamic>> deleteProduct(int id,Map<String,dynamic> p)=>_map('DELETE','/v1/products/$id',b:p);
  Future<Map<String,dynamic>> stockAdjust(Map<String,dynamic> p)=>_map('POST','/v1/stock/adjust',b:p);
  Future<List<dynamic>> stockLog()=>_list('GET','/v1/stock-log');

  Future<List<dynamic>> sales()=>_list('GET','/v1/sales',q:{'limit':'1000'});
  Future<Map<String,dynamic>> createSale(Map<String,dynamic> p)=>_map('POST','/v1/sales',b:p);
  Future<Map<String,dynamic>> saleDetail(int id)=>_map('GET','/v1/sales/$id');
  Future<Map<String,dynamic>> updateSaleStatus(int id,Map<String,dynamic> p)=>_map('POST','/v1/sales/$id/status',b:p);
  Future<Map<String,dynamic>> settleShipping(int id,Map<String,dynamic> p)=>_map('POST','/v1/sales/$id/settle-shipping',b:p);

  Future<List<dynamic>> batches()=>_list('GET','/v1/batches');
  Future<Map<String,dynamic>> createBatch(Map<String,dynamic> p)=>_map('POST','/v1/batches',b:p);
  Future<Map<String,dynamic>> addSaleToBatch(int b,int s,Map<String,dynamic> p)=>_map('POST','/v1/batches/$b/sales/$s',b:{...p,'action':'add'});
  Future<Map<String,dynamic>> removeSaleFromBatch(int b,int s,Map<String,dynamic> p)=>_map('POST','/v1/batches/$b/sales/$s',b:{...p,'action':'remove'});
  Future<Map<String,dynamic>> arriveBatch(int id,Map<String,dynamic> p)=>_map('POST','/v1/batches/$id/arrive',b:p);

  Future<List<dynamic>> deliveries()=>_list('GET','/v1/deliveries');
  Future<List<dynamic>> readyDeliveries()=>_list('GET','/v1/deliveries/ready');
  Future<Map<String,dynamic>> createDelivery(Map<String,dynamic> p)=>_map('POST','/v1/deliveries',b:p);
  Future<Map<String,dynamic>> updateDeliveryStatus(int id,Map<String,dynamic> p)=>_map('POST','/v1/deliveries/$id/status',b:p);
  Future<Map<String,dynamic>> prepareLabel(int id,Map<String,dynamic> p)=>_map('POST','/v1/deliveries/$id/label',b:p);
  Future<Uint8List> labelPdf(int id) async { final token=await this.token(); final base=Uri.parse(AppConfig.apiBaseUrl); final uri=base.replace(path:'${base.path.replaceFirst(RegExp(r'/$'), '')}/v1/deliveries/$id/label.pdf'); final r=await _client.get(uri,headers:{'Accept':'application/pdf','Authorization':'Bearer ${token??''}'}).timeout(const Duration(seconds:30)); if(r.statusCode<200||r.statusCode>=300) throw ApiException(r.statusCode,'Could not generate label.'); return r.bodyBytes; }

  Future<List<dynamic>> shipping({String? trackingNumber,String? state})=>_list('GET','/v1/shipping',q:{if(trackingNumber?.isNotEmpty==true)'tracking_number':trackingNumber!,if(state?.isNotEmpty==true)'state':state!});
  Future<Map<String,dynamic>> createShipping(Map<String,dynamic> p)=>_map('POST','/v1/shipping',b:p);
  Future<Map<String,dynamic>> updateShipping(int id,Map<String,dynamic> p)=>_map('POST','/v1/shipping/$id',b:p);

  Future<List<dynamic>> courierRates()=>_list('GET','/v1/courier-rates');
  Future<Map<String,dynamic>> createCourierRate(Map<String,dynamic> p)=>_map('POST','/v1/courier-rates',b:p);
  Future<Map<String,dynamic>> updateCourierRate(int id,Map<String,dynamic> p)=>_map('PUT','/v1/courier-rates/$id',b:p);
  Future<Map<String,dynamic>> deleteCourierRate(int id,Map<String,dynamic> p)=>_map('DELETE','/v1/courier-rates/$id',b:p);
  Future<List<dynamic>> monthlyRates()=>_list('GET','/v1/monthly-shipping-rates');
  Future<Map<String,dynamic>> createMonthlyRate(Map<String,dynamic> p)=>_map('POST','/v1/monthly-shipping-rates',b:p);
  Future<Map<String,dynamic>> updateMonthlyRate(int id,Map<String,dynamic> p)=>_map('PUT','/v1/monthly-shipping-rates/$id',b:p);
  Future<Map<String,dynamic>> deleteMonthlyRate(int id,Map<String,dynamic> p)=>_map('DELETE','/v1/monthly-shipping-rates/$id',b:p);

  Future<Map<String,dynamic>> settings()=>_map('GET','/v1/settings');
  Future<Map<String,dynamic>> updateSettings(Map<String,dynamic> p)=>_map('POST','/v1/settings',b:p);
  Future<List<dynamic>> users()=>_list('GET','/v1/users');
  Future<Map<String,dynamic>> createUser(Map<String,dynamic> p)=>_map('POST','/v1/users',b:p);
  Future<Map<String,dynamic>> updateUser(int id,Map<String,dynamic> p)=>_map('PUT','/v1/users/$id',b:p);

  Future<Map<String,dynamic>> salesReport({String? startDate,String? endDate})=>_map('GET','/v1/reports/sales',q:{if(startDate!=null)'start_date':startDate,if(endDate!=null)'end_date':endDate});
  Future<List<dynamic>> shippingReport()=>_list('GET','/v1/reports/shipping');
  Future<List<dynamic>> inventoryReport()=>_list('GET','/v1/reports/inventory');
  Future<Map<String,dynamic>> clearTestData(String confirmation)=>_map('POST','/v1/admin/clear-test-data',b:{'confirmation':confirmation});
}
