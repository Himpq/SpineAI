import 'dart:convert';

class UserModel {
  final int id;
  final String username;
  final String displayName;
  final String role;
  final bool isActive;
  final List<String> modules;
  final String? lastLoginAt;

  UserModel({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    required this.isActive,
    required this.modules,
    this.lastLoginAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    List<String> mods = [];
    if (json['module_permissions'] != null) {
      if (json['module_permissions'] is List) {
        mods = (json['module_permissions'] as List).cast<String>();
      } else if (json['module_permissions'] is String) {
        try {
          final parsed = json['module_permissions'] as String;
          if (parsed.isNotEmpty && parsed != '[]') {
            mods = List<String>.from(jsonDecode(parsed) as List);
          }
        } catch (_) {}
      }
    }
    if (json['modules'] is List) {
      mods = (json['modules'] as List).cast<String>();
    }
    return UserModel(
      id: json['id'] as int,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? json['username'] as String? ?? '',
      role: json['role'] as String? ?? 'doctor',
      isActive: json['is_active'] as bool? ?? true,
      modules: mods,
      lastLoginAt: json['last_login_at'] as String?,
    );
  }

  bool get isAdmin => role == 'admin';
  bool hasModule(String module) => isAdmin || modules.contains(module);
}
