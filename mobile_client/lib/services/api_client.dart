import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({
    required String baseUrl,
    Duration requestTimeout = const Duration(seconds: 90),
  }) : _baseUrl = _normalizeBaseUrl(baseUrl),
       _requestTimeout = requestTimeout;

  final String _baseUrl;
  final Duration _requestTimeout;

  Future<Map<String, dynamic>> getJson(
    String path, {
    String? accessToken,
  }) async {
    final response = await _send(
      () => http.get(
        Uri.parse('$_baseUrl$path'),
        headers: _buildHeaders(accessToken: accessToken),
      ),
    );
    return _decodeEnvelope(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    required Map<String, dynamic> body,
    String? accessToken,
  }) async {
    final response = await _send(
      () => http.post(
        Uri.parse('$_baseUrl$path'),
        headers: _buildHeaders(accessToken: accessToken),
        body: jsonEncode(body),
      ),
    );
    return _decodeEnvelope(response);
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    String? accessToken,
  }) async {
    final response = await _send(
      () => http.delete(
        Uri.parse('$_baseUrl$path'),
        headers: _buildHeaders(accessToken: accessToken),
      ),
    );
    return _decodeEnvelope(response);
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required String fileField,
    required String filePath,
    Map<String, String> fields = const <String, String>{},
    String? accessToken,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl$path'));
    request.headers.addAll(
      _buildHeaders(accessToken: accessToken, isJson: false),
    );
    request.fields.addAll(fields);
    request.files.add(await http.MultipartFile.fromPath(fileField, filePath));
    final streamedResponse = await _sendStream(() => request.send());
    final response = await http.Response.fromStream(streamedResponse);
    return _decodeEnvelope(response);
  }

  static String _normalizeBaseUrl(String baseUrl) {
    if (baseUrl.endsWith('/')) {
      return baseUrl.substring(0, baseUrl.length - 1);
    }
    return baseUrl;
  }

  Map<String, String> _buildHeaders({String? accessToken, bool isJson = true}) {
    final headers = <String, String>{'Accept': 'application/json'};
    if (isJson) {
      headers['Content-Type'] = 'application/json';
    }
    if (accessToken != null && accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    return headers;
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(_requestTimeout);
    } on TimeoutException {
      throw const ApiException('请求超时，请检查网络连接或稍后重试。');
    } on SocketException {
      throw const ApiException('无法连接服务，请确认服务已启动且地址可访问。');
    } on http.ClientException {
      throw const ApiException('网络请求失败，请检查地址配置和网络状态。');
    }
  }

  Future<http.StreamedResponse> _sendStream(
    Future<http.StreamedResponse> Function() request,
  ) async {
    try {
      return await request().timeout(_requestTimeout);
    } on TimeoutException {
      throw const ApiException('上传超时，请检查网络连接或稍后重试。');
    } on SocketException {
      throw const ApiException('无法连接服务，请确认服务已启动且地址可访问。');
    } on http.ClientException {
      throw const ApiException('网络请求失败，请检查地址配置和网络状态。');
    }
  }

  Map<String, dynamic> _decodeEnvelope(http.Response response) {
    final body = _safeDecodeBody(response);
    final success = body['success'] as bool? ?? false;
    if (!success) {
      final backendMessage = body['message'] as String?;
      throw ApiException(
        _humanizeErrorMessage(
          response.statusCode,
          backendMessage,
          fallback: '请求失败，请稍后重试。',
        ),
        statusCode: response.statusCode,
      );
    }

    return body['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
  }

  Map<String, dynamic> _safeDecodeBody(http.Response response) {
    if (response.body.isEmpty) {
      return <String, dynamic>{};
    }

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw ApiException(
        response.statusCode >= 500
            ? '服务暂时不可用，请稍后重试。'
            : '服务返回了无法识别的数据，请稍后重试。',
        statusCode: response.statusCode,
      );
    }
  }

  String _humanizeErrorMessage(
    int statusCode,
    String? backendMessage, {
    required String fallback,
  }) {
    final normalizedMessage = backendMessage?.trim();
    if (normalizedMessage == null ||
        normalizedMessage.isEmpty ||
        normalizedMessage == 'Not Found' ||
        normalizedMessage == 'request failed') {
      return _fallbackStatusMessage(statusCode, fallback);
    }

    if (normalizedMessage == 'invalid request') {
      return '请求参数无效，请检查输入内容后重试。';
    }
    if (normalizedMessage == 'invalid token signature') {
      return '登录已失效，请重新登录。';
    }
    return normalizedMessage;
  }

  String _fallbackStatusMessage(int statusCode, String fallback) {
    switch (statusCode) {
      case 400:
        return '请求参数无效，请检查输入内容后重试。';
      case 401:
        return '登录已失效，请重新登录。';
      case 403:
        return '当前账号没有权限执行该操作。';
      case 404:
        return '请求的服务或资源不存在，请确认服务已经更新。';
      case 409:
        return '当前操作与现有数据冲突，请刷新后重试。';
      case 422:
        return '提交的数据格式不正确，请检查后重试。';
      default:
        if (statusCode >= 500) {
          return '服务暂时不可用，请稍后重试。';
        }
        return fallback;
    }
  }
}
