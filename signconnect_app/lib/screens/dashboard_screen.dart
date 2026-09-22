import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/socket_service.dart';
import '../widgets/hand_detector_view.dart';
import '../widgets/remote_webcam_view.dart';

class DashboardScreen extends StatefulWidget {
  final Function(String) onNavigate;

  const DashboardScreen({super.key, required this.onNavigate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final SocketService _socket = SocketService();
  final List<String> _quickSigns = [
    "Hello", "Thank You", "House", "Book", "Food", "Love", "Water",
    "Good", "Bad", "Help", "Time", "Please", "Stop", "Yes", "No"
  ];

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 850;

    return AnimatedBuilder(
      animation: _socket,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppTheme.bgCard,
            elevation: 0,
            titleSpacing: isDesktop ? 16 : 8,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    width: isDesktop ? 28 : 24,
                    height: isDesktop ? 28 : 24,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const SizedBox(),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "SignConnect",
                  style: GoogleFonts.outfit(
                    fontSize: isDesktop ? 20 : 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.brandOrangeDark,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: InkWell(
                    onTap: _showRoomDialog,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.brandOrangeLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.brandOrange.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.meeting_room_outlined, size: 12, color: AppTheme.brandOrangeDark),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _socket.currentRoomId,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.brandOrangeDark,
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, size: 12, color: AppTheme.brandOrangeDark),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              InkWell(
                onTap: _socket.switchRole,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCardSecondary,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _socket.currentRole == AppRole.deaf ? AppTheme.accentGreen : Colors.blueAccent,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _socket.currentRole == AppRole.deaf ? "Deaf ⇄" : "Hearing ⇄",
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: AppTheme.textSecondary, size: 20),
                onPressed: () => widget.onNavigate("settings"),
                tooltip: "Settings",
              ),
            ],
          ),
          body: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
        );
      },
    );
  }

  void _showRoomDialog() {
    final controller = TextEditingController(text: _socket.currentRoomId);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            "Call Room Information",
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Share this room code with your peer to start a 2-way video call:",
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: "Room Identifier Code",
                  prefixIcon: Icon(Icons.vpn_key_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Copied room identifier: ${_socket.currentRoomId}")),
                );
                Navigator.pop(context);
              },
              child: const Text("Copy Link"),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  _socket.setRoomId(controller.text.trim());
                }
                Navigator.pop(context);
              },
              child: const Text("Switch Room"),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDesktopLayout() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Primary Video Stage (Dual Cameras + Controls)
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Expanded(child: _buildVideoCard(isMobile: false)),
                const SizedBox(height: 16),
                _buildQuickSignBar(),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // Live Transcript Sidebar Panel
          Expanded(
            flex: 2,
            child: _buildTranscriptPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          SizedBox(height: 440, child: _buildVideoCard(isMobile: true)),
          const SizedBox(height: 12),
          _buildQuickSignBar(),
          const SizedBox(height: 12),
          SizedBox(height: 320, child: _buildTranscriptPanel()),
        ],
      ),
    );
  }

  Widget _buildVideoCard({required bool isMobile}) {
    final isSwapped = _socket.isSwappedFeeds;

    // 1. Local Webcam Feed Widget (WebRTC video OR live MediaPipe detection)
    final Widget localFeedWidget = _socket.isCameraEnabled
        ? const HandDetectorView(key: ValueKey('local_webcam_key'))
        : Container(
            color: const Color(0xFF181310),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.videocam_off_outlined, size: 48, color: AppTheme.textMuted),
                  const SizedBox(height: 8),
                  Text(
                    "Camera Muted",
                    style: GoogleFonts.outfit(fontSize: 14, color: Colors.white70),
                  ),
                ],
              ),
            ),
          );

    // 2. Remote Peer Video Feed Widget (Always mounted so remote-peer-video-element exists in DOM)
    const Widget remoteFeedWidget = RemoteWebcamView(key: ValueKey('remote_webcam_key'));

    final mainStageWidget = !isSwapped ? localFeedWidget : remoteFeedWidget;
    final pipStageWidget = !isSwapped ? remoteFeedWidget : localFeedWidget;
    final pipLabelText = !isSwapped
        ? (_socket.remoteRole == AppRole.hearing ? "Hearing Peer" : "Deaf Peer")
        : "You (Local)";

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1916),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Stack(
        children: [
          // MAIN STAGE FEED
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: mainStageWidget,
            ),
          ),

          // ROLE-BASED STATUS BADGE (Top Left)
          Positioned(
            top: isMobile ? 8 : 14,
            left: isMobile ? 8 : 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _socket.currentRole == AppRole.deaf ? AppTheme.accentGreen : Colors.blueAccent),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _socket.currentRole == AppRole.deaf ? AppTheme.accentGreen : Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _socket.currentRole == AppRole.deaf
                        ? "DEAF MODE — ISL ACTIVE"
                        : "HEARING MODE — STT ACTIVE",
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

          // TRANSLATION BANNER (Top Overlay)
          Positioned(
            top: isMobile ? 36 : 52,
            left: isMobile ? 8 : 14,
            right: isMobile ? 8 : 150,
            child: Container(
              padding: EdgeInsets.all(isMobile ? 8 : 12),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  )
                ],
              ),
              child: Row(
                children: [
                  Text(_socket.currentRole == AppRole.deaf ? "🤟" : "🎙️", style: TextStyle(fontSize: isMobile ? 18 : 22)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _socket.currentRole == AppRole.deaf
                              ? "RECOGNIZED ISL GESTURE"
                              : "SPEECH TRANSLATED TO DEAF USER",
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.brandOrangeDark,
                          ),
                        ),
                        Text(
                          _socket.currentRole == AppRole.deaf
                              ? _socket.lastRecognizedGesture
                              : _socket.latestPeerSpeechText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: isMobile ? 14 : 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _socket.currentRole == AppRole.deaf ? AppTheme.accentGreen : Colors.blueAccent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _socket.currentRole == AppRole.deaf ? "${_socket.gestureConfidence}%" : "LIVE STT",
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // SECONDARY FLOATING PIP CARD (Top Right)
          Positioned(
            top: isMobile ? 104 : 14,
            right: isMobile ? 8 : 14,
            child: GestureDetector(
              onTap: _socket.toggleSwapFeeds,
              child: Container(
                width: isMobile ? 100 : 130,
                height: isMobile ? 125 : 160,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.brandOrange, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    )
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: pipStageWidget,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.swap_calls, size: 12, color: Colors.white),
                      ),
                    ),
                    Positioned(
                      bottom: 4,
                      left: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "$pipLabelText (Tap Swap)",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 7.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // STATS METRICS OVERLAY (Bottom Left) — only when real metrics exist
          if (_socket.fps > 0)
            Positioned(
            bottom: isMobile
                ? (_socket.currentRole == AppRole.deaf ? 125 : 62)
                : (_socket.currentRole == AppRole.deaf ? 138 : 64),
            left: isMobile ? 8 : 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "FPS: ${_socket.fps} | LATENCY: ${_socket.latencyMs}ms",
                style: GoogleFonts.jetBrainsMono(fontSize: 8.5, color: Colors.white70),
              ),
            ),
          ),

          // HEARING PEER SPEECH SUBTITLE CAPTION BANNER (FOR DEAF USER)
          if (_socket.currentRole == AppRole.deaf)
            Positioned(
              bottom: isMobile ? 58 : 64,
              left: isMobile ? 8 : 14,
              right: isMobile ? 8 : 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.blueAccent, width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    const Text("💬", style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "HEARING PEER SPEECH SUBTITLES",
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueAccent,
                            ),
                          ),
                          Text(
                            _socket.latestPeerSpeechText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: isMobile ? 12.5 : 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // CONTROL DOCK BAR (Bottom Center - Horizontally Scrollable)
          Positioned(
            bottom: 8,
            left: isMobile ? 6 : 14,
            right: isMobile ? 6 : 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildControlButton(
                      icon: _socket.isMicEnabled ? Icons.mic_none_outlined : Icons.mic_off_outlined,
                      label: _socket.isMicEnabled ? "Mic On" : "Muted",
                      isActive: _socket.isMicEnabled,
                      activeColor: AppTheme.brandOrange,
                      onTap: () => _socket.toggleMic(),
                    ),
                    _buildControlButton(
                      icon: _socket.isCameraEnabled ? Icons.videocam_outlined : Icons.videocam_off_outlined,
                      label: _socket.isCameraEnabled ? "Cam On" : "Cam Off",
                      isActive: _socket.isCameraEnabled,
                      activeColor: AppTheme.brandOrange,
                      onTap: () => _socket.toggleCamera(),
                    ),
                    _buildControlButton(
                      icon: _socket.isSkeletonEnabled ? Icons.gesture : Icons.visibility_off_outlined,
                      label: _socket.isSkeletonEnabled ? "Skeleton" : "Hidden",
                      isActive: _socket.isSkeletonEnabled,
                      activeColor: AppTheme.accentGreen,
                      onTap: () => _socket.toggleSkeleton(),
                    ),
                    _buildControlButton(
                      icon: Icons.swap_calls,
                      label: isSwapped ? "Peer Main" : "Local Main",
                      isActive: isSwapped,
                      activeColor: Colors.deepPurpleAccent,
                      onTap: _socket.toggleSwapFeeds,
                    ),
                    _buildControlButton(
                      icon: Icons.back_hand_outlined,
                      label: _socket.isDetectionEnabled ? "Signs ON" : "Signs OFF",
                      isActive: _socket.isDetectionEnabled,
                      activeColor: AppTheme.accentGreen,
                      onTap: () => _socket.toggleDetection(),
                    ),
                    _buildControlButton(
                      icon: Icons.sync,
                      label: "Switch Role",
                      isActive: true,
                      activeColor: Colors.blueAccent,
                      onTap: _socket.switchRole,
                    ),
                    _buildControlButton(
                      icon: Icons.call_end,
                      label: "Leave Call",
                      isActive: false,
                      activeColor: Colors.redAccent,
                      isDanger: true,
                      onTap: _showLeaveCallDialog,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    final btnColor = isDanger
        ? Colors.redAccent
        : (isActive ? activeColor : Colors.white24);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: btnColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(color: btnColor),
              ),
              child: Icon(icon, color: isDanger ? Colors.redAccent : Colors.white, size: 18),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 8.5,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLeaveCallDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("Leave Call Room?", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          content: Text(
            "Are you sure you want to exit '${_socket.currentRoomId}' and stop camera feed?",
            style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () {
                _socket.leaveCall();
                Navigator.pop(context);
                widget.onNavigate("room_join");
              },
              child: const Text("Leave Room"),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickSignBar() {
    final isDeaf = _socket.currentRole == AppRole.deaf;
    final List<String> chipsList = isDeaf
        ? _quickSigns
        : ["Hello!", "How can I help you?", "Where do you want to go?", "What is your name?", "Please take care", "Thank you!"];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  isDeaf ? "⚡ QUICK ISL SIGN SIMULATOR" : "🎙️ QUICK SPEECH-TO-TEXT SIMULATOR",
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDeaf ? AppTheme.brandOrangeDark : Colors.blueAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: chipsList.map((itemText) {
                return Container(
                  margin: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(itemText),
                    backgroundColor: AppTheme.bgCardSecondary,
                    labelStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                    onPressed: () {
                      if (isDeaf) {
                        _socket.simulateGesture(itemText, 98);
                      } else {
                        _socket.broadcastSpeech(itemText);
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isDeaf ? "Broadcasted ISL Gesture: $itemText" : "Broadcasted Speech Subtitles: $itemText"),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "💬 Live Transcripts",
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              Row(
                children: [
                  Text(
                    "${_socket.transcripts.length} ENTRIES",
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.textMuted),
                    onPressed: _socket.clearTranscripts,
                    tooltip: "Clear History",
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Divider(color: AppTheme.borderColor, height: 1),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _socket.transcripts.length,
              itemBuilder: (context, index) {
                final item = _socket.transcripts[index];
                final isSystem = item["type"] == "system";
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSystem ? const Color(0xFFFAF0EB) : AppTheme.bgCardSecondary,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            item["sender"]!,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.brandOrangeDark,
                            ),
                          ),
                          Text(
                            item["time"]!,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item["text"]!,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
