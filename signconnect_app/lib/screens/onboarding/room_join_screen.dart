import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../widgets/step_indicator.dart';
import '../../services/socket_service.dart';

class RoomJoinScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const RoomJoinScreen({super.key, required this.onComplete});

  @override
  State<RoomJoinScreen> createState() => _RoomJoinScreenState();
}

const String kDefaultServerUrl = "https://islsignconnect.onrender.com";

class _RoomJoinScreenState extends State<RoomJoinScreen> {
  final TextEditingController _roomController = TextEditingController(text: "signconnect-room");
  final TextEditingController _serverController =
      TextEditingController(text: kDefaultServerUrl);
  bool _isConnecting = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _loadSavedConfig();
  }

  Future<void> _loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      final savedServer = prefs.getString('signconnect_server_url');
      if (savedServer != null && savedServer.isNotEmpty && _isValidServerUrl(savedServer)) {
        _serverController.text = savedServer;
      } else {
        _serverController.text = kDefaultServerUrl;
      }
      final savedRoom = prefs.getString('signconnect_room_id');
      if (savedRoom != null && savedRoom.isNotEmpty) {
        _roomController.text = savedRoom;
      }
    });
  }

  String _generateRoomCode() {
    const letters = "abcdefghijkmnopqrstuvwxyz";
    final rnd = DateTime.now().microsecondsSinceEpoch;
    String chunk(int seed, int len) =>
        List.generate(len, (i) => letters[(seed >> (i * 3)) % letters.length]).join();
    return "${chunk(rnd, 3)}-${chunk(rnd >> 9, 4)}-${chunk(rnd >> 21, 3)}";
  }

  bool _isValidServerUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  String _buildShareableLink() {
    final server = _serverController.text.trim();
    final room = _roomController.text.trim();
    if (server.isEmpty || room.isEmpty) return "";
    return "$server/room/$room";
  }

  void _copyShareLink() {
    final link = _buildShareableLink();
    if (link.isEmpty) {
      setState(() => _errorText = "Enter both server URL and room code first.");
      return;
    }
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Room link copied! Share it with your friend."),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: "OK",
          onPressed: () {},
        ),
      ),
    );
  }

  Future<void> _launchSession() async {
    final roomId = _roomController.text.trim();
    final serverUrl = _serverController.text.trim();

    if (roomId.isEmpty) {
      setState(() => _errorText = "Please enter a room code.");
      return;
    }
    if (!_isValidServerUrl(serverUrl)) {
      setState(() => _errorText = "Enter the server URL, e.g. $kDefaultServerUrl");
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorText = null;
    });

    final socket = SocketService();
    socket.setServerUrl(serverUrl);
    socket.setRoomId(roomId);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('signconnect_server_url', serverUrl);
    await prefs.setString('signconnect_room_id', roomId);

    if (!mounted) return;
    setState(() => _isConnecting = false);
    widget.onComplete();
  }

  @override
  void dispose() {
    _roomController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "SignConnect",
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.brandOrangeDark,
                    ),
                  ),
                  const StepIndicator(currentStep: 4, totalSteps: 4),
                ],
              ),
            ),
            const Divider(color: AppTheme.borderColor, height: 1),

            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 480),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: AppTheme.brandOrangeLight,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Center(
                              child: Text("🤟", style: TextStyle(fontSize: 32)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Center(
                          child: Text(
                            "Enter Communication Room",
                            style: GoogleFonts.outfit(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            "Both peers must join the SAME room code to start a live video call.",
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 28),

                        Text(
                          "SIGNALING SERVER",
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _serverController,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            hintText: kDefaultServerUrl,
                            prefixIcon: const Icon(Icons.dns_outlined, color: AppTheme.textSecondary),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.help_outline, size: 18),
                              tooltip: "Enter the public URL of your deployed server",
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Enter the full URL of your SignConnect server (default: $kDefaultServerUrl). Both devices use this same URL to connect.",
                                    ),
                                    duration: Duration(seconds: 5),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                "ROOM CODE",
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ),
                            Tooltip(
                              message: "Copy room link to share with your friend",
                              child: IconButton(
                                onPressed: _copyShareLink,
                                icon: const Icon(Icons.share_outlined, size: 18),
                                style: IconButton.styleFrom(
                                  backgroundColor: AppTheme.brandOrangeLight,
                                  padding: const EdgeInsets.all(6),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _roomController,
                                decoration: const InputDecoration(
                                  hintText: "e.g. room-101",
                                  prefixIcon: Icon(Icons.meeting_room_outlined, color: AppTheme.textSecondary),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: "Create a new Meet-style room code",
                              child: IconButton.filled(
                                onPressed: () {
                                  setState(() {
                                    _roomController.text = _generateRoomCode();
                                  });
                                },
                                style: IconButton.styleFrom(backgroundColor: AppTheme.brandOrangeLight),
                                icon: const Icon(Icons.casino_outlined, color: AppTheme.brandOrangeDark),
                              ),
                            ),
                          ],
                        ),
                        if (_errorText != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _errorText!,
                            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.redAccent),
                          ),
                        ],
                        const SizedBox(height: 28),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isConnecting ? null : _launchSession,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.brandOrangeDark,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            icon: _isConnecting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.video_call_rounded),
                            label: Text(
                              _isConnecting ? "Connecting..." : "Launch SignConnect",
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
