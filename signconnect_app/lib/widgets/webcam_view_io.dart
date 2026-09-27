// Native (Android/iOS/desktop) implementation of WebcamView.
// Requests camera & microphone permissions, opens the real camera via
// flutter_webrtc, and mirrors the feed. MediaPipe skeleton runs on web.

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/socket_service.dart';

class WebcamView extends StatefulWidget {
  const WebcamView({super.key});

  @override
  State<WebcamView> createState() => _WebcamViewState();
}

class _WebcamViewState extends State<WebcamView> {
  final SocketService _socket = SocketService();
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  bool _rendererReady = false;
  MediaStream? _attachedStream;
  String? _attachedVideoTrackId;

  @override
  void initState() {
    super.initState();
    _initRenderer();
    _socket.addListener(_onServiceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _initRenderer() async {
    await _renderer.initialize();
    if (!mounted) return;
    setState(() => _rendererReady = true);
    _attachStream(_socket.localStream);
  }

  Future<void> _bootstrap() async {
    // Auto-attempt on first show; falls back to a tap-to-start overlay when denied.
    final status = await [Permission.camera, Permission.microphone].request();
    final allGranted = status.values.every((s) => s.isGranted);
    if (!mounted) return;
    if (allGranted) {
      await _socket.ensureLocalMedia();
      if (_socket.serverUrl.isNotEmpty) {
        await _socket.joinRoom();
      }
    } else {
      _socket.setMediaStatus("permission_denied");
    }
  }

  void _attachStream(MediaStream? stream) {
    if (!_rendererReady) return;
    // Native renderer binds videoTracks[0] only at set-time — re-set
    // srcObject when the video track appears/changes on the same stream.
    final videoTracks = stream?.getVideoTracks() ?? const <MediaStreamTrack>[];
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
    _attachStream(_socket.localStream);
    _applyEnabledState();
  }

  void _applyEnabledState() {
    final stream = _attachedStream;
    if (stream == null) return;
    for (final track in stream.getVideoTracks()) {
      track.enabled = _socket.isCameraEnabled;
    }
    for (final track in stream.getAudioTracks()) {
      track.enabled = _socket.isMicEnabled;
    }
  }

  Future<void> _requestAndStart() async {
    final status = await [Permission.camera, Permission.microphone].request();
    if (status.values.every((s) => s.isGranted)) {
      await _socket.ensureLocalMedia();
      if (_socket.serverUrl.isNotEmpty && !_socket.isConnected) {
        await _socket.joinRoom();
      }
    } else if (status.values.any((s) => s.isPermanentlyDenied)) {
      _socket.setMediaStatus("permission_denied");
    }
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
      color: const Color(0xFF181310),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_rendererReady && _attachedStream != null)
            RTCVideoView(
              _renderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            _buildPlaceholder(),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    switch (_socket.mediaStatus) {
      case "permission_denied":
        return _buildMessage(
          icon: Icons.no_photography_outlined,
          title: "Camera & Microphone Blocked",
          subtitle: "SignConnect needs camera access for sign recognition and mic access so you can hear your peer.",
          actionLabel: "Open Settings",
          action: openAppSettings,
        );
      case "initializing":
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFFF5E1E)),
              SizedBox(height: 12),
              Text("Starting camera...", style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        );
      case "error":
        return _buildMessage(
          icon: Icons.error_outline,
          title: "Camera Unavailable",
          subtitle: "The camera could not be started. Close other apps using it and try again.",
          actionLabel: "Retry",
          action: () async {
            await _socket.ensureLocalMedia();
          },
        );
      default:
        return _buildMessage(
          icon: Icons.videocam_outlined,
          title: "Camera Off",
          subtitle: "Tap below to allow camera & microphone and start the live ISL session.",
          actionLabel: "🎥 Enable Camera & Mic",
          action: _requestAndStart,
        );
    }
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required Future<void> Function() action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.white24),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white60, height: 1.4),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => action(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5E1E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: Text(actionLabel, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
