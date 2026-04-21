class PlanSummary {
  const PlanSummary({
    required this.id,
    required this.planCode,
    required this.name,
    required this.priceCents,
    required this.currency,
    required this.status,
  });

  final int id;
  final String planCode;
  final String name;
  final int priceCents;
  final String currency;
  final String status;

  String get priceLabel => '${(priceCents / 100).toStringAsFixed(2)} $currency';

  factory PlanSummary.fromJson(Map<String, dynamic> json) {
    return PlanSummary(
      id: json['id'] as int,
      planCode: json['plan_code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      priceCents: json['price_cents'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'CNY',
      status: json['status'] as String? ?? 'inactive',
    );
  }
}
