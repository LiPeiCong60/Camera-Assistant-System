part of '../device_link_page.dart';

class _MobilePushSocketSender {
  WebSocket? _socket;

  bool get isOpen => _socket?.readyState == WebSocket.open;

  Future<void> connect({
    required Uri uri,
    required Duration timeout,
    required VoidCallback onError,
    required VoidCallback onClosed,
  }) async {
    await close();
    final socket = await WebSocket.connect(uri.toString()).timeout(timeout);
    _socket = socket;
    socket.listen(
      (_) {},
      onError: (_) {
        if (identical(_socket, socket)) {
          _socket = null;
        }
        onError();
      },
      onDone: () {
        if (identical(_socket, socket)) {
          _socket = null;
        }
        onClosed();
      },
      cancelOnError: false,
    );
  }

  void sendConfig({required CameraImage image, required int rotationDegrees}) {
    final socket = _openSocket;
    socket.add(
      _MobilePushTools.buildNv21ConfigJson(
        image: image,
        rotationDegrees: rotationDegrees,
      ),
    );
  }

  void sendFrame(Uint8List frameBytes) {
    _openSocket.add(frameBytes);
  }

  Future<void> close() async {
    final socket = _socket;
    _socket = null;
    if (socket == null) {
      return;
    }
    try {
      await socket.close();
    } catch (_) {
      // Ignore socket shutdown errors while leaving the page.
    }
  }

  WebSocket get _openSocket {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw StateError('Mobile push socket is not open.');
    }
    return socket;
  }
}
