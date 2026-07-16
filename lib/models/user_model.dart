class UserModel {
  final int id;
  final String username;
  final String fullName;
  final String token;

  const UserModel({
    required this.id,
    required this.username,
    required this.fullName,
    required this.token,
  });

  factory UserModel.fromLoginResponse(Map<String, dynamic> json) {
    final user = (json['user'] as Map<String, dynamic>? ?? const {});
    return UserModel(
      id: (user['id'] as num?)?.toInt() ?? 0,
      username: (user['username'] ?? '').toString(),
      fullName: (user['full_name'] ?? '').toString(),
      token: (json['token'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'fullName': fullName,
      'token': token,
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: (json['username'] ?? '').toString(),
      fullName: (json['fullName'] ?? '').toString(),
      token: (json['token'] ?? '').toString(),
    );
  }
}
