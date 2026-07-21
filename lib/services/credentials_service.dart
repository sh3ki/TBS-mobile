import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class SavedCredential {
  final String username;
  final String password;

  SavedCredential({
    required this.username,
    required this.password,
  });

  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'password': password,
    };
  }

  factory SavedCredential.fromMap(Map<String, dynamic> map) {
    return SavedCredential(
      username: map['username'] as String,
      password: map['password'] as String,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory SavedCredential.fromJson(String source) =>
      SavedCredential.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

class CredentialsService {
  static const String _credentialsKey = 'saved_credentials';

  /// Save credentials locally
  static Future<void> saveCredentials(String username, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final credentials = await getCredentials();

      print('[CredentialsService] Saving credentials for: $username (existing: ${credentials.length})');

      // Remove if username already exists (update instead of duplicate)
      credentials.removeWhere((c) => c.username == username);

      // Add new credential
      credentials.add(SavedCredential(
        username: username,
        password: password,
      ));

      // Save all credentials
      final jsonList = credentials.map((c) => c.toJson()).toList();
      final saveSuccess = await prefs.setStringList(_credentialsKey, jsonList);
      print('[CredentialsService] Credentials saved for user: $username (success: $saveSuccess, total: ${credentials.length})');
    } catch (e) {
      print('[CredentialsService] Error saving credentials: $e');
      rethrow;
    }
  }

  /// Get all saved credentials
  static Future<List<SavedCredential>> getCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList(_credentialsKey) ?? [];

      print('[CredentialsService] Loading credentials - found: ${jsonList.length}');
      if (jsonList.isNotEmpty) {
        for (var json in jsonList) {
          final cred = SavedCredential.fromJson(json);
          print('[CredentialsService]   - Username: ${cred.username}');
        }
      }

      return jsonList
          .map((json) => SavedCredential.fromJson(json))
          .toList();
    } catch (e) {
      print('[CredentialsService] Error getting credentials: $e');
      return [];
    }
  }

  /// Get a specific credential
  static Future<SavedCredential?> getCredential(String username) async {
    try {
      final credentials = await getCredentials();
      return credentials.firstWhere(
        (c) => c.username == username,
        orElse: () => null as SavedCredential,
      ) as SavedCredential?;
    } catch (e) {
      print('[CredentialsService] Error getting specific credential: $e');
      return null;
    }
  }

  /// Remove a specific credential
  static Future<void> removeCredential(String username) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final credentials = await getCredentials();

      credentials.removeWhere((c) => c.username == username);

      final jsonList = credentials.map((c) => c.toJson()).toList();
      await prefs.setStringList(_credentialsKey, jsonList);
      print('[CredentialsService] Credential removed for user: $username');
    } catch (e) {
      print('[CredentialsService] Error removing credential: $e');
      rethrow;
    }
  }

  /// Clear all saved credentials
  static Future<void> clearAllCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_credentialsKey);
      print('[CredentialsService] All credentials cleared');
    } catch (e) {
      print('[CredentialsService] Error clearing credentials: $e');
      rethrow;
    }
  }
}
