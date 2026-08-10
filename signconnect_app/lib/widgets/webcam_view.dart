import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Web specific imports
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:js' as js;
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
          final videoId = 'webcam-feed-element';
          final canvasId = 'landmark-canvas-element';

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

          container.children.addAll([video, canvas]);

          final startMediaPipe = () {
            if (js.context.hasProperty('initSignConnectMediaPipe')) {
              js.context.callMethod('initSignConnectMediaPipe', [
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
          };

          html.window.navigator.mediaDevices?.getUserMedia({'video': true}).then((stream) {
            video.srcObject = stream;

            if (video.readyState >= 1) {
              startMediaPipe();
            } else {
              video.onLoadedMetadata.listen((_) => startMediaPipe());
            }
          }).catchError((err) {
            debugPrint("Webcam access error: $err");
          });

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
      if (js.context.hasProperty('setMediaPipeRole')) {
        final roleStr = role == AppRole.deaf ? 'deaf' : 'hearing';
        js.context.callMethod('setMediaPipeRole', [roleStr]);
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
        color: Colors.white.withOpacity(0.2),
      ),
    );
  }
}
