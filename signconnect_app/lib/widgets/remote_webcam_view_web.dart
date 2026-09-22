// Web-only implementation of RemoteWebcamView (peer video platform view).
// Loaded only on the browser platform via remote_webcam_view.dart.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

class RemoteWebcamView extends StatefulWidget {
  const RemoteWebcamView({super.key});

  @override
  State<RemoteWebcamView> createState() => _RemoteWebcamViewState();
}

class _RemoteWebcamViewState extends State<RemoteWebcamView> {
  static bool _isRegistered = false;
  static const String _staticViewType = 'remote-peer-video-feed-static';

  @override
  void initState() {
    super.initState();
    if (kIsWeb && !_isRegistered) {
      _isRegistered = true;

      ui_web.platformViewRegistry.registerViewFactory(_staticViewType, (int viewId) {
        final video = html.VideoElement()
          ..id = 'remote-peer-video-element'
          ..autoplay = true
          ..muted = true
          ..setAttribute('playsinline', 'true')
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'cover'
          ..style.display = 'block'
          ..style.backgroundColor = '#0F172A';

        return video;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const HtmlElementView(viewType: _staticViewType);
    }
    return Container(
      color: const Color(0xFF0F172A),
      child: const Center(
        child: Icon(Icons.person, size: 48, color: Colors.white24),
      ),
    );
  }
}
