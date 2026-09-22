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

  // Detection mode
  CameraController? _cameraController;
  HandLandmarkerPlugin? _landmarker;
  List<Hand> _hands = const [];
  Size _previewSize = const Size(640, 480);
  int _sensorOrientation = 90;
  bool _lensFront = true;
  bool _detectorStarting = false;

  // Gesture stability tracking
  String _currentGesture = "-";
  String _stableGesture = "-";
  int _stableFrames = 0;
  DateTime _lastBroadcastAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastBroadcastedGesture = "-";

  // ML Inference server
  String _infServerUrl = "http://10.24.159.58:5001";
  bool _serverAvailable = true;
  bool _pendingRequest = false;

  bool get _detecting => _socket.isDetectionEnabled;

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
    final granted = await _ensurePermissions();
    if (!granted) {
      _socket.setMediaStatus("permission_denied");
      return;
    }
    if (_detecting) {
      await _startDetectionPipeline();
    } else {
      await _socket.ensureLocalMedia();
      if (_socket.serverUrl.isNotEmpty && !_socket.isConnected) {
        await _socket.joinRoom();
      }
    }
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
    if (identical(stream, _attachedStream)) return;
    _attachedStream = stream;
    _renderer.srcObject = stream;
    if (mounted) setState(() {});
  }

  void _onServiceChanged() {
    _applyTrackStates();
    final detecting = _socket.isDetectionEnabled;
    if (detecting && _cameraController == null && !_detectorStarting) {
      _startDetectionPipeline();
    } else if (!detecting && _cameraController != null) {
      _stopDetectionPipeline();
    }
    if (!_detecting) _attachStream(_socket.localStream);
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
    if (_detectorStarting || _cameraController != null) return;
    _detectorStarting = true;
    try {
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
    } catch (e) {
      debugPrint("Detection pipeline error: $e");
      if (mounted) {
        setState(() => _currentGesture = "Detection unavailable");
      }
      await _stopDetectionPipeline(reacquireWebrtc: true);
    } finally {
      _detectorStarting = false;
    }
  }

  Future<void> _stopDetectionPipeline({bool reacquireWebrtc = true}) async {
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
  }

  Future<void> _processFrame(CameraImage image) async {
    final plugin = _landmarker;
    if (plugin == null) return;
    try {
      plugin.processFrame(image, _sensorOrientation);
    } catch (_) {}
  }

  void _classify(List<Hand> hands) {
    if (hands.isEmpty) return;

    // Build 126-dim feature vector from hand landmarks
    final featureVector = _buildFeatureVector(hands);

    // Try ML inference server first
    if (_serverAvailable && !_pendingRequest) {
      _pendingRequest = true;
      _callInferenceServer(featureVector).then((result) {
        _pendingRequest = false;
        if (result != null) {
          _processGestureResult(result.$1, result.$2);
        } else {
          // Server returned null — fall back to rule-based
          final fallback = _recognizeGesture(hands.first.landmarks);
          _processGestureResult(fallback.$1, fallback.$2);
        }
      }).catchError((_) {
        _pendingRequest = false;
        _serverAvailable = false;
        // Auto-retry after 10 seconds
        Future.delayed(const Duration(seconds: 10), () {
          _serverAvailable = true;
        });
        // Fallback to rule-based
        final fallback = _recognizeGesture(hands.first.landmarks);
        _processGestureResult(fallback.$1, fallback.$2);
      });
    } else {
      // Server unavailable — use rule-based classifier
      final result = _recognizeGesture(hands.first.landmarks);
      _processGestureResult(result.$1, result.$2);
    }
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

  Future<(String, double)?> _callInferenceServer(List<double> features) async {
    try {
      final response = await http.post(
        Uri.parse('$_infServerUrl/predict'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'landmarks': features}),
      ).timeout(const Duration(milliseconds: 2000));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final word = data['word'] as String;
        final confidence = (data['confidence'] as num).toDouble();
        if (confidence >= 0.60) {
          return (word, confidence);
        }
      }
    } catch (_) {}
    return null;
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
      final conf = (confidence * 100).round().clamp(70, 99);
      _socket.simulateGesture(gesture, conf);
      _lastBroadcastedGesture = gesture;
    }

    if (_currentGesture != gesture && mounted) {
      setState(() => _currentGesture = gesture);
    }
  }

  // ---------------- Starter geometric ISL-style classifier ----------------

  static const _fingerTipsPips = [
    [8, 6], // index
    [12, 10], // middle
    [16, 14], // ring
    [20, 18], // pinky
  ];

  double _dist(Landmark a, Landmark b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

  (String, double) _recognizeGesture(List<Landmark> lm) {
    if (lm.length < 21) return ("-", 0);

    final wrist = lm[0];
    final handSize = _dist(wrist, lm[9]);
    if (handSize < 0.04) return ("Hand too far", 0);

    bool fingerExtended(int tipIdx, int pipIdx) =>
        _dist(wrist, lm[tipIdx]) > _dist(wrist, lm[pipIdx]) * 1.12;

    final fingers = _fingerTipsPips.map((p) => fingerExtended(p[0], p[1])).toList();
    final extendedCount = fingers.where((f) => f).length;

    final thumbReach = _dist(lm[4], lm[5]) / handSize;
    final thumbExtended = thumbReach > 1.15;
    final thumbUp = thumbExtended && (wrist.y - lm[4].y) > handSize * 1.2;
    final thumbDown = thumbExtended && (lm[4].y - wrist.y) > handSize * 0.5;
    final pinchGap = _dist(lm[4], lm[8]) / handSize;

    String gesture;
    double confidence;

    // FOOD: Fingertips pinched together
    if (pinchGap < 0.45 && !fingers[1] && !fingers[2] && !fingers[3]) {
      gesture = "Food";
      confidence = 0.9;
    }
    // GOOD: Thumbs up (thumb extended upward, no other fingers)
    else if (thumbUp && extendedCount == 0) {
      gesture = "Good";
      confidence = 0.88;
    }
    // BAD: Thumbs down (thumb extended downward)
    else if (thumbDown && extendedCount == 0) {
      gesture = "Bad";
      confidence = 0.85;
    }
    // YES: Closed fist (no fingers extended)
    else if (extendedCount == 0 && !thumbExtended) {
      gesture = "Yes";
      confidence = 0.85;
    }
    // LOVE: ILY shape (index + pinky extended, thumb extended)
    else if (fingers[0] && !fingers[1] && !fingers[2] && fingers[3] && thumbExtended) {
      gesture = "Love";
      confidence = 0.88;
    }
    // WATER: W shape (index + middle + ring extended, pinky folded)
    else if (fingers[0] && fingers[1] && fingers[2] && !fingers[3]) {
      gesture = "Water";
      confidence = 0.87;
    }
    // TIME: Index finger pointing up only
    else if (fingers[0] && extendedCount == 1) {
      gesture = "Time";
      confidence = 0.86;
    }
    // NO: Index + middle extended (peace sign context = no)
    else if (fingers[0] && fingers[1] && !fingers[2] && !fingers[3] && !thumbExtended) {
      gesture = "No";
      confidence = 0.87;
    }
    // HELP / STOP / PLEASE: All 5 fingers extended (open hand)
    else if (extendedCount == 4 && thumbExtended) {
      gesture = "Help";
      confidence = 0.9;
    }
    // HELLO: 4 fingers extended without thumb spread (flat hand wave)
    else if (extendedCount == 4) {
      gesture = "Hello";
      confidence = 0.85;
    }
    else {
      gesture = "Detecting...";
      confidence = 0;
    }
    return (gesture, confidence);
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
    return Container(
      color: const Color(0xFF181310),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_detecting)
            _buildDetectionFeed()
          else
            _buildWebrtcFeed(),
          if (_detecting) _buildGestureBanner(),
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
