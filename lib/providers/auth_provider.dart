import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';

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
      if (token != null && token.isNotEmpty) {
        try {
          await _authService.logout(token);
        } catch (_) {
          // Ignore logout API failure and clear local session anyway.
        }
      }
      _user = null;
      await StorageService.clearSession();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
