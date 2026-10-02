import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'signconnect_js_bridge.dart';
import 'dart:io' show HttpClient;

enum AppRole { deaf, hearing }

class SocketService extends ChangeNotifier {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;

  SocketService._internal() {
    if (!kIsWeb) {
      _initNativeStt();
    }
    _loadInfServerConfig();
  }

  AppRole _currentRole = AppRole.deaf;
  String _currentRoomId = "signconnect-room";
  String _serverUrl = "";
  bool _isCameraEnabled = true;
  bool _isMicEnabled = true;
  bool _isSkeletonEnabled = true;
  bool _isTTSEnabled = true;
  bool _isDetectionEnabled = true; // live MediaPipe sign detection on the call stage
  bool _isRemoteUserConnected = false;
  bool _peerPresent = false; // signaling-level: another user is in the room
  bool _isSwappedFeeds = false;
  double _micSensitivity = 0.75;
  String _vocabularyFocus = "Daily";

  String _userName = "Alex Sharma";
  String _userEmail = "alex@signconnect.org";
  bool _isAuthenticated = false;

  // ---- ML inference server (sign recognition) -------------------------------
  // The classifier lives on the PC running inference_server.py. The phone has
  // to reach it over the LAN, so the URL is configurable in Settings, persisted
  // across restarts, and auto-probed against a couple of sensible candidates.
  static const String _kInfServerPref = 'signconnect_inf_url';
  String _savedInfServerUrl = "";
  String _infServerUrl = "";
  String _infServerStatus = "checking"; // checking | online | offline

  String get infServerUrl => _infServerUrl;
  String get savedInfServerUrl => _savedInfServerUrl;
  String get infServerStatus => _infServerStatus;

  /// Persists the user-configured inference URL and verifies it answers.
  Future<void> setInfServerUrl(String url) async {
    _savedInfServerUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kInfServerPref, _savedInfServerUrl);
    await resolveInfServer(verbose: true);
  }

  Future<void> _loadInfServerConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _savedInfServerUrl = prefs.getString(_kInfServerPref) ?? "";
    } catch (_) {}
    if (_savedInfServerUrl.isNotEmpty && _infServerUrl.isEmpty) {
      _infServerUrl = _savedInfServerUrl;
      notifyListeners();
    }
  }

  List<String> _infServerCandidates() {
    final candidates = <String>[];
    if (_savedInfServerUrl.isNotEmpty) candidates.add(_savedInfServerUrl);
    final host = Uri.tryParse(_serverUrl)?.host;
    if (host != null && host.isNotEmpty) candidates.add('http://$host:5001');
    if (!candidates.contains('http://127.0.0.1:5001')) {
      candidates.add('http://127.0.0.1:5001');
    }
    return candidates;
  }

  /// Probes /health on every candidate URL and keeps the first one that
  /// answers. Returns true when sign recognition is usable.
  Future<bool> resolveInfServer({bool verbose = false}) async {
    _infServerStatus = "checking";
    notifyListeners();

    for (final url in _infServerCandidates()) {
      try {
        final uri = Uri.parse("${url.replaceAll(RegExp(r'/+$'), '')}/health");
        final response =
            await http.get(uri).timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          _infServerUrl = uri.toString().replaceAll('/health', '');
          _infServerStatus = "online";
          if (verbose) {
            addTranscript("System", "ML sign recognition online ($_infServerUrl)",
                "system");
          }
          notifyListeners();
          return true;
        }
      } catch (_) {}
    }

    _infServerStatus = "offline";
    if (verbose) {
      addTranscript(
        "System",
        "ML inference server unreachable. Open Settings and set its URL to "
        "your computer's LAN address, e.g. http://192.168.1.10:5001",
        "system",
      );
    }
    notifyListeners();
    return false;
  }

  /// Called by the detector when a prediction request fails mid-call.
  void markInfServerOffline() {
    if (_infServerStatus == "offline") return;
    _infServerStatus = "offline";
    notifyListeners();
  }

  /// Called by the detector when a prediction request succeeds.
  void markInfServerOnline(String url) {
    final changed = _infServerStatus != "online" || _infServerUrl != url;
    _infServerStatus = "online";
    if (_infServerUrl.isEmpty) _infServerUrl = url;
    if (changed) notifyListeners();
  }

  bool _isConnected = false;
  final List<Map<String, String>> _transcripts = [
    {
      "sender": "SignConnect System",
      "text": "Welcome to SignConnect! Real-time two-way ISL translation session active.",
      "time": "Now",
      "type": "system"
    }
  ];

  String _lastRecognizedGesture = "-";
  String _latestPeerSpeechText = "Waiting for your peer to speak...";
  int _gestureConfidence = 0;
  int _jointPoints = 21;
  double _fps = 0;
  int _latencyMs = 0;

  String _mediaStatus = "idle"; // idle | initializing | ready | permission_denied | error

  // ---- Real WebRTC / Signaling state (native platforms) ----
  sio.Socket? _socket;
  rtc.RTCPeerConnection? _peerConnection;
  rtc.MediaStream? _localStream;
  rtc.MediaStream? _remoteStream;
  bool _makingOffer = false;
  Timer? _fallbackOfferTimer;
  bool _hasSentFallbackOffer = false;
  bool _joiningRoom = false;
  String? _activeRoomId;
  int _iceRestartAttempts = 0;
  List<Map<String, dynamic>>? _cachedIceServers;

  // ---- Native speech recognition ----
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _sttAvailable = false;
  bool _sttShouldListen = false;

  // Getters
  AppRole get currentRole => _currentRole;
  AppRole get remoteRole => _currentRole == AppRole.deaf ? AppRole.hearing : AppRole.deaf;
  String get currentRoomId => _currentRoomId;
  String get serverUrl => _serverUrl;
  bool get isCameraEnabled => _isCameraEnabled;
  bool get isMicEnabled => _isMicEnabled;
  bool get isSkeletonEnabled => _isSkeletonEnabled;
  bool get isTTSEnabled => _isTTSEnabled;
  bool get isDetectionEnabled => _isDetectionEnabled && _isCameraEnabled;
  bool get isRemoteUserConnected => _isRemoteUserConnected;

  /// True while another user occupies the room (presence or media level).
  /// While true, the camera must stay with WebRTC so the peer sees video.
  bool get peerPresent => _peerPresent || _isRemoteUserConnected;
  bool get isSwappedFeeds => _isSwappedFeeds;
  double get micSensitivity => _micSensitivity;
  String get vocabularyFocus => _vocabularyFocus;
  String get userName => _userName;
  String get userEmail => _userEmail;
  bool get isAuthenticated => _isAuthenticated;
  bool get isConnected => _isConnected;
  List<Map<String, String>> get transcripts => _transcripts;
  String get lastRecognizedGesture => _lastRecognizedGesture;
  String get latestPeerSpeechText => _latestPeerSpeechText;
  int get gestureConfidence => _gestureConfidence;
  int get jointPoints => _jointPoints;
  double get fps => _fps;
  int get latencyMs => _latencyMs;
  String get mediaStatus => _mediaStatus;
  rtc.MediaStream? get localStream => _localStream;
  rtc.MediaStream? get remoteStream => _remoteStream;

  void updateUserProfile({
    required String name,
    required String email,
    required AppRole role,
    String? vocabularyFocus,
    double? micSensitivity,
  }) {
    _userName = name.trim().isEmpty ? "User Account" : name.trim();
    _userEmail = email.trim().isEmpty ? "user@signconnect.org" : email.trim();
    _currentRole = role;
    if (vocabularyFocus != null) _vocabularyFocus = vocabularyFocus;
    if (micSensitivity != null) _micSensitivity = micSensitivity;
    _isAuthenticated = true;
    addTranscript("System", "Updated profile for $_userName ($_userEmail)", "system");
    notifyListeners();
  }

  void setServerUrl(String url) {
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty || trimmed == _serverUrl) return;
    _serverUrl = trimmed;
    notifyListeners();
  }

  /// Legacy entry point kept for compatibility. On native platforms this
  /// performs the full connect -> join -> negotiate sequence when a server
  /// URL has been configured.
  void initWebRTC() {
    if (kIsWeb) {
      if (_currentRole == AppRole.hearing && _isMicEnabled) {
        _startSpeechRecognition();
      }
      try {
        if (SignConnectJsBridge.hasProperty('initSignConnectRTC')) {
          SignConnectJsBridge.callMethod('initSignConnectRTC', [
            _currentRoomId,
            _currentRole == AppRole.deaf ? 'deaf' : 'hearing',
            (isConnected, peerRoleStr) {
              _isRemoteUserConnected = isConnected == true;
              notifyListeners();
            },
            (gestureWord, confidence) {
              _lastRecognizedGesture = gestureWord.toString();
              _gestureConfidence = (confidence as num).toInt();
              addTranscript("Peer (ISL Sign)", gestureWord.toString(), "deaf");
              notifyListeners();
            },
            (speechText) {
              _latestPeerSpeechText = speechText.toString();
              addTranscript("Peer (Speech)", speechText.toString(), "hearing");
              notifyListeners();
            }
          ]);
        }
      } catch (e) {
        debugPrint("RTC JS Interop error: $e");
      }
      return;
    }
    if (_serverUrl.isNotEmpty) {
      joinRoom();
    }
  }

  void setRole(AppRole role) {
    _currentRole = role;
    initWebRTC();
    notifyListeners();
  }

  void switchRole([AppRole? role]) {
    if (role != null) {
      _currentRole = role;
    } else {
      _currentRole = _currentRole == AppRole.deaf ? AppRole.hearing : AppRole.deaf;
    }
    addTranscript("System", "Switched primary role to ${_currentRole == AppRole.deaf ? 'Deaf Mode' : 'Hearing Mode'}", "system");
    if (!kIsWeb) {
      _syncRoleOnServer();
      // Deaf users sign (detection on); hearing users speak (normal video).
      if (_isDetectionEnabled != (_currentRole == AppRole.deaf)) {
        toggleDetection(_currentRole == AppRole.deaf);
      }
      _restartSttIfNeeded();
    }
    initWebRTC();
    notifyListeners();
  }

  void setRoomId(String roomId) {
    _currentRoomId = roomId;
    _isConnected = true;
    addTranscript("System", "Joined room '$_currentRoomId' as ${_currentRole == AppRole.deaf ? 'Deaf User' : 'Hearing User'}", "system");
    initWebRTC();
    notifyListeners();
  }

  void toggleCamera([bool? value]) {
    _isCameraEnabled = value ?? !_isCameraEnabled;
    _applyTrackStates();
    notifyListeners();
  }

  void toggleMic([bool? value]) {
    _isMicEnabled = value ?? !_isMicEnabled;
    _applyTrackStates();
    if (_isMicEnabled) {
      _startSpeechRecognition();
    } else {
      _stopSpeechRecognition();
    }
    notifyListeners();
  }

  void _startSpeechRecognition() {
    if (kIsWeb) {
      try {
        if (SignConnectJsBridge.hasProperty('startSignConnectSpeechRecognition')) {
          SignConnectJsBridge.callMethod('startSignConnectSpeechRecognition', [
            (speechText) {
              broadcastSpeech(speechText.toString());
            }
          ]);
        }
      } catch (e) {
        debugPrint("Speech recognition start notice: $e");
      }
    } else {
      _restartSttIfNeeded(forceStart: true);
    }
  }

  void toggleSkeleton() {
    _isSkeletonEnabled = !_isSkeletonEnabled;
    notifyListeners();
  }

  /// Toggles LIVE MediaPipe sign detection on the call stage.
  /// ON: the camera plugin takes over and frames stream to MediaPipe.
  /// OFF: flutter_webrtc resumes normal two-way video.
  Future<void> toggleDetection([bool? value]) async {
    final target = value ?? !_isDetectionEnabled;
    if (target == _isDetectionEnabled) return;
    _isDetectionEnabled = target;
    addTranscript(
      "System",
      target
          ? (peerPresent
              ? "ISL sign detection requested — it will use the camera after your video peer leaves the room."
              : "Live ISL sign detection enabled — signs broadcast to your peer while you sign.")
          : "Sign detection off — live camera streaming to your peer.",
      "system",
    );
    notifyListeners();
  }

  void toggleTTS() {
    _isTTSEnabled = !_isTTSEnabled;
    notifyListeners();
  }

  void toggleRemoteUser() {
    _isRemoteUserConnected = !_isRemoteUserConnected;
    addTranscript("System", _isRemoteUserConnected ? "Peer reconnected to room" : "Peer disconnected from room", "system");
    notifyListeners();
  }

  void toggleSwapFeeds() {
    _isSwappedFeeds = !_isSwappedFeeds;
    notifyListeners();
  }

  void setMicSensitivity(double value) {
    _micSensitivity = value;
    notifyListeners();
  }

  void setVocabularyFocus(String focus) {
    _vocabularyFocus = focus;
    notifyListeners();
  }

  void leaveCall() {
    if (kIsWeb) {
      try {
        if (SignConnectJsBridge.hasProperty('leaveSignConnectCall')) {
          SignConnectJsBridge.callMethod('leaveSignConnectCall');
        }
      } catch (e) {
        debugPrint("Leave call error: $e");
      }
    }
    if (!kIsWeb) {
      _stopSpeechRecognition();
      _teardownPeerConnection();
      _socket?.dispose();
      _socket = null;
      _localStream?.getTracks().forEach((t) => t.stop());
      _localStream?.dispose();
      _localStream = null;
      _remoteStream = null;
      _mediaStatus = "idle";
    }
    _isCameraEnabled = true;
    _isMicEnabled = true;
    _isRemoteUserConnected = false;
    _peerPresent = false;
    _isConnected = false;
    _transcripts.clear();
    addTranscript("System", "Left room '$_currentRoomId'. Call session ended.", "system");
    notifyListeners();
  }

  void clearTranscripts() {
    _transcripts.clear();
    addTranscript("System", "Cleared transcript history.", "system");
    notifyListeners();
  }

  void addTranscript(String sender, String text, String type) {
    _transcripts.insert(0, {
      "sender": sender,
      "text": text,
      "time": "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}",
      "type": type,
    });
    notifyListeners();
  }

  void updateMetrics({double? fps, int? latencyMs, int? jointPoints}) {
    if (fps != null) _fps = fps;
    if (latencyMs != null) _latencyMs = latencyMs;
    if (jointPoints != null) _jointPoints = jointPoints;
    notifyListeners();
  }

  void setMediaStatus(String status) {
    if (_mediaStatus == status) return;
    _mediaStatus = status;
    notifyListeners();
  }

  void broadcastSpeech(String speechText) {
    _latestPeerSpeechText = speechText;
    final roleTag = _currentRole == AppRole.hearing ? "You (Speech)" : "Peer (Speech)";
    addTranscript(roleTag, speechText, "hearing");

    if (kIsWeb) {
      try {
        if (SignConnectJsBridge.hasProperty('broadcastSignConnectSpeech')) {
          SignConnectJsBridge.callMethod('broadcastSignConnectSpeech', [_currentRoomId, speechText]);
        }
      } catch (e) {
        debugPrint("Speech broadcast error: $e");
      }
    } else {
      _socket?.emit('speech-transcript', {
        'roomId': _currentRoomId,
        'text': speechText,
        'isFinal': true,
      });
    }
    notifyListeners();
  }

  void simulateGesture(String gestureName, int confidence) {
    _lastRecognizedGesture = gestureName;
    _gestureConfidence = confidence;
    final roleTag = _currentRole == AppRole.deaf ? "You (ISL Sign)" : "You (Speech)";
    addTranscript(roleTag, gestureName, _currentRole == AppRole.deaf ? "deaf" : "hearing");

    if (kIsWeb) {
      try {
        if (SignConnectJsBridge.hasProperty('broadcastSignConnectGesture')) {
          SignConnectJsBridge.callMethod('broadcastSignConnectGesture', [_currentRoomId, gestureName, confidence]);
        }
      } catch (e) {
        debugPrint("Broadcast error: $e");
      }
    } else {
      _socket?.emit('gesture-recognized', {
        'roomId': _currentRoomId,
        'word': gestureName,
        'confidence': confidence,
      });
    }
    notifyListeners();
  }

  // =====================================================================
  // NATIVE (Android/iOS/desktop) REAL WEBRTC IMPLEMENTATION
  // =====================================================================

  /// Fetches camera + microphone access. Call AFTER runtime permissions
  /// have been granted (the WebcamView widget drives that UX).
  Future<bool> ensureLocalMedia({bool audio = true}) async {
    if (kIsWeb) return false;
    final existing = _localStream;
    if (existing != null) {
      if (existing.getVideoTracks().isNotEmpty) {
        // A peer connection created earlier (before permissions were granted,
        // or while detection held the camera) may still be sending nothing —
        // push every local track into it now.
        await _syncLocalTracksToPeer();
        return true;
      }
      // Stream exists but its video track was released to the detection
      // pipeline — take the camera back so the self-view and the peer both
      // get live video again.
      return _attachFreshVideoTrack(existing);
    }
    try {
      setMediaStatus("initializing");
      final stream = await _getUserMediaWithPermission(audio: audio);
      _localStream = stream;
      _applyTrackStates();
      setMediaStatus("ready");
      // The connection may already exist: it is created the moment the peer
      // sends an offer, which can happen before permissions were granted.
      await _syncLocalTracksToPeer();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("getUserMedia failed: $e");
      setMediaStatus("error");
      notifyListeners();
      return false;
    }
  }

  /// getUserMedia, requesting the runtime permission ourselves if the platform
  /// rejects the first attempt (a room can be joined before the dashboard has
  /// asked for camera/microphone access).
  Future<rtc.MediaStream> _getUserMediaWithPermission({required bool audio}) async {
    try {
      return await rtc.navigator.mediaDevices.getUserMedia(_mediaConstraints(audio));
    } catch (first) {
      debugPrint("getUserMedia denied, requesting permission: $first");
      final statuses = await [Permission.camera, Permission.microphone].request();
      final granted = statuses.values.every((s) => s.isGranted);
      if (!granted) {
        setMediaStatus("permission_denied");
        addTranscript(
            "System", "Camera/microphone permission is required for the call.", "system");
        rethrow;
      }
      return await rtc.navigator.mediaDevices.getUserMedia(_mediaConstraints(audio));
    }
  }

  Map<String, dynamic> _mediaConstraints(bool audio) => {
        'audio': audio,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 960},
          'height': {'ideal': 720},
          'frameRate': {'ideal': 30},
        },
      };

  void _applyTrackStates() {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getVideoTracks()) {
      track.enabled = _isCameraEnabled;
    }
    for (final track in stream.getAudioTracks()) {
      track.enabled = _isMicEnabled;
    }
  }

  /// Fully releases the camera device so another pipeline (e.g. the MediaPipe
  /// hand-landmarker screen) can own it while a call stays connected.
  Future<void> releaseCameraForDetection() async {
    if (kIsWeb) return;
    final stream = _localStream;
    if (stream == null) return;
    try {
      final videoTracks = List<rtc.MediaStreamTrack>.from(stream.getVideoTracks());
      // Find the sender currently carrying video so we can null it too.
      // NOTE: RTCRtpSender has no getParameters() in this plugin version and
      // rtpParametersToMap does not include "kind" — identify by track kind.
      final senders = await _peerConnection?.getSenders();
      rtc.RTCRtpSender? videoSender;
      for (final s in senders ?? const <rtc.RTCRtpSender>[]) {
        if (s.track?.kind == 'video') {
          videoSender = s;
          break;
        }
      }
      for (final t in videoTracks) {
        await senderReplaceTrack(videoSender, null);
        t.stop();
        stream.removeTrack(t);
      }
    } catch (e) {
      debugPrint("releaseCameraForDetection: $e");
    }
    notifyListeners();
  }

  /// Re-acquires the camera after the detection screen closes and hot-swaps
  /// it back into the ongoing WebRTC session.
  Future<void> reacquireCameraAfterDetection() async {
    if (kIsWeb) return;
    final local = _localStream;
    if (local == null) {
      await ensureLocalMedia();
      return;
    }
    await _attachFreshVideoTrack(local);
  }

  /// Opens a new front-camera track and swaps it into [target], after first
  /// dropping any stale video track the detection pipeline left behind.
  /// Both the local renderer and the RTP sender bind videoTracks[0], so a
  /// leftover stopped track would show as a black self-view.
  Future<bool> _attachFreshVideoTrack(rtc.MediaStream target) async {
    try {
      final fresh = await rtc.navigator.mediaDevices.getUserMedia({
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 960},
          'height': {'ideal': 720},
        },
        'audio': false,
      });
      final tracks = fresh.getVideoTracks();
      if (tracks.isEmpty) return false;

      for (final old in List<rtc.MediaStreamTrack>.from(target.getVideoTracks())) {
        if (tracks.any((t) => t.id == old.id)) continue;
        try {
          await old.stop();
        } catch (_) {}
        try {
          target.removeTrack(old);
        } catch (_) {}
      }
      for (final t in tracks) {
        target.addTrack(t);
      }

      _applyTrackStates();
      setMediaStatus("ready");
      await _ensureTrackSending(tracks.first);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("_attachFreshVideoTrack: $e");
      setMediaStatus("error");
      notifyListeners();
      return false;
    }
  }

  /// Makes sure the given local track is actually being sent to the peer.
  /// 1. A sender already carries this kind -> replaceTrack (no renegotiation).
  /// 2. A negotiated transceiver exists but its sender track was nulled
  ///    (releaseCameraForDetection) -> replaceTrack + setDirection + renego.
  /// 3. Nothing suitable (PeerConnection was created while detection held the
  ///    camera / before permissions were granted) -> addTrack + renegotiate.
  /// Works for audio as well as video: the call stays silent forever if the
  /// microphone track is only acquired after the connection was created.
  Future<void> _ensureTrackSending(rtc.MediaStreamTrack track) async {
    final pc = _peerConnection;
    if (pc == null) return;
    final kind = track.kind;

    try {
      // 1. Sender already sending this kind.
      final senders = await pc.getSenders();
      for (final s in senders) {
        if (s.track?.kind == kind) {
          if (s.track?.id == track.id) return; // nothing to do
          await senderReplaceTrack(s, track);
          debugPrint("[WebRTC] $kind track replaced on existing sender");
          return;
        }
      }

      // 2. Transceiver negotiated earlier, sender track currently null.
      final transceivers = await pc.getTransceivers();
      for (final t in transceivers) {
        if (t.sender.track == null && t.receiver.track?.kind == kind) {
          await senderReplaceTrack(t.sender, track);
          try {
            await t.setDirection(rtc.TransceiverDirection.SendRecv);
          } catch (e) {
            debugPrint("[WebRTC] setDirection(SendRecv): $e");
          }
          debugPrint("[WebRTC] $kind resumed on existing transceiver, renegotiating");
          await _renegotiateForVideo();
          return;
        }
      }

      // 3. No path at all — add the track (reuses a free transceiver if one
      //    exists) and renegotiate.
      final local = _localStream;
      if (local == null) return;
      final sender = await pc.addTrack(track, local);
      for (final t in await pc.getTransceivers()) {
        if (t.sender.senderId == sender.senderId) {
          try {
            await t.setDirection(rtc.TransceiverDirection.SendRecv);
          } catch (e) {
            debugPrint("[WebRTC] setDirection(SendRecv): $e");
          }
          break;
        }
      }
      debugPrint("[WebRTC] $kind addTrack done, renegotiating");
      await _renegotiateForVideo();
    } catch (e) {
      debugPrint("_ensureTrackSending: $e");
    }
  }

  /// Pushes every local track the connection is not sending yet. Called when
  /// the camera/microphone become available AFTER the peer connection was
  /// created (permissions are only requested once the dashboard opens).
  Future<void> _syncLocalTracksToPeer() async {
    final pc = _peerConnection;
    final local = _localStream;
    if (pc == null || local == null) return;
    try {
      for (final track in local.getTracks()) {
        await _ensureTrackSending(track);
      }
    } catch (e) {
      debugPrint("syncLocalTracks: $e");
    }
  }

  /// Best-effort recovery after ICE/connection failure: renegotiate with an
  /// ICE restart so both sides gather fresh candidates.
  Future<void> _recoverConnection() async {
    if (_iceRestartAttempts >= 2) {
      addTranscript("System",
          "Could not recover the call automatically — leave and rejoin.",
          "system");
      return;
    }
    _iceRestartAttempts++;
    for (var attempt = 0; attempt < 8; attempt++) {
      await Future.delayed(const Duration(milliseconds: 750));
      final pc = _peerConnection;
      if (pc == null) return;
      if (!_makingOffer &&
          pc.signalingState == rtc.RTCSignalingState.RTCSignalingStateStable) {
        addTranscript("System", "Restarting the connection (attempt $_iceRestartAttempts)…", "system");
        await _createOfferToPeer(iceRestart: true);
        return;
      }
    }
  }

  /// Offers again once the signaling state allows it so a freshly added
  /// video track (added after the initial offer) reaches the peer.
  Future<void> _renegotiateForVideo() async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final pc = _peerConnection;
      if (pc == null) return;
      if (!_makingOffer &&
          pc.signalingState == rtc.RTCSignalingState.RTCSignalingStateStable) {
        await _createOfferToPeer();
        return;
      }
      await Future.delayed(const Duration(milliseconds: 750));
    }
    debugPrint("[WebRTC] Could not renegotiate video: signaling never stable");
  }

  Future<void> senderReplaceTrack(rtc.RTCRtpSender? sender, rtc.MediaStreamTrack? track) async {
    if (sender == null) return;
    try {
      await sender.replaceTrack(track);
    } catch (e) {
      debugPrint("replaceTrack: $e");
    }
  }

  /// Connects to the signaling server and joins the current room.
  /// Safe to call from several places: joining twice would make the socket
  /// leave and re-enter the room, which makes the peer tear the call down
  /// and re-offer while we are still negotiating.
  Future<void> joinRoom() async {
    if (kIsWeb || _serverUrl.isEmpty) return;
    if (_joiningRoom) return;
    if (_activeRoomId == _currentRoomId &&
        _socket != null &&
        (_socket!.connected || _joiningRoom)) {
      return; // already in (or joining) this room
    }
    _joiningRoom = true;
    _activeRoomId = _currentRoomId;
    try {
      await _joinRoomImpl();
    } finally {
      _joiningRoom = false;
    }
  }

  Future<void> _joinRoomImpl() async {
    await ensureLocalMedia();

    _socket?.dispose();
    _peerConnection?.close();
    _peerConnection = null;
    _remoteStream = null;
    _isRemoteUserConnected = false;
    _peerPresent = false;

    try {
      final socket = sio.io(
        _serverUrl,
        sio.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .disableReconnection()
            .build(),
      );

      socket.onConnect((_) {
        _isConnected = true;
        addTranscript("System", "Connected to signaling server ($_serverUrl)", "system");
        socket.emit('join-room', {
          'roomId': _currentRoomId,
          'role': _currentRole == AppRole.deaf ? 'deaf' : 'hearing',
        });
        // Find the ML inference server once we know which host we talk to.
        resolveInfServer(verbose: true);
        notifyListeners();
      });

      socket.onDisconnect((_) {
        _isConnected = false;
        _isRemoteUserConnected = false;
        _peerPresent = false;
        if (_socket == socket) _activeRoomId = null;
        addTranscript("System", "Disconnected from signaling server.", "system");
        notifyListeners();
      });

      socket.onConnectError((data) {
        _isConnected = false;
        addTranscript("System", "Could not reach server at $_serverUrl. Check IP/port and firewall.", "system");
        notifyListeners();
      });

      socket.on('room-participants', (data) {
        // Data: [ { id, role }, ... ] — used to detect peers already in room.
        if (data is List) {
          final others = data.whereType<Map>().where((p) => p['id'] != socket.id).length;
          final hadPeer = _peerPresent;
          _peerPresent = others > 0;
          if (_peerPresent && !hadPeer) notifyListeners();

          // The side that was ALREADY in the room is told "user-joined" and
          // sends the offer. We only ever offer from here as a last-resort
          // fallback (event lost / socket reconnected) — offering twice makes
          // both peers answer each other and the call never connects.
          if (_peerPresent && _peerConnection == null && !_hasSentFallbackOffer) {
            _fallbackOfferTimer?.cancel();
            _fallbackOfferTimer = Timer(const Duration(seconds: 5), () {
              if (_peerConnection == null &&
                  _peerPresent &&
                  _socket?.connected == true) {
                _hasSentFallbackOffer = true;
                addTranscript(
                  "System",
                  "No offer received from peer — starting call ourselves.",
                  "system",
                );
                _createOfferToPeer();
              }
            });
          }
          if (!_peerPresent) {
            _fallbackOfferTimer?.cancel();
            _hasSentFallbackOffer = false;
          }
        }
      });

      socket.on('user-joined', (data) {
        if (data is Map && data['id'] != socket.id) {
          final roleStr = data['role']?.toString() ?? '';
          addTranscript("System", "Peer joined (${roleStr.isEmpty ? 'unknown' : roleStr} mode). Negotiating call...", "system");
          // Camera must belong to WebRTC while a peer is in the room.
          _peerPresent = true;
          _hasSentFallbackOffer = false;
          _fallbackOfferTimer?.cancel();
          notifyListeners();
          // Existing participant initiates the SDP offer.
          _createOfferToPeer();
        }
      });

      socket.on('user-left', (data) {
        _isRemoteUserConnected = false;
        _peerPresent = false;
        _fallbackOfferTimer?.cancel();
        _hasSentFallbackOffer = false;
        _iceRestartAttempts = 0;
        _teardownPeerConnection();
        addTranscript("System", "Your peer left the call.", "system");
        notifyListeners();
      });

      socket.on('offer', (data) => _handleOffer(data as Map<dynamic, dynamic>));
      socket.on('answer', (data) => _handleAnswer(data as Map<dynamic, dynamic>));
      socket.on('ice-candidate', (data) => _handleIceCandidate(data as Map<dynamic, dynamic>));

      socket.on('gesture-recognized', (data) {
        if (data is Map) {
          _lastRecognizedGesture = data['word']?.toString() ?? "-";
          _gestureConfidence = (data['confidence'] as num?)?.toInt() ?? 0;
          // origin:"self" = the web page recognised THIS device's signs on
          // the incoming video and echoed them back (the app's own camera
          // is serving the call, so the phone cannot detect during it).
          final origin = data['origin']?.toString() ?? '';
          final tag = origin == 'self' ? 'You (ISL Sign)' : 'Peer (ISL Sign)';
          addTranscript(tag, _lastRecognizedGesture, "deaf");
          notifyListeners();
        }
      });

      socket.on('room-log', (data) {
        if (data is Map) {
          debugPrint('[PageLog] ${data['msg']}');
        }
      });

      socket.on('speech-transcript', (data) {
        if (data is Map) {
          final sender = data['senderId']?.toString() ?? '';
          if (sender == socket.id) return;
          _latestPeerSpeechText = data['text']?.toString() ?? "";
          addTranscript("Peer (Speech)", _latestPeerSpeechText, "hearing");
          notifyListeners();
        }
      });

      socket.connect();
      _socket = socket;
    } catch (e) {
      debugPrint("joinRoom error: $e");
      _isConnected = false;
      addTranscript("System", "Signaling error: $e", "system");
      notifyListeners();
    }
  }

  /// Fetches TURN credentials from the signaling server's /api/turn-credentials
  /// endpoint. Falls back to STUN-only if the endpoint is unavailable.
  Future<List<Map<String, dynamic>>> _fetchIceServers() async {
    if (_cachedIceServers != null) return _cachedIceServers!;

    // Default: STUN-only (works if both peers are on the same network)
    final fallback = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ];

    if (_serverUrl.isEmpty) return fallback;

    try {
      final uri = Uri.parse('$_serverUrl/api/turn-credentials');
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3)
        ..badCertificateCallback = (_, __, ___) => true; // Allow self-signed certs
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 5));
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final servers = (data['iceServers'] as List)
            .map((s) => Map<String, dynamic>.from(s as Map))
            .toList();
        _cachedIceServers = servers;
        debugPrint("[TURN] Fetched ${servers.length} ICE servers from server");
        return servers;
      }
    } catch (e) {
      debugPrint("[TURN] Could not fetch credentials, using STUN-only: $e");
    }

    return fallback;
  }

  Future<rtc.RTCPeerConnection> _getOrCreatePeerConnection() async {
    final existing = _peerConnection;
    if (existing != null) {
      return existing;
    }

    // The peer connection must not be built without local media: joining a
    // room happens before the dashboard has asked for camera/microphone
    // permission, and a connection created back then would send neither
    // audio nor video for the whole call.
    if (_localStream == null) {
      await ensureLocalMedia();
    }

    final iceServers = await _fetchIceServers();
    final config = {
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    };

    final pc = await rtc.createPeerConnection(config);

    final local = _localStream;
    bool hasVideo = false;
    bool hasAudio = false;
    if (local != null) {
      for (final track in local.getTracks()) {
        await pc.addTrack(track, local);
        if (track.kind == 'video') hasVideo = true;
        if (track.kind == 'audio') hasAudio = true;
      }
      debugPrint("[WebRTC] PC created with local tracks "
          "video=$hasVideo audio=$hasAudio");
    } else {
      debugPrint("[WebRTC] WARNING: PC created without any local track");
      addTranscript("System",
          "Camera/microphone unavailable — the peer will not see or hear you.",
          "system");
    }
    // Always be able to RECEIVE media kinds we are not currently sending
    // (e.g. video while ISL detection still holds the camera).
    if (!hasVideo) {
      await pc.addTransceiver(kind: rtc.RTCRtpMediaType.RTCRtpMediaTypeVideo, init: rtc.RTCRtpTransceiverInit(direction: rtc.TransceiverDirection.RecvOnly));
    }
    if (!hasAudio) {
      await pc.addTransceiver(kind: rtc.RTCRtpMediaType.RTCRtpMediaTypeAudio, init: rtc.RTCRtpTransceiverInit(direction: rtc.TransceiverDirection.RecvOnly));
    }

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
      }
      final firstConnect = !_isRemoteUserConnected;
      _isRemoteUserConnected = true;
      if (firstConnect) {
        addTranscript("System",
            "Peer media received (${event.track.kind ?? 'track'}) — call is live.",
            "system");
      }
      notifyListeners();
    };

    pc.onIceCandidate = (candidate) {
      _socket?.emit('ice-candidate', {
        'roomId': _currentRoomId,
        'candidate': candidate.toMap(),
      });
    };

    pc.onConnectionState = (state) {
      debugPrint("PeerConnection state: $state");
      switch (state) {
        case rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _iceRestartAttempts = 0;
          addTranscript("System", "WebRTC connected.", "system");
          _logSenders("connected");
          break;
        case rtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _isRemoteUserConnected = false;
          addTranscript("System", "Connection failed — trying to recover…", "system");
          _recoverConnection();
          break;
        case rtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          addTranscript("System", "Connection interrupted…", "system");
          break;
        case rtc.RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _isRemoteUserConnected = false;
          break;
        default:
          break;
      }
      notifyListeners();
    };

    _peerConnection = pc;
    return pc;
  }

  Future<void> _createOfferToPeer({bool iceRestart = false}) async {
    try {
      final pc = await _getOrCreatePeerConnection();
      // Never fire a second offer while one is outstanding or while we are
      // answering — that desynchronises SDP and the call never connects.
      // NOTE: flutter_webrtc reports null for signalingState until the first
      // state event lands (i.e. right after the pc is created). Null must be
      // treated as the initial/stable state, otherwise the very first offer
      // is silently dropped and the peer waits forever.
      final state = pc.signalingState;
      if (_makingOffer ||
          (state != null &&
              state != rtc.RTCSignalingState.RTCSignalingStateStable)) {
        debugPrint("[WebRTC] offer skipped (state=$state)");
        return;
      }
      _makingOffer = true;
      final options = <String, dynamic>{
        'offerToReceiveVideo': 1,
        'offerToReceiveAudio': 1,
      };
      if (iceRestart) options['iceRestart'] = true;
      final offer = await pc.createOffer(options);
      await pc.setLocalDescription(offer);
      final desc = await pc.getLocalDescription();
      if (desc != null) {
        _socket?.emit('offer', {
          'roomId': _currentRoomId,
          'offer': desc.toMap(),
        });
        debugPrint("[WebRTC] offer sent (iceRestart=$iceRestart)");
        await _logSenders("after-offer");
      }
    } catch (e) {
      debugPrint("createOffer error: $e");
    } finally {
      _makingOffer = false;
    }
  }

  Future<void> _handleOffer(Map data) async {
    try {
      final offer = data['offer'];
      if (offer is! Map) return;
      final pc = await _getOrCreatePeerConnection();

      // Null (initial, pre-first-event) state means no local description is
      // pending — same reasoning as in _createOfferToPeer, and required here
      // or an incoming offer right after pc creation is wrongly treated as a
      // collision and dropped.
      final inState = pc.signalingState;
      final collision = _makingOffer ||
          (inState != null &&
              inState != rtc.RTCSignalingState.RTCSignalingStateStable);
      if (collision) {
        // Perfect negotiation: the peer with the LARGER socket id is "polite"
        // and rolls back its own offer; the other side ignores the incoming
        // one. Without this, both sides ignore each other's offer and the
        // connection stays black/silent forever.
        final myId = _socket?.id ?? '';
        final peerId = data['senderId']?.toString() ?? '';
        final polite = myId.isNotEmpty && peerId.isNotEmpty && myId.compareTo(peerId) > 0;
        if (!polite) {
          debugPrint("[WebRTC] offer ignored (collision, impolite peer)");
          return;
        }
        debugPrint("[WebRTC] offer collision — rolling back own offer (polite)");
        try {
          await pc.setLocalDescription(rtc.RTCSessionDescription(null, 'rollback'));
        } catch (e) {
          debugPrint("[WebRTC] rollback failed: $e — ignoring offer");
          return;
        }
      }

      await pc.setRemoteDescription(
          rtc.RTCSessionDescription(offer['sdp'] as String, offer['type'] as String));
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      final desc = await pc.getLocalDescription();
      if (desc != null) {
        _socket?.emit('answer', {
          'roomId': _currentRoomId,
          'answer': desc.toMap(),
        });
        debugPrint("[WebRTC] answer sent");
        await _logSenders("after-answer");
      }
    } catch (e) {
      debugPrint("handleOffer error: $e");
      addTranscript("System", "Call negotiation error: $e", "system");
    }
  }

  Future<void> _handleAnswer(Map data) async {
    try {
      final answer = data['answer'];
      if (answer is! Map) return;
      final pc = _peerConnection;
      if (pc == null) return;
      await pc.setRemoteDescription(rtc.RTCSessionDescription(answer['sdp'] as String, answer['type'] as String));
      debugPrint("[WebRTC] answer applied (state=${pc.signalingState})");
    } catch (e) {
      debugPrint("handleAnswer error: $e");
    }
  }

  /// Diagnostic: which tracks this side is actually sending, and the
  /// direction of every transceiver. Printed after each negotiation and on
  /// connect so a one-way-media problem is visible in logcat immediately.
  Future<void> _logSenders(String context) async {
    final pc = _peerConnection;
    if (pc == null) return;
    try {
      final senders = await pc.getSenders();
      for (final s in senders) {
        final t = s.track;
        debugPrint("[WebRTC] $context sender kind=${t?.kind ?? '?'} "
            "track=${t?.id ?? 'null'} enabled=${t?.enabled}");
      }
      final transceivers = await pc.getTransceivers();
      for (final tr in transceivers) {
        final dir = await tr.getCurrentDirection();
        debugPrint("[WebRTC] $context transceiver dir=$dir "
            "senderTrack=${tr.sender.track?.id ?? 'null'} "
            "recvKind=${tr.receiver.track?.kind ?? '-'}");
      }
    } catch (e) {
      debugPrint("[WebRTC] logSenders error: $e");
    }
  }

  Future<void> _handleIceCandidate(Map data) async {
    try {
      final candidate = data['candidate'];
      if (candidate is! Map) return;
      final pc = _peerConnection;
      if (pc == null) return;
      await pc.addCandidate(rtc.RTCIceCandidate(
        candidate['candidate'] as String?,
        candidate['sdpMid'] as String?,
        candidate['sdpMLineIndex'] as int?,
      ));
    } catch (e) {
      debugPrint("addIceCandidate error: $e");
    }
  }

  void _teardownPeerConnection() {
    try {
      _peerConnection?.close();
    } catch (_) {}
    _peerConnection = null;
    _remoteStream = null;
    notifyListeners();
  }

  void _syncRoleOnServer() {
    _socket?.emit('change-role', {
      'roomId': _currentRoomId,
      'role': _currentRole == AppRole.deaf ? 'deaf' : 'hearing',
    });
  }

  // ---------------- Native Speech-to-Text (Hearing mode) ----------------

  void _initNativeStt() {
    _speechToText.initialize(
      onError: (error) => debugPrint("STT error: ${error.errorMsg}"),
      onStatus: (status) {
        debugPrint("STT status: $status");
        if ((status == 'done' || status == 'notListening') && _sttShouldListen) {
          Future.delayed(const Duration(milliseconds: 300), () => _restartSttIfNeeded());
        }
      },
    ).then((available) {
      _sttAvailable = available;
      if (available && _shouldListen()) {
        _startSttListening();
      }
    }).catchError((e) {
      debugPrint("STT init failed: $e");
    });
  }

  bool _shouldListen() =>
      !kIsWeb && _sttShouldListen && _isMicEnabled && _currentRole == AppRole.hearing && _isConnected;

  Future<void> _restartSttIfNeeded({bool forceStart = false}) async {
    if (forceStart) _sttShouldListen = true;
    if (!_shouldListen()) return;
    try {
      if (_speechToText.isListening) return;
      _startSttListening();
    } catch (e) {
      debugPrint("STT restart error: $e");
    }
  }

  Future<void> _startSttListening() async {
    try {
      if (!_sttAvailable) {
        _sttAvailable = await _speechToText.initialize(
          onError: (error) => debugPrint("STT error: ${error.errorMsg}"),
          onStatus: (status) {
            if ((status == 'done' || status == 'notListening') && _sttShouldListen) {
              Future.delayed(const Duration(milliseconds: 300), () => _restartSttIfNeeded());
            }
          },
        );
        if (!_sttAvailable) return;
      }
      await _speechToText.listen(
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          localeId: 'en_IN',
        ),
        onResult: (result) {
          final text = result.recognizedWords.trim();
          if (text.isEmpty) return;
          if (result.finalResult) {
            broadcastSpeech(text);
          } else {
            // Live interim preview for the local user.
            _latestPeerSpeechText = text;
            notifyListeners();
          }
        },
      );
      _sttShouldListen = true;
    } catch (e) {
      debugPrint("STT listen error: $e");
    }
  }

  void _stopSpeechRecognition() {
    if (kIsWeb) return;
    _sttShouldListen = false;
    try {
      if (_speechToText.isListening) _speechToText.stop();
    } catch (_) {}
  }
}
