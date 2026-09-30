// Unified call-stage camera view with LIVE MediaPipe hand detection.
//
// Two modes controlled by SocketService.isDetectionEnabled:
//  • detection ON  → the camera plugin owns the device, frames stream to
//    MediaPipe continuously, the SignConnect skeleton is painted over the
//    live preview and recognized signs broadcast to the peer in real time.
//  • detection OFF → flutter_webrtc owns the camera for normal two-way video.
//
// This keeps ONE camera owner at a time (Android forbids double-opening),
// while making detection a native part of the video-call stage itself.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:google_fonts/google_fonts.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../services/socket_service.dart';

class HandDetectorView extends StatefulWidget {
  const HandDetectorView({super.key});

  @override
  State<HandDetectorView> createState() => _HandDetectorViewState();
}

class _HandDetectorViewState extends State<HandDetectorView> {
  final SocketService _socket = SocketService();

  // WebRTC mode
  final rtc.RTCVideoRenderer _renderer = rtc.RTCVideoRenderer();
  bool _rendererReady = false;
  rtc.MediaStream? _attachedStream;
  String? _attachedVideoTrackId;

  // Detection mode
  CameraController? _cameraController;
  HandLandmarkerPlugin? _landmarker;
  List<Hand> _hands = const [];
  Size _previewSize = const Size(640, 480);
  int _sensorOrientation = 90;
  bool _lensFront = true;
  bool _detectorStarting = false;
  bool _stoppingPipeline = false;
  bool _pausedForPeer = false;

  // Gesture stability tracking
  String _currentGesture = "-";
  String _stableGesture = "-";
  int _stableFrames = 0;
  DateTime _lastBroadcastAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastBroadcastedGesture = "-";

  // ML inference server state (server itself lives on the PC; see Settings).
  bool _serverAvailable = true;
  bool _pendingRequest = false;

  bool get _detecting => _socket.isDetectionEnabled;

  @override
  void initState() {
    super.initState();
    _serverAvailable = _socket.infServerStatus != "offline";
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
    final granted = await _ensurePermissions();
    if (!granted) {
      _socket.setMediaStatus("permission_denied");
      return;
    }
    // Locate the ML inference server before the first frame is classified.
    _socket.resolveInfServer();
    // Detection takes the camera exclusively — never while a video peer is
    // in the room, otherwise the peer receives no video at all.
    if (_detecting && !_socket.peerPresent) {
      await _startDetectionPipeline();
    } else {
      await _socket.ensureLocalMedia();
      if (_socket.serverUrl.isNotEmpty && !_socket.isConnected) {
        await _socket.joinRoom();
      }
    }
    _attachStream(_socket.localStream);
  }

  Future<bool> _ensurePermissions() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  void _attachStream(rtc.MediaStream? stream) {
    if (!_rendererReady) return;
    // Re-set srcObject whenever the video track appears/changes: the native
    // renderer only binds videoTracks[0] at set-time and detection release /
    // reacquire swaps tracks while the stream object stays the same.
    final videoTracks = stream?.getVideoTracks() ?? const <rtc.MediaStreamTrack>[];
    final videoTrackId = videoTracks.isNotEmpty ? videoTracks.first.id : null;
    if (identical(stream, _attachedStream) && videoTrackId == _attachedVideoTrackId) {
      return;
    }
    _attachedStream = stream;
    _attachedVideoTrackId = videoTrackId;
    _renderer.srcObject = stream;
    if (mounted) setState(() {});
    // The video track often lands a beat AFTER the stream object itself
    // (the detection pipeline hands the camera back). Re-check once so a
    // late track cannot leave the self-view black.
    if (stream != null && videoTrackId == null) {
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        if (_attachedVideoTrackId == null && _attachedStream != null) {
          _attachStream(_socket.localStream);
        }
      });
    }
  }

  void _onServiceChanged() {
    _applyTrackStates();
    final detecting = _socket.isDetectionEnabled;
    final peerHere = _socket.peerPresent;
    final pipelineActive = _cameraController != null || _detectorStarting;

    if (detecting && !peerHere && !pipelineActive && !_stoppingPipeline) {
      _startDetectionPipeline();
    } else if (pipelineActive && (peerHere || !detecting)) {
      // Peer joined (camera must stream video) or detection switched off.
      // _stopDetectionPipeline reacquires the camera for WebRTC and reattaches
      // the local renderer once it has a live video track.
      _stopDetectionPipeline();
    }

    if (peerHere && (pipelineActive || _stoppingPipeline) && !_pausedForPeer) {
      _pausedForPeer = true;
      _socket.addTranscript(
        "System",
        "Video peer in room — camera switched to the live call. ISL detection is paused and resumes after the call.",
        "system",
      );
    } else if (!peerHere && _pausedForPeer) {
      _pausedForPeer = false;
      if (detecting) {
        _socket.addTranscript(
          "System",
          "Peer left — ISL sign detection resuming.",
          "system",
        );
      }
    }

    // The local renderer must re-bind whenever the stream gains its video
    // track back (the detection pipeline hands the camera to WebRTC and the
    // same MediaStream object is reused). Without this the self-view stays
    // black even though the peer receives video.
    _attachStream(_socket.localStream);

    if (mounted) setState(() {});
  }

  void _applyTrackStates() {
    final stream = _attachedStream;
    if (stream == null) return;
    for (final track in stream.getVideoTracks()) {
      track.enabled = _socket.isCameraEnabled;
    }
    for (final track in stream.getAudioTracks()) {
      track.enabled = _socket.isMicEnabled;
    }
  }

  // ---------------- Detection pipeline ----------------

  Future<void> _startDetectionPipeline() async {
    if (_detectorStarting || _cameraController != null || _stoppingPipeline) return;
    _detectorStarting = true;
    try {
      if (_socket.peerPresent) return; // camera must stay with WebRTC
      await _socket.releaseCameraForDetection();
      await Future.delayed(const Duration(milliseconds: 400));

      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception("No camera found");
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _lensFront = camera.lensDirection == CameraLensDirection.front;

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      await controller.startImageStream(_processFrame);

      _landmarker ??= HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.6,
        delegate: HandLandmarkerDelegate.gpu,
      );
      _landmarker!.landmarkStream.listen((hands) {
        if (!mounted || !_socket.isDetectionEnabled) return;
        setState(() => _hands = hands);
        _classify(hands);
      });

      if (!mounted) return;
      setState(() {
        _cameraController = controller;
        final ps = controller.value.previewSize;
        if (ps != null) _previewSize = Size(ps.width, ps.height);
        _sensorOrientation = camera.sensorOrientation;
        _hands = const [];
      });
      // A peer may have joined while we were starting: hand the camera
      // straight back to WebRTC so the call shows live video.
      if (_socket.peerPresent) {
        await _stopDetectionPipeline();
      }
    } catch (e) {
      debugPrint("Detection pipeline error: $e");
      if (mounted) {
        setState(() => _currentGesture = "Detection unavailable");
      }
      await _stopDetectionPipeline();
    } finally {
      _detectorStarting = false;
    }
  }

  Future<void> _stopDetectionPipeline({bool reacquireWebrtc = true}) async {
    if (_stoppingPipeline) return;
    _stoppingPipeline = true;
    try {
      try {
        await _cameraController?.stopImageStream();
        await _cameraController?.dispose();
      } catch (_) {}
      _cameraController = null;
      if (!reacquireWebrtc && mounted) setState(() {});
      if (mounted) setState(() => _hands = const []);
      if (reacquireWebrtc) {
        await Future.delayed(const Duration(milliseconds: 500));
        await _socket.reacquireCameraAfterDetection();
        _attachStream(_socket.localStream);
      }
    } finally {
      _stoppingPipeline = false;
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    final plugin = _landmarker;
    if (plugin == null) return;
    try {
      plugin.processFrame(image, _sensorOrientation);
    } catch (_) {}
  }

  // ---------------- ML inference ----------------

  /// Lowest probability at which a sign is accepted.
  static const double _minConfidence = 0.45;

  /// Below [_confidentLevel] the top guess must also beat the runner-up by
  /// this margin, otherwise the sign is reported as uncertain instead of
  /// guessing (this is what used to spam "Hello" for every open hand).
  static const double _minMargin = 0.08;
  static const double _confidentLevel = 0.60;

  void _classify(List<Hand> hands) {
    if (hands.isEmpty || _pendingRequest || !_serverAvailable) return;

    _pendingRequest = true;
    _callInferenceServer(_buildFeatureVector(hands)).then((result) {
      _pendingRequest = false;
      _socket.markInfServerOnline(_socket.infServerUrl);
      if (result != null) {
        _processGestureResult(result.$1, result.$2);
      } else {
        _setUncertain();
      }
    }).catchError((_) {
      _pendingRequest = false;
      _handleServerOffline();
    });
  }

  void _setUncertain() {
    const msg = "Hold sign steady…";
    if (_currentGesture == msg || !mounted) return;
    setState(() => _currentGesture = msg);
  }

  void _handleServerOffline() {
    if (!_serverAvailable) return;
    _serverAvailable = false;
    _socket.markInfServerOffline();
    if (mounted) {
      setState(() => _currentGesture = "ML server offline");
    }
    _socket.addTranscript(
      "System",
      "Sign recognition server unreachable — set its URL in Settings "
      "(e.g. http://192.168.1.10:5001). Retrying automatically.",
      "system",
    );
    _retryServerLater();
  }

  void _retryServerLater() {
    Future.delayed(const Duration(seconds: 10), () async {
      if (!mounted || _serverAvailable) return;
      final ok = await _socket.resolveInfServer();
      if (!mounted) return;
      if (ok) {
        _serverAvailable = true;
        setState(() => _currentGesture = "-");
      } else {
        _retryServerLater();
      }
    });
  }

  Future<(String, double)?> _callInferenceServer(List<double> features) async {
    final base = _socket.infServerUrl.replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) throw StateError("inference server not configured");

    final response = await http.post(
      Uri.parse('$base/predict'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'landmarks': features}),
    ).timeout(const Duration(milliseconds: 2500));

    if (response.statusCode != 200) {
      throw http.ClientException('inference server returned ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final word = data['word']?.toString().trim() ?? '';
    final confidence = (data['confidence'] as num?)?.toDouble() ?? 0;
    if (word.isEmpty || confidence < _minConfidence) return null;

    double second = 0;
    final top5 = data['top5'];
    if (top5 is List && top5.length > 1) {
      final runnerUp = top5[1];
      if (runnerUp is Map) {
        second = (runnerUp['confidence'] as num?)?.toDouble() ?? 0;
      }
    }
    if (confidence < _confidentLevel && (confidence - second) < _minMargin) {
      return null;
    }
    return (word, confidence);
  }

  List<double> _buildFeatureVector(List<Hand> hands) {
    final flat = <double>[];
    for (int h = 0; h < 2; h++) {
      if (h < hands.length) {
        for (final pt in hands[h].landmarks) {
          flat.add(pt.x);
          flat.add(pt.y);
          flat.add(pt.z);
        }
      } else {
        flat.addAll(List<double>.filled(63, 0.0));
      }
    }
    return flat;
  }

  void _processGestureResult(String gesture, double confidence) {
    final now = DateTime.now();
    if (gesture == _stableGesture && confidence > 0) {
      _stableFrames++;
    } else {
      _stableGesture = gesture;
      _stableFrames = 1;
    }

    final heldLongEnough = _stableFrames >= 8;
    final cooldownOver = now.difference(_lastBroadcastAt).inMilliseconds > 1500;

    if (heldLongEnough &&
        cooldownOver &&
        confidence > 0 &&
        gesture != _lastBroadcastedGesture) {
      _lastBroadcastAt = now;
      final conf = (confidence * 100).round().clamp(1, 99);
      _socket.simulateGesture(gesture, conf);
      _lastBroadcastedGesture = gesture;
    }

    if (_currentGesture != gesture && mounted) {
      setState(() => _currentGesture = gesture);
    }
  }

  @override
  void dispose() {
    _socket.removeListener(_onServiceChanged);
    if (_cameraController != null) {
      try {
        _cameraController?.stopImageStream();
        _cameraController?.dispose();
      } catch (_) {}
      _cameraController = null;
      // Camera returns to WebRTC after this widget leaves the tree.
      Future.delayed(const Duration(milliseconds: 500), () {
        SocketService().reacquireCameraAfterDetection();
      });
    }
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Detection preview only while the pipeline actually owns the camera;
    // while a video peer is present the WebRTC feed must be shown instead.
    final showDetection = _detecting && !_socket.peerPresent;
    return Container(
      color: const Color(0xFF181310),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showDetection)
            _buildDetectionFeed()
          else
            _buildWebrtcFeed(),
          if (showDetection) _buildGestureBanner(),
        ],
      ),
    );
  }

  Widget _buildWebrtcFeed() {
    if (_rendererReady &&
        _attachedStream != null &&
        _attachedStream!.getVideoTracks().isNotEmpty) {
      return rtc.RTCVideoView(
        _renderer,
        mirror: true,
        objectFit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    return _buildWebrtcPlaceholder();
  }

  Widget _buildWebrtcPlaceholder() {
    switch (_socket.mediaStatus) {
      case "permission_denied":
        return _buildMessage(
          icon: Icons.no_photography_outlined,
          title: "Camera & Microphone Blocked",
          subtitle:
              "SignConnect needs camera access for sign recognition and mic access so you can hear your peer.",
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
              Text("Starting camera...",
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        );
      case "error":
        return _buildMessage(
          icon: Icons.error_outline,
          title: "Camera Unavailable",
          subtitle:
              "The camera could not be started. Close other apps using it and try again.",
          actionLabel: "Retry",
          action: () async {
            await _socket.ensureLocalMedia();
            _attachStream(_socket.localStream);
          },
        );
      case "ready":
        // Media is granted but the video track is being swapped back from
        // the detection pipeline — show a short transitional spinner.
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFFF5E1E)),
              SizedBox(height: 12),
              Text("Starting live video…",
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        );
      default:
        return _buildMessage(
          icon: Icons.videocam_outlined,
          title: "Camera Off",
          subtitle:
              "Tap below to allow camera & microphone and start the live ISL session.",
          actionLabel: "Enable Camera & Mic",
          action: () async {
            if (await _ensurePermissions()) {
              await _socket.ensureLocalMedia();
              _attachStream(_socket.localStream);
              if (_socket.serverUrl.isNotEmpty && !_socket.isConnected) {
                await _socket.joinRoom();
              }
            } else {
              _socket.setMediaStatus("permission_denied");
            }
          },
        );
    }
  }

  Widget _buildDetectionFeed() {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFFFF5E1E)),
            const SizedBox(height: 12),
            Text(
              "Starting live sign detection...",
              style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: _previewSize.height,
            height: _previewSize.width,
            child: CameraPreview(controller),
          ),
        ),
        CustomPaint(
          size: Size.infinite,
          painter: _SkeletonPainter(
            hands: _hands,
            previewSize: _previewSize,
            lensFront: _lensFront,
            sensorOrientation: _sensorOrientation,
          ),
        ),
        Positioned(
          top: 10,
          left: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _hands.isNotEmpty
                        ? DetectorColors.skeletonLine
                        : Colors.white24,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _hands.isEmpty
                      ? "SEARCHING FOR HANDS"
                      : "${_hands.length} HAND${_hands.length > 1 ? 'S' : ''} TRACKED",
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGestureBanner() {
    final connected = _socket.isConnected;
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DetectorColors.skeletonLine, width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "LIVE ISL DETECTION"
                  "${connected ? "  •  RELAYED TO PEER" : "  •  NOT CONNECTED"}",
              style: GoogleFonts.jetBrainsMono(
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
                color: DetectorColors.skeletonLine,
              ),
            ),
            Text(
              _currentGesture,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
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
              style: GoogleFonts.outfit(
                  fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: Colors.white60, height: 1.4),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => action(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5E1E),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: Text(actionLabel,
                  style:
                      GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

/// SignConnect brand colors for the detection overlay.
class DetectorColors {
  static const skeletonLine = Color(0xFF00FFCC);
  static const landmarkDot = Color(0xFFFF3366);
}

/// Draws the MediaPipe hand skeleton in SignConnect colors.
class _SkeletonPainter extends CustomPainter {
  _SkeletonPainter({
    required this.hands,
    required this.previewSize,
    required this.lensFront,
    required this.sensorOrientation,
  });

  final List<Hand> hands;
  final Size previewSize;
  final bool lensFront;
  final int sensorOrientation;

  static const List<List<int>> _connections = [
    [0, 1], [1, 2], [2, 3], [3, 4], // thumb
    [0, 5], [5, 6], [6, 7], [7, 8], // index
    [5, 9], [9, 10], [10, 11], [11, 12], // middle
    [9, 13], [13, 14], [14, 15], [15, 16], // ring
    [13, 17], [17, 18], [18, 19], [19, 20], // pinky
    [0, 17], // palm base
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (hands.isEmpty || previewSize == Size.zero) return;

    final scale = size.width / previewSize.height;
    final linePaint = Paint()
      ..color = DetectorColors.skeletonLine
      ..strokeWidth = 3 / scale
      ..strokeCap = StrokeCap.round;
    final dotPaint = Paint()..color = DetectorColors.landmarkDot;

    canvas.save();
    final center = Offset(size.width / 2, size.height / 2);
    canvas.translate(center.dx, center.dy);
    canvas.rotate(sensorOrientation * math.pi / 180);
    if (lensFront) {
      canvas.scale(-1, 1);
      canvas.rotate(math.pi);
    }
    canvas.scale(scale);

    final logicalWidth = previewSize.width;
    final logicalHeight = previewSize.height;

    for (final hand in hands) {
      if (hand.landmarks.length < 21) continue;
      Offset pt(Landmark l) =>
          Offset((l.x - 0.5) * logicalWidth, (l.y - 0.5) * logicalHeight);
      for (final c in _connections) {
        canvas.drawLine(pt(hand.landmarks[c[0]]), pt(hand.landmarks[c[1]]), linePaint);
      }
      for (final l in hand.landmarks) {
        canvas.drawCircle(pt(l), 4.5 / scale, dotPaint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SkeletonPainter oldDelegate) =>
      oldDelegate.hands != hands || oldDelegate.previewSize != previewSize;
}
