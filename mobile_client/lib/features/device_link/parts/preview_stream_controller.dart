part of '../device_link_page.dart';

class _DevicePreviewStreamController extends ChangeNotifier {
  WebSocket? _socket;
  Uint8List? _latestFrameBytes;
  DateTime? _latestFrameAt;
  String? _errorMessage;

  Uint8List? get latestFrameBytes => _latestFrameBytes;

  DateTime? get latestFrameAt => _latestFrameAt;

  String? get errorMessage => _errorMessage;

  Future<void> start({
    required Uri uri,
    required bool hasSession,
    required Duration timeout,
  }) async {
    if (_socket != null || !hasSession) {
      return;
    }

    try {
      final socket = await WebSocket.connect(uri.toString()).timeout(timeout);
      _socket = socket;
      socket.listen(
        (dynamic data) {
          if (data is! List<int>) {
            return;
          }
          _latestFrameBytes = Uint8List.fromList(data);
          _latestFrameAt = DateTime.now();
          _errorMessage = null;
          notifyListeners();
        },
        onError: (_) {
          _socket = null;
          _errorMessage = '实时预览连接出错，请检查设备运行时地址。';
          notifyListeners();
        },
        onDone: () {
          _socket = null;
          notifyListeners();
        },
        cancelOnError: false,
      );
    } catch (_) {
      _socket = null;
      _errorMessage = '实时预览暂时不可用，请确认设备会话已打开。';
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final socket = _socket;
    _socket = null;
    if (socket == null) {
      return;
    }
    try {
      await socket.close();
    } catch (_) {
      // Ignore preview socket shutdown errors while leaving the page.
    } finally {
      notifyListeners();
    }
  }

  void clear({bool clearError = true, DateTime? frameAt}) {
    _latestFrameBytes = null;
    _latestFrameAt = frameAt;
    if (clearError) {
      _errorMessage = null;
    }
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    final socket = _socket;
    _socket = null;
    unawaited(socket?.close());
    super.dispose();
  }
}
