import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../widgets/step_indicator.dart';
import '../../services/socket_service.dart';

class RoomJoinScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const RoomJoinScreen({super.key, required this.onComplete});

  @override
  State<RoomJoinScreen> createState() => _RoomJoinScreenState();
}

class _RoomJoinScreenState extends State<RoomJoinScreen> {
  final TextEditingController _roomController = TextEditingController(text: "signconnect-room");

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
                            "Connect with peers in real-time for live ISL gesture translation.",
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 28),

                        Text(
                          "ROOM IDENTIFIER CODE",
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _roomController,
                          decoration: const InputDecoration(
                            hintText: "e.g. room-101",
                            prefixIcon: Icon(Icons.meeting_room_outlined, color: AppTheme.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 28),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              final roomId = _roomController.text.trim();
                              if (roomId.isNotEmpty) {
                                SocketService().setRoomId(roomId);
                                widget.onComplete();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.brandOrangeDark,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: const Text("Launch SignConnect"),
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
