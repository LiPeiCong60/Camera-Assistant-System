class SubscriptionInfo {
  const SubscriptionInfo({
    required this.id,
    required this.userId,
    required this.planId,
    required this.status,
    required this.startedAt,
    this.expiresAt,
    required this.autoRenew,
    this.quotaSnapshot = const <String, dynamic>{},
  });

  final int id;
  final int userId;
  final int planId;
  final String status;
  final DateTime startedAt;
  final DateTime? expiresAt;
  final bool autoRenew;
  final Map<String, dynamic> quotaSnapshot;

  int? get captureQuota => _readQuotaValue('capture_quota');

  int? get aiTaskQuota => _readQuotaValue('ai_task_quota');

  int? _readQuotaValue(String key) {
    final value = quotaSnapshot[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    final rawQuotaSnapshot = json['quota_snapshot'];
    return SubscriptionInfo(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      planId: json['plan_id'] as int,
      status: json['status'] as String? ?? 'inactive',
      startedAt: DateTime.parse(
        json['started_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.parse(json['expires_at'] as String),
      autoRenew: json['auto_renew'] as bool? ?? false,
      quotaSnapshot: rawQuotaSnapshot is Map
          ? Map<String, dynamic>.from(rawQuotaSnapshot)
          : const <String, dynamic>{},
    );
  }
}
