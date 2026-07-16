import '../models/lookup_item.dart';
import '../models/pre_record_model.dart';
import 'api_service.dart';

class GateService {
  Future<List<PreRecord>> getPendingList(String username) async {
    final response = await ApiService.post(
      '/mobile/gateinout/list',
      body: {'username': username},
    );
    if (!response.isSuccessCode || response.data['success'] != true) {
      throw Exception(ApiService.extractMessage(response.data));
    }

    final records = (response.data['prelist'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PreRecord.fromJson)
        .toList();
    return records;
  }

  Future<List<LookupItem>> getClients(String username) async {
    final response = await ApiService.get('/mobile/gateinout/clients');
    if (!response.isSuccessCode || response.data['success'] != true) {
      throw Exception(ApiService.extractMessage(response.data));
    }

    return (response.data['data'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LookupItem.fromClientJson)
        .toList();
  }

  Future<List<LookupItem>> getStatusOptions(String username) async {
    final response =
        await ApiService.get('/mobile/gateinout/status-options');
    if (!response.isSuccessCode || response.data['success'] != true) {
      throw Exception(ApiService.extractMessage(response.data));
    }

    return (response.data['data'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LookupItem.fromStatusJson)
        .toList();
  }

  Future<List<LookupItem>> getSizeTypeOptions(String username) async {
    final response =
        await ApiService.get('/mobile/gateinout/sizetype-options');
    if (!response.isSuccessCode || response.data['success'] != true) {
      throw Exception(ApiService.extractMessage(response.data));
    }

    return (response.data['data'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LookupItem.fromSizeTypeJson)
        .toList();
  }

  Future<List<LookupItem>> getLoadOptions(String username) async {
    final response =
        await ApiService.get('/mobile/gateinout/load-options');
    if (!response.isSuccessCode || response.data['success'] != true) {
      throw Exception(ApiService.extractMessage(response.data));
    }

    return (response.data['data'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LookupItem.fromLoadTypeJson)
        .toList();
  }

  Future<String> addPreIn({
    required String username,
    required String containerNo,
    required String clientHash,
  }) async {
    final response = await ApiService.post(
      '/mobile/gateinout/check-container-in',
      body: {
        'username': username,
        'cno': containerNo,
        'client': clientHash,
      },
    );

    return ApiService.extractMessage(response.data);
  }

  Future<String> addPreOut({
    required String username,
    required String plateNo,
    required String hauler,
  }) async {
    final response = await ApiService.post(
      '/mobile/gateinout/check-container-out',
      body: {
        'username': username,
        'pno': plateNo,
        'hauler': hauler,
      },
    );

    return ApiService.extractMessage(response.data);
  }

  Future<Map<String, dynamic>> validateContainer({
    required String username,
    required String containerNo,
  }) async {
    final response = await ApiService.post(
      '/mobile/gateinout/validate-container',
      body: {
        'username': username,
        'container_no': containerNo,
      },
    );

    if (!response.isSuccessCode || response.data['success'] != true) {
      throw Exception(ApiService.extractMessage(response.data));
    }

    return (response.data['data'] as Map<String, dynamic>? ?? const {});
  }

  Future<String> processGateIn({
    required String username,
    required Map<String, dynamic> payload,
  }) async {
    final body = {
      'username': username,
      ...payload,
    };
    final response = await ApiService.post(
      '/mobile/gateinout/process-in',
      body: body,
    );

    if (!response.isSuccessCode || response.data['success'] != true) {
      throw Exception(ApiService.extractMessage(response.data));
    }

    return (response.data['message'] ?? 'Container successfully gated IN')
        .toString();
  }

  Future<String> processGateOut({
    required String username,
    required Map<String, dynamic> payload,
  }) async {
    final body = {
      'username': username,
      ...payload,
    };
    final response = await ApiService.post(
      '/mobile/gateinout/process-out',
      body: body,
    );

    if (!response.isSuccessCode || response.data['success'] != true) {
      throw Exception(ApiService.extractMessage(response.data));
    }

    return (response.data['message'] ?? 'Container successfully gated OUT')
        .toString();
  }
}
