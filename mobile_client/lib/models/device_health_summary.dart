class DeviceHealthSummary {
  const DeviceHealthSummary({
    required this.deviceCode,
    required this.status,
    required this.serviceVersion,
    this.sessionCode,
  });

  final String deviceCode;
  final String status;
  final String serviceVersion;
  final String? sessionCode;

  factory DeviceHealthSummary.fromJson(Map<String, dynamic> json) {
    return DeviceHealthSummary(
      deviceCode: json['device_code'] as String? ?? '',
      status: json['status'] as String? ?? 'unknown',
      serviceVersion: json['service_version'] as String? ?? '',
      sessionCode: json['session_code'] as String?,
    );
  }
}
