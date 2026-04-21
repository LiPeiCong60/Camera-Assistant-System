class PlanSummary {
  const PlanSummary({
    required this.id,
    required this.planCode,
    required this.name,
    this.description,
    required this.priceCents,
    required this.currency,
    required this.billingCycleDays,
    this.captureQuota,
    this.aiTaskQuota,
    this.featureFlags = const <String, dynamic>{},
    required this.status,
  });

  final int id;
  final String planCode;
  final String name;
  final String? description;
  final int priceCents;
  final String currency;
  final int billingCycleDays;
  final int? captureQuota;
  final int? aiTaskQuota;
  final Map<String, dynamic> featureFlags;
  final String status;

  String get priceLabel => '${(priceCents / 100).toStringAsFixed(2)} $currency';

  String get billingCycleLabel =>
      billingCycleDays >= 30 && billingCycleDays % 30 == 0
      ? '每 ${billingCycleDays ~/ 30} 月'
      : '每 $billingCycleDays 天';

  factory PlanSummary.fromJson(Map<String, dynamic> json) {
    final rawFeatureFlags = json['feature_flags'];
    return PlanSummary(
      id: json['id'] as int,
      planCode: json['plan_code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      priceCents: json['price_cents'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'CNY',
      billingCycleDays: json['billing_cycle_days'] as int? ?? 30,
      captureQuota: json['capture_quota'] as int?,
      aiTaskQuota: json['ai_task_quota'] as int?,
      featureFlags: rawFeatureFlags is Map
          ? Map<String, dynamic>.from(rawFeatureFlags)
          : const <String, dynamic>{},
      status: json['status'] as String? ?? 'inactive',
    );
  }
}
