import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ApiResponse {
  final int statusCode;
  final Map<String, dynamic> data;

  const ApiResponse({required this.statusCode, required this.data});

  bool get isSuccessCode => statusCode >= 200 && statusCode < 300;
}

class ApiService {
  static Map<String, String> _headers({String? token}) {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<ApiResponse> get(
    String path, {
    String? token,
    Map<String, String>? query,
  }) async {
    final response = await http
        .get(
          AppConfig.uri(path, query),
          headers: _headers(token: token),
        )
        .timeout(AppConfig.requestTimeout);
    return ApiResponse(
      statusCode: response.statusCode,
      data: _decodeBody(response.body),
    );
  }

  static Future<ApiResponse> post(
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    final response = await http
        .post(
          AppConfig.uri(path),
          headers: _headers(token: token),
          body: jsonEncode(body ?? const {}),
        )
        .timeout(AppConfig.requestTimeout);
    return ApiResponse(
      statusCode: response.statusCode,
      data: _decodeBody(response.body),
    );
  }

  static Map<String, dynamic> _decodeBody(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{'data': decoded};
  }

  static String extractMessage(Map<String, dynamic> data) {
    final message = data['message'];
    if (message is String && message.isNotEmpty) {
      return _stripHtml(message);
    }
    if (message is List && message.length > 1) {
      return _stripHtml(message[1].toString());
    }
    if (data['error'] is String) {
      return data['error'].toString();
    }
    return 'Request failed. Please try again.';
  }

  static String _stripHtml(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .trim();
  }
}
