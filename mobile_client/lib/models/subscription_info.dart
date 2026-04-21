class SubscriptionInfo {
  const SubscriptionInfo({
    required this.id,
    required this.userId,
    required this.planId,
    required this.status,
    required this.autoRenew,
  });

  final int id;
  final int userId;
  final int planId;
  final String status;
  final bool autoRenew;

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    return SubscriptionInfo(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      planId: json['plan_id'] as int,
      status: json['status'] as String? ?? 'inactive',
      autoRenew: json['auto_renew'] as bool? ?? false,
    );
  }
}
