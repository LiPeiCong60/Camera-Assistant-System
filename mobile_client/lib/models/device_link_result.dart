class DeviceLinkResult {
  const DeviceLinkResult({
    this.selectedTemplateId,
    this.selectedTemplateName,
    this.deviceSessionCode,
    this.lastCapturePath,
    this.backendTaskCode,
    this.aiLockEnabled = false,
    this.source = 'device_link_page',
  });

  final int? selectedTemplateId;
  final String? selectedTemplateName;
  final String? deviceSessionCode;
  final String? lastCapturePath;
  final String? backendTaskCode;
  final bool aiLockEnabled;
  final String source;
}
