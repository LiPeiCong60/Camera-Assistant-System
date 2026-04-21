import 'dart:io';

import '../models/capture_record.dart';

enum ResolvedImageSourceType { file, network }

class ResolvedImageSource {
  const ResolvedImageSource.file(this.file)
      : type = ResolvedImageSourceType.file,
        url = null;

  const ResolvedImageSource.network(this.url)
      : type = ResolvedImageSourceType.network,
        file = null;

  final ResolvedImageSourceType type;
  final File? file;
  final String? url;
}

class LocalImageResolver {
  static File? resolveCaptureRecord(CaptureRecord capture) {
    return resolvePath(capture.thumbnailUrl) ?? resolvePath(capture.fileUrl);
  }

  static ResolvedImageSource? resolveCaptureRecordSource(CaptureRecord capture) {
    return resolveSource(capture.thumbnailUrl) ?? resolveSource(capture.fileUrl);
  }

  static ResolvedImageSource? resolveSource(String? rawPath) {
    final file = resolvePath(rawPath);
    if (file != null) {
      return ResolvedImageSource.file(file);
    }

    if (rawPath == null || rawPath.trim().isEmpty) {
      return null;
    }

    final trimmed = rawPath.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty) {
      return ResolvedImageSource.network(trimmed);
    }

    return null;
  }

  static File? resolvePath(String? rawPath) {
    if (rawPath == null || rawPath.trim().isEmpty) {
      return null;
    }

    final trimmed = rawPath.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme == 'file') {
      final file = File.fromUri(uri);
      if (file.existsSync()) {
        return file;
      }
    }

    final directFile = File(trimmed);
    if (directFile.existsSync()) {
      return directFile;
    }

    final relativeFile = File(
      '${Directory.current.path}${Platform.pathSeparator}$trimmed',
    );
    if (relativeFile.existsSync()) {
      return relativeFile;
    }

    return null;
  }
}
