import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/socket_service.dart';
import '../widgets/webcam_view.dart';
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
    "Namaste", "House", "Book", "Help", "Time", "Food", "Water", "Love", "Yes", "No"
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return AnimatedBuilder(
      animation: _socket,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppTheme.bgCard,
            elevation: 0,
            title: Row(
              children: [
                Text(
                  "SignConnect",
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.brandOrangeDark,
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: _showRoomDialog,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.brandOrangeLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.brandOrange.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.meeting_room_outlined, size: 14, color: AppTheme.brandOrangeDark),
                        const SizedBox(width: 4),
                        Text(
                          _socket.currentRoomId,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.brandOrangeDark,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down, size: 14, color: AppTheme.brandOrangeDark),
                      ],
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
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.accentGreen,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _socket.currentRole == AppRole.deaf ? "Deaf Mode ⇄" : "Hearing Mode ⇄",
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: AppTheme.textSecondary),
                onPressed: () => widget.onNavigate("settings"),
                tooltip: "Open Settings",
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
                  SnackBar(content: Text("Copied room link: http://localhost:8080/#${_socket.currentRoomId}")),
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
          // Primary Video Call Stage (Dual Cameras + Controls)
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Expanded(child: _buildVideoCard()),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SizedBox(height: 380, child: _buildVideoCard()),
          const SizedBox(height: 16),
          _buildQuickSignBar(),
          const SizedBox(height: 16),
          SizedBox(height: 340, child: _buildTranscriptPanel()),
        ],
      ),
    );
  }

  Widget _buildVideoCard() {
    final isSwapped = _socket.isSwappedFeeds;

    // 1. Local Webcam Feed Widget
    final Widget localFeedWidget = _socket.isCameraEnabled
        ? const WebcamView(key: ValueKey('local_webcam_key'))
        : Container(
            color: const Color(0xFF181310),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.videocam_off_outlined, size: 64, color: AppTheme.textMuted),
                  const SizedBox(height: 12),
                  Text(
                    "Local Camera Muted",
                    style: GoogleFonts.outfit(fontSize: 16, color: Colors.white70),
                  ),
                ],
              ),
            ),
          );

    // 2. Remote Peer Video Feed Widget (WebRTC Stream)
    final Widget remoteFeedWidget = _socket.isRemoteUserConnected
        ? const RemoteWebcamView(key: ValueKey('remote_webcam_key'))
        : Container(
            color: const Color(0xFF0F172A),
            child: Center(
              child: Text(
                "Peer Disconnected",
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white54),
                textAlign: TextAlign.center,
              ),
            ),
          );

    final mainStageWidget = !isSwapped ? localFeedWidget : remoteFeedWidget;
    final pipStageWidget = !isSwapped ? remoteFeedWidget : localFeedWidget;
    final pipLabelText = !isSwapped
        ? (_socket.remoteRole == AppRole.hearing ? "Hearing Peer" : "Deaf Peer")
        : "You (Local Cam)";

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1916),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Stack(
        children: [
          // MAIN STAGE FEED (Swappable between Local & Peer Camera)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: mainStageWidget,
            ),
          ),

          // ROLE-BASED STATUS BADGE (Top Left)
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _socket.currentRole == AppRole.deaf ? AppTheme.accentGreen : Colors.blueAccent),
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
                  const SizedBox(width: 8),
                  Text(
                    _socket.currentRole == AppRole.deaf
                        ? "DEAF MODE — MEDIAPIPE SKELETON ACTIVE"
                        : "HEARING MODE — SPEECH-TO-TEXT ACTIVE",
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ROLE-BASED TRANSLATION BANNER (Top Overlay)
          Positioned(
            top: 56,
            left: 16,
            right: 160,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  )
                ],
              ),
              child: Row(
                children: [
                  Text(_socket.currentRole == AppRole.deaf ? "🤟" : "🎙️", style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _socket.currentRole == AppRole.deaf
                              ? "RECOGNIZED ISL GESTURE (HAND TRACKING)"
                              : "SPEECH TRANSLATED TO DEAF USER",
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.brandOrangeDark,
                          ),
                        ),
                        Text(
                          _socket.currentRole == AppRole.deaf
                              ? _socket.lastRecognizedGesture
                              : "Hello, how can I help you today?",
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _socket.currentRole == AppRole.deaf ? AppTheme.accentGreen : Colors.blueAccent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _socket.currentRole == AppRole.deaf ? "${_socket.gestureConfidence}%" : "LIVE STT",
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // SECONDARY PIP FLOATING CAMERA VIEW (Top Right Corner) — CLICKING SWAPS FEEDS!
          Positioned(
            top: 16,
            right: 16,
            child: GestureDetector(
              onTap: _socket.toggleSwapFeeds,
              child: Container(
                width: 135,
                height: 170,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.brandOrange, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    )
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: pipStageWidget,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.swap_calls, size: 14, color: Colors.white),
                      ),
                    ),
                    Positioned(
                      bottom: 4,
                      left: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "$pipLabelText (Tap Swap)",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 8,
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

          // STATS METRICS OVERLAY BAR (Bottom Left)
          Positioned(
            bottom: _socket.currentRole == AppRole.deaf ? 142 : 68,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "FPS: ${_socket.fps} | LATENCY: ${_socket.latencyMs}ms | JOINTS: ${_socket.jointPoints}",
                style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white70),
              ),
            ),
          ),

          // HEARING PEER SPEECH SUBTITLE CAPTION BANNER (FOR DEAF USER)
          if (_socket.currentRole == AppRole.deaf)
            Positioned(
              bottom: 68,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blueAccent, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    const Text("💬", style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "HEARING PEER SPEECH SUBTITLES",
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueAccent,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _socket.latestPeerSpeechText,
                            style: GoogleFonts.outfit(
                              fontSize: 15,
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

          // INTERACTIVE VIDEO CALL CONTROL DOCK BAR (Bottom Center)
          Positioned(
            bottom: 12,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mic Toggle Button
                  _buildControlButton(
                    icon: _socket.isMicEnabled ? Icons.mic_none_outlined : Icons.mic_off_outlined,
                    label: _socket.isMicEnabled ? "Mic On" : "Muted",
                    isActive: _socket.isMicEnabled,
                    activeColor: AppTheme.brandOrange,
                    onTap: () => _socket.toggleMic(),
                  ),

                  // Camera Toggle Button
                  _buildControlButton(
                    icon: _socket.isCameraEnabled ? Icons.videocam_outlined : Icons.videocam_off_outlined,
                    label: _socket.isCameraEnabled ? "Cam On" : "Cam Off",
                    isActive: _socket.isCameraEnabled,
                    activeColor: AppTheme.brandOrange,
                    onTap: () => _socket.toggleCamera(),
                  ),

                  // Hand Skeleton Toggle Button
                  _buildControlButton(
                    icon: _socket.isSkeletonEnabled ? Icons.gesture : Icons.visibility_off_outlined,
                    label: _socket.isSkeletonEnabled ? "Skeleton" : "Hidden",
                    isActive: _socket.isSkeletonEnabled,
                    activeColor: AppTheme.accentGreen,
                    onTap: () => _socket.toggleSkeleton(),
                  ),

                  // Swap Feeds Button
                  _buildControlButton(
                    icon: Icons.swap_calls,
                    label: isSwapped ? "Peer Main" : "Local Main",
                    isActive: isSwapped,
                    activeColor: Colors.deepPurpleAccent,
                    onTap: _socket.toggleSwapFeeds,
                  ),

                  // Switch Role Button
                  _buildControlButton(
                    icon: Icons.sync,
                    label: "Switch Role",
                    isActive: true,
                    activeColor: Colors.blueAccent,
                    onTap: _socket.switchRole,
                  ),

                  // Leave Call Button
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: btnColor.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: btnColor),
              ),
              child: Icon(icon, color: isDanger ? Colors.redAccent : Colors.white, size: 20),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9,
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
      padding: const EdgeInsets.all(16),
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
              Text(
                isDeaf ? "⚡ QUICK ISL SIGN SIMULATOR (DEAF USER)" : "🎙️ QUICK SPEECH-TO-TEXT SIMULATOR (HEARING USER)",
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDeaf ? AppTheme.brandOrangeDark : Colors.blueAccent,
                ),
              ),
              Text(
                isDeaf ? "Tap gesture to send to hearing peer" : "Tap phrase to broadcast text to deaf peer",
                style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: chipsList.map((itemText) {
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(itemText),
                    backgroundColor: AppTheme.bgCardSecondary,
                    labelStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
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
      padding: const EdgeInsets.all(20),
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
                  fontSize: 18,
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
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.textMuted),
                    onPressed: _socket.clearTranscripts,
                    tooltip: "Clear History",
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: AppTheme.borderColor, height: 1),
          const SizedBox(height: 12),

          Expanded(
            child: ListView.builder(
              itemCount: _socket.transcripts.length,
              itemBuilder: (context, index) {
                final item = _socket.transcripts[index];
                final isSystem = item["type"] == "system";
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
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
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.brandOrangeDark,
                            ),
                          ),
                          Text(
                            item["time"]!,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item["text"]!,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
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
