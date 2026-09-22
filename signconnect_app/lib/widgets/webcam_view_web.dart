// Web-only implementation of WebcamView (MediaPipe platform view).
// Loaded only on the browser platform via webcam_view.dart.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Web specific imports
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import '../services/signconnect_js_bridge_web.dart';
import '../services/socket_service.dart';

class WebcamView extends StatefulWidget {
  const WebcamView({super.key});

  @override
  State<WebcamView> createState() => _WebcamViewState();
}

class _WebcamViewState extends State<WebcamView> {
  static bool _isRegistered = false;
  static const String _staticViewType = 'webcam-mediapipe-feed-static';

  @override
  void initState() {
    super.initState();

    final socket = SocketService();
    socket.addListener(_onSocketChanged);

    if (kIsWeb) {
      _updateMediaPipeRole(socket.currentRole);

      if (!_isRegistered) {
        _isRegistered = true;

        ui_web.platformViewRegistry.registerViewFactory(_staticViewType, (int viewId) {
          const videoId = 'webcam-feed-element';
          const canvasId = 'landmark-canvas-element';

          final container = html.DivElement()
            ..style.position = 'relative'
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.backgroundColor = '#1E1916'
            ..style.overflow = 'hidden';

          final video = html.VideoElement()
            ..id = videoId
            ..autoplay = true
            ..muted = true
            ..setAttribute('playsinline', 'true')
            ..style.position = 'absolute'
            ..style.top = '0'
            ..style.left = '0'
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.objectFit = 'cover'
            ..style.zIndex = '1'
            ..style.transform = 'scaleX(-1)';

          final canvas = html.CanvasElement()
            ..id = canvasId
            ..style.position = 'absolute'
            ..style.top = '0'
            ..style.left = '0'
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.pointerEvents = 'none'
            ..style.zIndex = '10'
            ..style.transform = 'scaleX(-1)';

          final permBtn = html.ButtonElement()
            ..id = 'mobile-cam-perm-btn'
            ..innerText = '🎥 Tap to Enable Camera & Microphone'
            ..style.position = 'absolute'
            ..style.top = '50%'
            ..style.left = '50%'
            ..style.transform = 'translate(-50%, -50%)'
            ..style.zIndex = '20'
            ..style.padding = '12px 20px'
            ..style.backgroundColor = '#FF5E1E'
            ..style.color = '#FFFFFF'
            ..style.border = 'none'
            ..style.borderRadius = '24px'
            ..style.fontWeight = 'bold'
            ..style.fontSize = '13px'
            ..style.fontFamily = 'sans-serif'
            ..style.cursor = 'pointer'
            ..style.boxShadow = '0 4px 15px rgba(0,0,0,0.5)';

          container.children.addAll([video, canvas, permBtn]);

          void startMediaPipe() {
            try {
              if (SignConnectJsBridge.hasProperty('initSignConnectMediaPipe')) {
                SignConnectJsBridge.callMethod('initSignConnectMediaPipe', [
                  videoId,
                  canvasId,
                  (fps, latencyMs, jointPoints) {
                    SocketService().updateMetrics(
                      fps: (fps as num).toDouble(),
                      latencyMs: (latencyMs as num).toInt(),
                      jointPoints: (jointPoints as num).toInt(),
                    );
                  },
                  (gestureName, confidence) {
                    SocketService().simulateGesture(
                      gestureName.toString(),
                      (confidence as num).toInt(),
                    );
                  }
                ]);
              }
            } catch (e) {
              debugPrint("MediaPipe start notice: $e");
            }
          }

          void startFallbackCanvas() {
            try {
              final fallbackCanvas = html.CanvasElement()
                ..width = 640
                ..height = 480;
              final ctx = fallbackCanvas.getContext('2d') as html.CanvasRenderingContext2D;
              double step = 0;

              Timer.periodic(const Duration(milliseconds: 40), (timer) {
                step += 0.05;
                ctx.fillStyle = '#0F172A';
                ctx.fillRect(0, 0, 640, 480);

                ctx.strokeStyle = 'rgba(255, 255, 255, 0.08)';
                ctx.lineWidth = 1;
                for (int x = 0; x < 640; x += 40) {
                  ctx.beginPath(); ctx.moveTo(x.toDouble(), 0); ctx.lineTo(x.toDouble(), 480); ctx.stroke();
                }

                final hx = 320 + (15 * (step % 2));
                ctx.beginPath();
                ctx.arc(hx, 200, 50, 0, 6.28);
                ctx.fillStyle = '#334155';
                ctx.fill();
                ctx.strokeStyle = '#10B981';
                ctx.lineWidth = 3;
                ctx.stroke();

                ctx.fillStyle = '#FFFFFF';
                ctx.font = '16px sans-serif';
                ctx.fillText("ACTIVE STREAM - READY FOR SIGNING", 160, 50);
              });

              final stream = fallbackCanvas.captureStream(30);
              video.srcObject = stream;
              video.play();
              startMediaPipe();
            } catch (e) {
              debugPrint("Fallback stream notice: $e");
            }
          }

          void requestCameraAccess() {
            try {
              if (SignConnectJsBridge.hasProperty('startMobileCamera')) {
                SignConnectJsBridge.callMethod('startMobileCamera', [
                  videoId,
                  () {
                    permBtn.style.display = 'none';
                    startMediaPipe();
                  }
                ]);
              } else {
                startFallbackCanvas();
              }
            } catch(e) {
              startFallbackCanvas();
            }
          }

          permBtn.onClick.listen((_) => requestCameraAccess());
          requestCameraAccess();

          return container;
        });
      }
    }
  }

  void _onSocketChanged() {
    if (kIsWeb) {
      _updateMediaPipeRole(SocketService().currentRole);
    }
  }

  void _updateMediaPipeRole(AppRole role) {
    try {
      if (SignConnectJsBridge.hasProperty('setMediaPipeRole')) {
        final roleStr = role == AppRole.deaf ? 'deaf' : 'hearing';
        SignConnectJsBridge.callMethod('setMediaPipeRole', [roleStr]);
      }
    } catch (e) {
      debugPrint("MediaPipe role update notice: $e");
    }
  }

  @override
  void dispose() {
    SocketService().removeListener(_onSocketChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const HtmlElementView(viewType: _staticViewType);
    }

    return Center(
      child: Icon(
        Icons.camera_front_outlined,
        size: 72,
        color: Colors.white.withValues(alpha: 0.2),
      ),
    );
  }
}
