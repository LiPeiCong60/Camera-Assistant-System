class CaptureUploadResult {
  const CaptureUploadResult({
    required this.fileUrl,
    required this.storageProvider,
    required this.storagePath,
    required this.relativePath,
    required this.originalFilename,
    this.contentType,
  });

  final String fileUrl;
  final String storageProvider;
  final String storagePath;
  final String relativePath;
  final String originalFilename;
  final String? contentType;

  factory CaptureUploadResult.fromJson(Map<String, dynamic> json) {
    return CaptureUploadResult(
      fileUrl: json['file_url'] as String? ?? '',
      storageProvider: json['storage_provider'] as String? ?? 'local_static',
      storagePath: json['storage_path'] as String? ?? '',
      relativePath: json['relative_path'] as String? ?? '',
      originalFilename: json['original_filename'] as String? ?? '',
      contentType: json['content_type'] as String?,
    );
  }
}
