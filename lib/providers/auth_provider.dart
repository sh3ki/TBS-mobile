import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../services/credentials_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  UserModel? _user;
  bool _isLoading = false;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null;

  Future<void> restoreSession() async {
    _isLoading = true;
    notifyListeners();
    _user = await StorageService.getSession();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final user =
          await _authService.login(username: username, password: password);
      _user = user;
      await StorageService.saveSession(user);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = _user?.token;
      final username = _user?.username ?? '';
      final userId = _user?.id;
      
      // Log logout attempt for debugging
      print('[AuthProvider] Logout initiated - Username: $username, UserId: $userId');
      
      if (token != null && token.isNotEmpty) {
        try {
          await _authService.logout(
            token: token,
            username: username,
            userId: userId,
          );
          print('[AuthProvider] Logout API call successful');
        } catch (e) {
          // Log the error but don't fail - user should be logged out locally anyway
          print('[AuthProvider] Logout API failed: $e');
        }
      } else {
        print('[AuthProvider] No token available for logout');
      }
      
      // NOTE: We do NOT remove saved credentials on logout
      // The "Remember Me" feature should persist across logouts
      // Users can still log in with saved credentials immediately after logout
      
      _user = null;
      await StorageService.clearSession();
      print('[AuthProvider] Local session cleared successfully');
    } catch (e) {
      print('[AuthProvider] Logout error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
