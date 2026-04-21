class UserProfile {
  const UserProfile({
    required this.id,
    required this.userCode,
    required this.displayName,
    required this.role,
    required this.status,
    this.phone,
    this.email,
    this.avatarUrl,
  });

  final int id;
  final String userCode;
  final String displayName;
  final String role;
  final String status;
  final String? phone;
  final String? email;
  final String? avatarUrl;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as int,
      userCode: json['user_code'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      status: json['status'] as String? ?? 'inactive',
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}
