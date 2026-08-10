import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:js' as js;

enum AppRole { deaf, hearing }

class SocketService extends ChangeNotifier {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;

  SocketService._internal() {
    initWebRTC();
  }

  AppRole _currentRole = AppRole.deaf;
  String _currentRoomId = "signconnect-room";
  bool _isCameraEnabled = true;
  bool _isMicEnabled = true;
  bool _isSkeletonEnabled = true;
  bool _isTTSEnabled = true;
  bool _isRemoteUserConnected = true;
  bool _isSwappedFeeds = false;
  double _micSensitivity = 0.75;
  String _vocabularyFocus = "Daily";

  bool _isConnected = true;
  List<Map<String, String>> _transcripts = [
    {
      "sender": "SignConnect System",
      "text": "Welcome to SignConnect! Real-time two-way ISL translation session active.",
      "time": "Now",
      "type": "system"
    }
  ];

  String _lastRecognizedGesture = "Namaste";
  String _latestPeerSpeechText = "Hello! Ready to receive your sign language translation.";
  int _gestureConfidence = 98;
  int _jointPoints = 21;
  double _fps = 60.2;
  int _latencyMs = 12;

  // Getters
  AppRole get currentRole => _currentRole;
  AppRole get remoteRole => _currentRole == AppRole.deaf ? AppRole.hearing : AppRole.deaf;
  String get currentRoomId => _currentRoomId;
  bool get isCameraEnabled => _isCameraEnabled;
  bool get isMicEnabled => _isMicEnabled;
  bool get isSkeletonEnabled => _isSkeletonEnabled;
  bool get isTTSEnabled => _isTTSEnabled;
  bool get isRemoteUserConnected => _isRemoteUserConnected;
  bool get isSwappedFeeds => _isSwappedFeeds;
  double get micSensitivity => _micSensitivity;
  String get vocabularyFocus => _vocabularyFocus;
  bool get isConnected => _isConnected;
  List<Map<String, String>> get transcripts => _transcripts;
  String get lastRecognizedGesture => _lastRecognizedGesture;
  String get latestPeerSpeechText => _latestPeerSpeechText;
  int get gestureConfidence => _gestureConfidence;
  int get jointPoints => _jointPoints;
  double get fps => _fps;
  int get latencyMs => _latencyMs;

  void initWebRTC() {
    if (kIsWeb) {
      try {
        if (js.context.hasProperty('initSignConnectRTC')) {
          js.context.callMethod('initSignConnectRTC', [
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
    }
  }

  void setRole(AppRole role) {
    _currentRole = role;
    initWebRTC();
    notifyListeners();
  }

  void switchRole() {
    _currentRole = _currentRole == AppRole.deaf ? AppRole.hearing : AppRole.deaf;
    addTranscript("System", "Switched primary role to ${_currentRole == AppRole.deaf ? 'Deaf Mode' : 'Hearing Mode'}", "system");
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
    notifyListeners();
  }

  void toggleMic([bool? value]) {
    _isMicEnabled = value ?? !_isMicEnabled;
    notifyListeners();
  }

  void toggleSkeleton() {
    _isSkeletonEnabled = !_isSkeletonEnabled;
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
        if (js.context.hasProperty('leaveSignConnectCall')) {
          js.context.callMethod('leaveSignConnectCall');
        }
      } catch (e) {
        debugPrint("Leave call error: $e");
      }
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

  void broadcastSpeech(String speechText) {
    _latestPeerSpeechText = speechText;
    final roleTag = _currentRole == AppRole.hearing ? "You (Speech)" : "Peer (Speech)";
    addTranscript(roleTag, speechText, "hearing");

    if (kIsWeb) {
      try {
        if (js.context.hasProperty('broadcastSignConnectSpeech')) {
          js.context.callMethod('broadcastSignConnectSpeech', [_currentRoomId, speechText]);
        }
      } catch (e) {
        debugPrint("Speech broadcast error: $e");
      }
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
        if (js.context.hasProperty('broadcastSignConnectGesture')) {
          js.context.callMethod('broadcastSignConnectGesture', [_currentRoomId, gestureName, confidence]);
        }
      } catch (e) {
        debugPrint("Broadcast error: $e");
      }
    }
    notifyListeners();
  }
}
