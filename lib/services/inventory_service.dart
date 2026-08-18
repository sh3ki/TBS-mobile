import 'package:flutter/foundation.dart';

import 'api_service.dart';

class InventoryService {
  Future<List<Map<String, dynamic>>> searchInventory({
    required String username,
    required String searchTerm,
  }) async {
    final response = await ApiService.get(
      '/mobile/inventory/search',
      query: {'username': username, 'search': searchTerm, 'gate_status': 'CURRENTLY'},
    );

    if (!response.isSuccessCode || response.data['success'] != true) {
      throw Exception(ApiService.extractMessage(response.data));
    }

    return (response.data['data'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<List<Map<String, dynamic>>> loadCurrentInventory({
    required String username,
  }) async {
    final response = await ApiService.get(
      '/mobile/inventory/search',
      query: {'username': username, 'search': '', 'gate_status': 'CURRENTLY'},
    );

    if (!response.isSuccessCode || response.data['success'] != true) {
      throw Exception(ApiService.extractMessage(response.data));
    }

    return (response.data['data'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }
}
