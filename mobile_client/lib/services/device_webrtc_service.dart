import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

class DeviceWebRtcSession {
  DeviceWebRtcSession({
    required this.peerConnection,
    required this.localStream,
    required this.remoteRenderer,
    required this.lensDirection,
  });

  final RTCPeerConnection peerConnection;
  final MediaStream localStream;
  final RTCVideoRenderer remoteRenderer;
  final CameraLensDirection lensDirection;

  Future<void> dispose() async {
    remoteRenderer.srcObject = null;
    for (final track in localStream.getTracks()) {
      await track.stop();
    }
    await localStream.dispose();
    await peerConnection.close();
    await peerConnection.dispose();
    await remoteRenderer.dispose();
  }
}

class DeviceWebRtcService {
  const DeviceWebRtcService();

  static const Duration _requestTimeout = Duration(seconds: 12);
  static const Duration _iceGatheringTimeout = Duration(seconds: 3);

  Future<DeviceWebRtcSession> start({
    required String baseUrl,
    required CameraLensDirection lensDirection,
    void Function(RTCPeerConnectionState state)? onConnectionState,
  }) async {
    final remoteRenderer = RTCVideoRenderer();
    await remoteRenderer.initialize();

    RTCPeerConnection? peerConnection;
    MediaStream? localStream;
    try {
      peerConnection = await createPeerConnection(
        const <String, dynamic>{
          'sdpSemantics': 'unified-plan',
          'iceServers': <Map<String, dynamic>>[],
        },
        const <String, dynamic>{
          'mandatory': <String, dynamic>{},
          'optional': <Map<String, dynamic>>[],
        },
      );
      peerConnection.onConnectionState = onConnectionState;
      peerConnection.onTrack = (RTCTrackEvent event) {
        if (event.track.kind != 'video' || event.streams.isEmpty) {
          return;
        }
        remoteRenderer.srcObject = event.streams.first;
      };

      localStream = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
        'audio': false,
        'video': <String, dynamic>{
          'mandatory': <String, dynamic>{
            'minWidth': '640',
            'minHeight': '480',
            'minFrameRate': '20',
          },
          'facingMode': lensDirection == CameraLensDirection.front
              ? 'user'
              : 'environment',
          'optional': <Map<String, dynamic>>[],
        },
      });

      for (final track in localStream.getVideoTracks()) {
        await peerConnection.addTrack(track, localStream);
      }
      await peerConnection.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );

      final offer = await peerConnection.createOffer(<String, dynamic>{});
      await peerConnection.setLocalDescription(offer);
      await _waitForIceGathering(peerConnection);
      final localDescription = await peerConnection.getLocalDescription();
      if (localDescription?.sdp == null || localDescription?.type == null) {
        throw const ApiException('WebRTC offer 创建失败，请重试。');
      }

      final answer = await _postOffer(
        baseUrl: baseUrl,
        sdp: localDescription!.sdp!,
        type: localDescription.type!,
      );
      await peerConnection.setRemoteDescription(
        RTCSessionDescription(
          answer['sdp'] as String? ?? '',
          answer['type'] as String? ?? 'answer',
        ),
      );

      return DeviceWebRtcSession(
        peerConnection: peerConnection,
        localStream: localStream,
        remoteRenderer: remoteRenderer,
        lensDirection: lensDirection,
      );
    } catch (_) {
      remoteRenderer.srcObject = null;
      await localStream?.dispose();
      await peerConnection?.close();
      await peerConnection?.dispose();
      await remoteRenderer.dispose();
      rethrow;
    }
  }

  Future<void> _waitForIceGathering(RTCPeerConnection peerConnection) async {
    if (peerConnection.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }

    final completer = Completer<void>();
    peerConnection.onIceGatheringState = (RTCIceGatheringState state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !completer.isCompleted) {
        completer.complete();
      }
    };
    try {
      await completer.future.timeout(_iceGatheringTimeout);
    } on TimeoutException {
      // Host candidates are usually available quickly on LAN. Continue so the
      // device can still answer when the platform reports gathering slowly.
    }
  }

  Future<Map<String, dynamic>> _postOffer({
    required String baseUrl,
    required String sdp,
    required String type,
  }) async {
    final response = await http
        .post(
          Uri.parse('${_normalizeBaseUrl(baseUrl)}/api/device/webrtc/offer'),
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{'sdp': sdp, 'type': type}),
        )
        .timeout(_requestTimeout);

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] != true) {
      final detail = decoded['detail'];
      final message =
          decoded['message'] as String? ??
          (detail is String ? detail : 'WebRTC signaling 失败，请检查设备运行时地址。');
      throw ApiException(message, statusCode: response.statusCode);
    }
    return decoded['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
  }

  String _normalizeBaseUrl(String rawBaseUrl) {
    var normalized = rawBaseUrl.trim();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.endsWith('/api')) {
      normalized = normalized.substring(0, normalized.length - 4);
    }
    return normalized;
  }
}
