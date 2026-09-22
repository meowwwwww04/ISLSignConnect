import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import '../services/socket_service.dart';

class HandDetectorView extends StatefulWidget {
  const HandDetectorView({super.key});

  @override
  State<HandDetectorView> createState() => _HandDetectorViewState();
}

class _HandDetectorViewState extends State<HandDetectorView> {
  final SocketService _socket = SocketService();
  final rtc.RTCVideoRenderer _renderer = rtc.RTCVideoRenderer();
  bool _rendererReady = false;
  rtc.MediaStream? _attachedStream;

  @override
  void initState() {
    super.initState();
    _initRenderer();
    _socket.addListener(_onServiceChanged);
  }

  Future<void> _initRenderer() async {
    await _renderer.initialize();
    if (!mounted) return;
    setState(() => _rendererReady = true);
    _attachStream(_socket.localStream);
  }

  void _attachStream(rtc.MediaStream? stream) {
    if (!_rendererReady) return;
    if (identical(stream, _attachedStream)) return;
    _attachedStream = stream;
    _renderer.srcObject = stream;
    if (mounted) setState(() {});
  }

  void _onServiceChanged() {
    _attachStream(_socket.localStream);
  }

  @override
  void dispose() {
    _socket.removeListener(_onServiceChanged);
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_rendererReady &&
        _attachedStream != null &&
        _attachedStream!.getVideoTracks().isNotEmpty) {
      return rtc.RTCVideoView(
        _renderer,
        mirror: true,
        objectFit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    return Container(
      color: const Color(0xFF181310),
      child: const Center(
        child: Text(
          "Camera connecting...",
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ),
    );
  }
}
