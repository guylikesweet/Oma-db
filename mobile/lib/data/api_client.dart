import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
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
  final http.Client _client;
  final FlutterSecureStorage _storage;
  final Uuid _uuid = const Uuid();
  String _op([String? prefix]) => '${prefix ?? 'op'}-${_uuid.v4()}';
  Future<String?> token()=>_storage.read(key:'api_token');
  Future<void> saveToken(String v)=>_storage.write(key:'api_token',value:v);
  Future<void> clearToken()=>_storage.delete(key:'api_token');

  Uri _uri(String path, [Map<String,String>? query]) {
    final base=Uri.parse(AppConfig.apiBaseUrl);
    final joined='${base.path.replaceFirst(RegExp(r'/$'), '')}$path';
    return base.replace(path:joined,queryParameters:query);
  }
  Future<dynamic> _request(String method,String path,{Map<String,dynamic>? body,Map<String,String>? query,String? operationId}) async {
    final t=await token(); final headers=<String,String>{'Accept':'application/json'};
    if(body!=null)headers['Content-Type']='application/json'; if(t!=null&&t.isNotEmpty)headers['Authorization']='Bearer $t'; if(operationId!=null)headers['X-Operation-ID']=operationId;
    final u=_uri(path,query); late http.Response r;
    final encoded=body==null?null:jsonEncode(body);
    if(method=='GET')r=await _client.get(u,headers:headers).timeout(const Duration(seconds:20));
    else if(method=='POST')r=await _client.post(u,headers:headers,body:encoded).timeout(const Duration(seconds:20));
    else if(method=='PATCH')r=await _client.patch(u,headers:headers,body:encoded).timeout(const Duration(seconds:20));
    else if(method=='DELETE')r=await _client.delete(u,headers:headers,body:encoded).timeout(const Duration(seconds:20));
    else throw ArgumentError('Unsupported method $method');
    dynamic decoded; try{decoded=r.body.isEmpty?null:jsonDecode(r.body);}catch(_){decoded=null;}
    if(r.statusCode<200||r.statusCode>=300){final m=decoded is Map&&decoded['error']!=null?decoded['error'].toString():'Request failed';throw ApiException(r.statusCode,m);}
    return decoded;
  }
  Future<Map<String,dynamic>> login(String u,String p)=>_map(await _request('POST','/v1/auth/login',body:{'username':u,'password':p}));
  Future<Map<String,dynamic>> me()=>_map(await _request('GET','/v1/auth/me'));
  Future<void> logout() async{await _request('POST','/v1/auth/logout');}
  Future<Map<String,dynamic>> bootstrap()=>_map(await _request('GET','/v1/bootstrap'));
  Future<Map<String,dynamic>> sync(int cursor,{int limit=250})=>_map(await _request('GET','/v1/sync',query:{'cursor':'$cursor','limit':'$limit'}));
  Future<List<dynamic>> products()=>_list(await _request('GET','/v1/products'));
  Future<Map<String,dynamic>> product(int id)=>_map(await _request('GET','/v1/products/$id'));
  Future<Map<String,dynamic>> createProduct(Map<String,dynamic> p)=>_map(await _request('POST','/v1/products',body:{...p,'operation_id':p['operation_id']??_op('product-create')},operationId:p['operation_id']?.toString()));
  Future<Map<String,dynamic>> updateProduct(int id,Map<String,dynamic> p)=>_map(await _request('PATCH','/v1/products/$id',body:{...p,'operation_id':p['operation_id']??_op('product-update')},operationId:p['operation_id']?.toString()));
  Future<void> deleteProduct(int id) async{await _request('DELETE','/v1/products/$id');}
  Future<Map<String,dynamic>> stockAdjust(Map<String,dynamic> p)=>_map(await _request('POST','/v1/stock/adjust',body:{...p,'operation_id':p['operation_id']??_op('stock')},operationId:p['operation_id']?.toString()));
  Future<List<dynamic>> stockLog() async => _list(await _request('GET','/v1/reports/inventory'));
  Future<List<dynamic>> sales()=>_list(await _request('GET','/v1/sales'));
  Future<Map<String,dynamic>> sale(int id)=>_map(await _request('GET','/v1/sales/$id'));
  Future<Map<String,dynamic>> createSale(Map<String,dynamic> p)=>_map(await _request('POST','/v1/sales',body:{...p,'operation_id':p['operation_id']??_op('sale-create')},operationId:p['operation_id']?.toString()));
  Future<Map<String,dynamic>> updateSaleStatus(int id,Map<String,dynamic> p)=>_map(await _request('POST','/v1/sales/$id/status',body:{...p,'operation_id':p['operation_id']??_op('sale-status')},operationId:p['operation_id']?.toString()));
  Future<Map<String,dynamic>> settleShipping(int id,Map<String,dynamic> p)=>_map(await _request('POST','/v1/sales/$id/settle-shipping',body:{...p,'operation_id':p['operation_id']??_op('settle')},operationId:p['operation_id']?.toString()));
  Future<List<dynamic>> batches()=>_list(await _request('GET','/v1/batches'));
  Future<Map<String,dynamic>> batch(int id)=>_map(await _request('GET','/v1/batches/$id'));
  Future<Map<String,dynamic>> createBatch(Map<String,dynamic> p)=>_map(await _request('POST','/v1/batches',body:{...p,'operation_id':p['operation_id']??_op('batch-create')},operationId:p['operation_id']?.toString()));
  Future<Map<String,dynamic>> addSaleToBatch(int b,int s)=>_map(await _request('POST','/v1/batches/$b/sales/$s',body:{'operation_id':_op('batch-add')}));
  Future<Map<String,dynamic>> removeSaleFromBatch(int b,int s)=>_map(await _request('DELETE','/v1/batches/$b/sales/$s',body:{'operation_id':_op('batch-remove')}));
  Future<Map<String,dynamic>> arriveBatch(int b,Map<String,dynamic> p)=>_map(await _request('POST','/v1/batches/$b/arrive',body:{...p,'operation_id':p['operation_id']??_op('batch-arrive')},operationId:p['operation_id']?.toString()));
  Future<List<dynamic>> deliveries()=>_list(await _request('GET','/v1/deliveries'));
  Future<Map<String,dynamic>> readyDeliveries()=>_map(await _request('GET','/v1/deliveries/ready'));
  Future<Map<String,dynamic>> delivery(int id)=>_map(await _request('GET','/v1/deliveries/$id'));
  Future<Map<String,dynamic>> createDelivery(Map<String,dynamic> p)=>_map(await _request('POST','/v1/deliveries',body:{...p,'operation_id':p['operation_id']??_op('delivery-create')},operationId:p['operation_id']?.toString()));
  Future<Map<String,dynamic>> updateDeliveryStatus(int id,Map<String,dynamic> p)=>_map(await _request('POST','/v1/deliveries/$id/status',body:{...p,'operation_id':p['operation_id']??_op('delivery-status')},operationId:p['operation_id']?.toString()));
  Future<Map<String,dynamic>> saveLabelData(int id,Map<String,dynamic> p)=>_map(await _request('POST','/v1/deliveries/$id/label-data',body:{...p,'operation_id':p['operation_id']??_op('label-data')},operationId:p['operation_id']?.toString()));
  Future<Uint8List> labelPdf(int id) async { final t=await token(); final h={'Authorization':'Bearer ${t??''}'}; final r=await _client.get(_uri('/v1/deliveries/$id/label.pdf'),headers:h).timeout(const Duration(seconds:30)); if(r.statusCode<200||r.statusCode>=300)throw ApiException(r.statusCode,'Unable to generate label'); return r.bodyBytes; }
  Future<List<dynamic>> shipping()=>_list(await _request('GET','/v1/shipping'));
  Future<List<dynamic>> searchShipping({String? trackingNumber,String? state})=>_list(await _request('GET','/v1/shipping/search',query:{if(trackingNumber!=null&&trackingNumber.isNotEmpty)'tracking_number':trackingNumber,if(state!=null&&state.isNotEmpty)'state':state}));
  Future<Map<String,dynamic>> createShipping(Map<String,dynamic> p)=>_map(await _request('POST','/v1/shipping',body:{...p,'operation_id':p['operation_id']??_op('shipping-create')},operationId:p['operation_id']?.toString()));
  Future<Map<String,dynamic>> updateShipping(int id,Map<String,dynamic> p)=>_map(await _request('POST','/v1/shipping/$id',body:{...p,'operation_id':p['operation_id']??_op('shipping-update')},operationId:p['operation_id']?.toString()));
  Future<List<dynamic>> courierRates()=>_list(await _request('GET','/v1/rates/courier'));
  Future<Map<String,dynamic>> createCourierRate(Map<String,dynamic> p)=>_map(await _request('POST','/v1/rates/courier',body:p));
  Future<Map<String,dynamic>> updateCourierRate(int id,Map<String,dynamic> p)=>_map(await _request('PATCH','/v1/rates/courier/$id',body:p));
  Future<void> deleteCourierRate(int id) async{await _request('DELETE','/v1/rates/courier/$id');}
  Future<List<dynamic>> monthlyRates()=>_list(await _request('GET','/v1/rates/monthly'));
  Future<Map<String,dynamic>> createMonthlyRate(Map<String,dynamic> p)=>_map(await _request('POST','/v1/rates/monthly',body:p));
  Future<Map<String,dynamic>> updateMonthlyRate(int id,Map<String,dynamic> p)=>_map(await _request('PATCH','/v1/rates/monthly/$id',body:p));
  Future<void> deleteMonthlyRate(int id) async{await _request('DELETE','/v1/rates/monthly/$id');}
  Future<Map<String,dynamic>> dashboard()=>_map(await _request('GET','/v1/dashboard'));
  Future<Map<String,dynamic>> salesReport({String? start,String? end})=>_map(await _request('GET','/v1/reports/sales',query:{if(start!=null)'start_date':start,if(end!=null)'end_date':end}));
  Future<List<dynamic>> shippingReport()=>_list(await _request('GET','/v1/reports/shipping'));
  Future<List<dynamic>> inventoryReport()=>_list(await _request('GET','/v1/reports/inventory'));
  Future<Map<String,dynamic>> settings()=>_map(await _request('GET','/v1/settings'));
  Future<Map<String,dynamic>> updateSettings(Map<String,dynamic> p)=>_map(await _request('PATCH','/v1/settings',body:{...p,'operation_id':p['operation_id']??_op('settings')},operationId:p['operation_id']?.toString()));
  Future<List<dynamic>> users()=>_list(await _request('GET','/v1/users'));
  Future<Map<String,dynamic>> createUser(Map<String,dynamic> p)=>_map(await _request('POST','/v1/users',body:p));
  Future<void> deleteUser(int id) async{await _request('DELETE','/v1/users/$id');}
  Future<Map<String,dynamic>> clearTestData({String? confirmation})=>_map(await _request('POST','/v1/clear-test-data',body:{'confirmation':confirmation}));
  Future<Map<String,dynamic>> clearTestDataInfo()=>_map(await _request('GET','/v1/clear-test-data'));
  Future<Map<String,dynamic>> changePassword(String current, String next) => _map(await _request('POST','/v1/auth/change-password',body:{'current_password':current,'new_password':next}));
  Future<Uint8List> reportCsv(String kind,{String? start,String? end}) async {
    final t=await token(); final h={'Authorization':'Bearer ${t??''}'};
    final q=<String,String>{if(start!=null)'start_date':start!,if(end!=null)'end_date':end!};
    final r=await _client.get(_uri('/v1/reports/$kind.csv',q),headers:h).timeout(const Duration(seconds:30));
    if(r.statusCode<200||r.statusCode>=300) throw ApiException(r.statusCode,'Unable to export report'); return r.bodyBytes;
  }
  Future<Map<String,dynamic>> uploadLogo(Uint8List bytes,String mime) async => updateSettings({'logo_base64':base64Encode(bytes),'logo_mimetype':mime});
  Future<Uint8List> logoBytes() async { final t=await token(); final r=await _client.get(_uri('/v1/settings/logo'),headers:{'Authorization':'Bearer ${t??''}'}).timeout(const Duration(seconds:20)); if(r.statusCode<200||r.statusCode>=300)throw ApiException(r.statusCode,'Unable to load logo'); return r.bodyBytes; }
  Map<String,dynamic> _map(dynamic x)=>Map<String,dynamic>.from(x as Map);
  List<dynamic> _list(dynamic x)=>List<dynamic>.from(x as List);
}
