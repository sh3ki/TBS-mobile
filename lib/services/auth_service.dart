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

  Future<void> logout(String token) async {
    final response = await ApiService.post('/mobile/logout', token: token);
    if (!response.isSuccessCode) {
      throw Exception(ApiService.extractMessage(response.data));
    }
  }
}
