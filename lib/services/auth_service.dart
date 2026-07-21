import '../models/user_model.dart';
import 'api_service.dart';

class AuthService {
  Future<UserModel> login(
      {required String username, required String password}) async {
    final response = await ApiService.post(
      '/mobile/login',
      body: {
        'username': username,
        'password': password,
      },
    );

    if (!response.isSuccessCode || response.data['success'] != true) {
      throw Exception(ApiService.extractMessage(response.data));
    }

    return UserModel.fromLoginResponse(response.data);
  }

  Future<void> logout({
    required String token,
    required String username,
    int? userId,
  }) async {
    print('[AuthService] Logout request - Username: $username, UserId: $userId');
    
    final response = await ApiService.post(
      '/mobile/logout',
      token: token,
      body: {
        'username': username,
        'user_id': userId,
      },
    );
    
    print('[AuthService] Logout response - Status: ${response.statusCode}, Success: ${response.isSuccessCode}');
    
    if (!response.isSuccessCode) {
      print('[AuthService] Logout failed - Response: ${response.data}');
      throw Exception(ApiService.extractMessage(response.data));
    }
    
    print('[AuthService] Logout successful');
  }
}
