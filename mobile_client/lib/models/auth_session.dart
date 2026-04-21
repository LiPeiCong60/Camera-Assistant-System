class AuthUserSummary {
  const AuthUserSummary({
    required this.id,
    required this.displayName,
    required this.role,
    required this.status,
  });

  final int id;
  final String displayName;
  final String role;
  final String status;

  factory AuthUserSummary.fromJson(Map<String, dynamic> json) {
    return AuthUserSummary(
      id: json['id'] as int,
      displayName: json['display_name'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      status: json['status'] as String? ?? 'inactive',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'display_name': displayName,
      'role': role,
      'status': status,
    };
  }
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.tokenType,
    required this.user,
  });

  final String accessToken;
  final String tokenType;
  final AuthUserSummary user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['access_token'] as String? ?? '',
      tokenType: json['token_type'] as String? ?? 'bearer',
      user: AuthUserSummary.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'access_token': accessToken,
      'token_type': tokenType,
      'user': user.toJson(),
    };
  }
}
