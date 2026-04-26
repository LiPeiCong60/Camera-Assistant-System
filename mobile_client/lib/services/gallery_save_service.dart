import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'local_image_resolver.dart';

class GallerySaveService {
  const GallerySaveService();

  static const MethodChannel _channel = MethodChannel(
    'camera_assistant/gallery_saver',
  );

  Future<String?> saveImageSource({
    required ResolvedImageSource source,
    required String fileName,
  }) async {
    final bytes = await _readBytes(source);
    return _channel.invokeMethod<String>('saveImage', <String, Object>{
      'bytes': bytes,
      'fileName': fileName,
    });
  }

  Future<Uint8List> _readBytes(ResolvedImageSource source) async {
    if (source.type == ResolvedImageSourceType.file) {
      return source.file!.readAsBytes();
    }

    final response = await http
        .get(Uri.parse(source.url!))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('图片下载失败：HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }
}
