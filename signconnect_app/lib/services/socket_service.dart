import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'signconnect_js_bridge.dart';
import 'dart:io' show HttpClient, HttpClientRequest, HttpClientResponse;

enum AppRole { deaf, hearing }

class SocketService extends ChangeNotifier {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;

  SocketService._internal() {
    if (!kIsWeb) {
      _initNativeStt();
    }
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
  bool _isSwappedFeeds = false;
  double _micSensitivity = 0.75;
  String _vocabularyFocus = "Daily";

  String _userName = "Alex Sharma";
  String _userEmail = "alex@signconnect.org";
  bool _isAuthenticated = false;

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
  rtc.RTCRtpSender? _cachedVideoSender;
  bool _makingOffer = false;
  bool _ignoreOffer = false;
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
          ? "Live ISL sign detection enabled — your peer sees a placeholder while detection runs."
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
    if (_localStream != null) return true;
    try {
      setMediaStatus("initializing");
      final stream = await rtc.navigator.mediaDevices.getUserMedia({
        'audio': audio,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 960},
          'height': {'ideal': 720},
          'frameRate': {'ideal': 30},
        },
      });
      _localStream = stream;
      _applyTrackStates();
      setMediaStatus("ready");
      return true;
    } catch (e) {
      debugPrint("getUserMedia failed: $e");
      setMediaStatus("error");
      return false;
    }
  }

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
      final videoTracks = stream.getVideoTracks();
      // Remember the sender so we can hot-swap the track back on resume.
      final senders = await _peerConnection?.getSenders();
      rtc.RTCRtpSender? videoSender;
      for (final s in senders ?? const []) {
        if ((await s.getParameters()).kind == 'video') {
          videoSender = s;
          break;
        }
      }
      _cachedVideoSender = videoSender;
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
  /// it back into the ongoing WebRTC session without renegotiation.
  Future<void> reacquireCameraAfterDetection() async {
    if (kIsWeb) return;
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
      if (tracks.isEmpty) return;

      if (_localStream != null) {
        for (final t in tracks) {
          _localStream!.addTrack(t);
        }
      } else {
        await ensureLocalMedia();
        return;
      }
      _applyTrackStates();
      await senderReplaceTrack(_cachedVideoSender, tracks.first);
      _cachedVideoSender = null;
    } catch (e) {
      debugPrint("reacquireCameraAfterDetection: $e");
    }
    notifyListeners();
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
  Future<void> joinRoom() async {
    if (kIsWeb || _serverUrl.isEmpty) return;
    await ensureLocalMedia();

    _socket?.dispose();
    _peerConnection?.close();
    _peerConnection = null;
    _remoteStream = null;
    _isRemoteUserConnected = false;

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
        notifyListeners();
      });

      socket.onDisconnect((_) {
        _isConnected = false;
        _isRemoteUserConnected = false;
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
          if (others > 0 && _peerConnection == null) {
            // A peer was already here before us; wait a beat then offer.
            Future.delayed(const Duration(milliseconds: 600), () {
              if (_peerConnection == null) {
                _createOfferToPeer();
              }
            });
          }
        }
      });

      socket.on('user-joined', (data) {
        if (data is Map && data['id'] != socket.id) {
          final roleStr = data['role']?.toString() ?? '';
          addTranscript("System", "Peer joined (${roleStr.isEmpty ? 'unknown' : roleStr} mode). Negotiating call...", "system");
          // Existing participant initiates the SDP offer.
          _createOfferToPeer();
        }
      });

      socket.on('user-left', (data) {
        _isRemoteUserConnected = false;
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
          addTranscript("Peer (ISL Sign)", _lastRecognizedGesture, "deaf");
          notifyListeners();
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

    final iceServers = await _fetchIceServers();
    final config = {
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    };

    final pc = await rtc.createPeerConnection(config);

    final local = _localStream;
    if (local != null) {
      for (final track in local.getTracks()) {
        await pc.addTrack(track, local);
      }
    } else {
      // Still able to RECEIVE even without local media permission.
      await pc.addTransceiver(kind: rtc.RTCRtpMediaType.RTCRtpMediaTypeVideo, init: rtc.RTCRtpTransceiverInit(direction: rtc.TransceiverDirection.RecvOnly));
      await pc.addTransceiver(kind: rtc.RTCRtpMediaType.RTCRtpMediaTypeAudio, init: rtc.RTCRtpTransceiverInit(direction: rtc.TransceiverDirection.RecvOnly));
    }

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _isRemoteUserConnected = true;
        addTranscript("System", "Call connected! Video streaming both ways.", "system");
        notifyListeners();
      }
    };

    pc.onIceCandidate = (candidate) {
      _socket?.emit('ice-candidate', {
        'roomId': _currentRoomId,
        'candidate': candidate.toMap(),
      });
    };

    pc.onConnectionState = (state) {
      debugPrint("PeerConnection state: $state");
      if (state == rtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == rtc.RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _isRemoteUserConnected = false;
        notifyListeners();
      }
    };

    _peerConnection = pc;
    return pc;
  }

  Future<void> _createOfferToPeer() async {
    try {
      final pc = await _getOrCreatePeerConnection();
      _makingOffer = true;
      final offer = await pc.createOffer({'offerToReceiveVideo': 1, 'offerToReceiveAudio': 1});
      await pc.setLocalDescription(offer);
      final desc = await pc.getLocalDescription();
      if (desc != null) {
        _socket?.emit('offer', {
          'roomId': _currentRoomId,
          'offer': desc.toMap(),
        });
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

      final collision = _makingOffer || pc.signalingState != rtc.RTCSignalingState.RTCSignalingStateStable;
      _ignoreOffer = collision;
      if (_ignoreOffer) return;

      await pc.setRemoteDescription(rtc.RTCSessionDescription(offer['sdp'] as String, offer['type'] as String));
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      final desc = await pc.getLocalDescription();
      if (desc != null) {
        _socket?.emit('answer', {
          'roomId': _currentRoomId,
          'answer': desc.toMap(),
        });
      }
    } catch (e) {
      debugPrint("handleOffer error: $e");
    }
  }

  Future<void> _handleAnswer(Map data) async {
    try {
      final answer = data['answer'];
      if (answer is! Map) return;
      final pc = _peerConnection;
      if (pc == null) return;
      await pc.setRemoteDescription(rtc.RTCSessionDescription(answer['sdp'] as String, answer['type'] as String));
    } catch (e) {
      debugPrint("handleAnswer error: $e");
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
