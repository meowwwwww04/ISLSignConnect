// Native (Android/iOS/desktop) implementation of RemoteWebcamView.
// Renders the WebRTC remote peer stream once the call connects.

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:google_fonts/google_fonts.dart';
import '../services/socket_service.dart';

class RemoteWebcamView extends StatefulWidget {
  const RemoteWebcamView({super.key});

  @override
  State<RemoteWebcamView> createState() => _RemoteWebcamViewState();
}

class _RemoteWebcamViewState extends State<RemoteWebcamView> {
  final SocketService _socket = SocketService();
  final rtc.RTCVideoRenderer _renderer = rtc.RTCVideoRenderer();
  bool _rendererReady = false;
  rtc.MediaStream? _attachedStream;
  String? _attachedVideoTrackId;

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
    _attachStream(_socket.remoteStream);
  }

  void _attachStream(rtc.MediaStream? stream) {
    if (!_rendererReady) return;
    // flutter_webrtc's native renderer only binds videoTracks[0] at
    // set-time. The video track usually arrives AFTER the audio track on
    // the same MediaStream, so re-set srcObject whenever the video track
    // appears/changes — otherwise remote video stays black forever.
    final videoTracks = stream?.getVideoTracks() ?? const <rtc.MediaStreamTrack>[];
    final videoTrackId = videoTracks.isNotEmpty ? videoTracks.first.id : null;
    if (identical(stream, _attachedStream) && videoTrackId == _attachedVideoTrackId) {
      return;
    }
    _attachedStream = stream;
    _attachedVideoTrackId = videoTrackId;
    _renderer.srcObject = stream;
    if (mounted) setState(() {});
  }

  void _onServiceChanged() {
    _attachStream(_socket.remoteStream);
  }

  @override
  void dispose() {
    _socket.removeListener(_onServiceChanged);
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Render only once a remote VIDEO track exists — an audio-only
          // stream would show a black rectangle instead of the waiting state.
          if (_rendererReady && _attachedStream != null && _attachedVideoTrackId != null)
            rtc.RTCVideoView(
              _renderer,
              objectFit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            _buildWaitingState(),
        ],
      ),
    );
  }

  Widget _buildWaitingState() {
    final connected = _socket.isConnected;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!connected)
              const Icon(Icons.cloud_off_outlined, size: 44, color: Colors.white24)
            else ...[
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(color: Color(0xFFFF5E1E), strokeWidth: 3),
              ),
              const SizedBox(height: 4),
            ],
            const SizedBox(height: 14),
            Text(
              !connected ? "Not Connected" : "Waiting for your peer to join...",
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              !connected
                  ? "Join a room from the Room screen to start a live call."
                  : "Share room code '${_socket.currentRoomId}' with your peer.\nVideo will appear here automatically.",
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: Colors.white54, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
