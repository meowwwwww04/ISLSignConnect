import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/team_card.dart';
import '../services/socket_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SocketService _socket = SocketService();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _socket,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header matching Mockup 3
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "App Settings & About",
                                style: GoogleFonts.outfit(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Configure your hardware and learn about the mission.",
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.help_outline, color: AppTheme.textSecondary),
                                onPressed: () {},
                              ),
                              const SizedBox(width: 8),
                              const CircleAvatar(
                                radius: 18,
                                backgroundColor: AppTheme.brandOrangeLight,
                                child: Icon(Icons.person, color: AppTheme.brandOrange, size: 20),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),

                      // Section 1: Hardware & Preferences
                      Row(
                        children: [
                          const Icon(Icons.sensors, color: AppTheme.brandOrange, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            "Hardware & Preferences",
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Hardware Section Box
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.borderColor),
                        ),
                        child: Column(
                          children: [
                            // Row 1: Camera Status & Mic Sensitivity
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isWide = constraints.maxWidth > 700;
                                return isWide
                                    ? Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(child: _buildCameraCard()),
                                          const SizedBox(width: 20),
                                          Expanded(child: _buildMicSensitivityCard()),
                                        ],
                                      )
                                    : Column(
                                        children: [
                                          _buildCameraCard(),
                                          const SizedBox(height: 16),
                                          _buildMicSensitivityCard(),
                                        ],
                                      );
                              },
                            ),

                            const SizedBox(height: 24),
                            const Divider(color: AppTheme.borderColor),
                            const SizedBox(height: 24),

                            // Row 2: Vocabulary Focus matching mockup 3
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Vocabulary Focus",
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Tailor the AI model to recognize domain-specific terminology.",
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 10,
                                  children: [
                                    _buildVocabChip("Medical", Icons.medical_services_outlined),
                                    _buildVocabChip("Daily", Icons.wb_sunny_outlined),
                                    _buildVocabChip("Emergency", Icons.flare_outlined),
                                    _buildVocabChip("Professional", Icons.work_outline),
                                  ],
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),
                            const Divider(color: AppTheme.borderColor),
                            const SizedBox(height: 20),

                            // Badges Row at bottom of hardware section
                            Wrap(
                              spacing: 24,
                              runSpacing: 12,
                              children: [
                                _buildStatusBadge(
                                  Icons.check_circle_outline,
                                  "Standard ASL V4.2",
                                  "Core dictionary loaded.",
                                  AppTheme.accentGreen,
                                ),
                                _buildStatusBadge(
                                  Icons.file_download_outlined,
                                  "Medical Extension",
                                  "82% downloaded (2.4 GB)",
                                  AppTheme.brandOrange,
                                ),
                                _buildStatusBadge(
                                  Icons.lock_outline,
                                  "Local Storage Only",
                                  "Privacy-first processing.",
                                  AppTheme.textSecondary,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Section 2: About the Project matching Mockup 3
                      Row(
                        children: [
                          Text(
                            "About the Project",
                            style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 800;
                          return isWide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 2, child: _buildAboutTextColumn()),
                                    const SizedBox(width: 20),
                                    Expanded(
                                      flex: 3,
                                      child: Row(
                                        children: [
                                          Expanded(child: _buildTeamG4Card()),
                                          const SizedBox(width: 16),
                                          Expanded(child: _buildMentorCard()),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _buildAboutTextColumn(),
                                    const SizedBox(height: 24),
                                    _buildTeamG4Card(),
                                    const SizedBox(height: 16),
                                    _buildMentorCard(),
                                  ],
                                );
                        },
                      ),

                      const SizedBox(height: 48),
                      const Divider(color: AppTheme.borderColor),
                      const SizedBox(height: 16),

                      // Footer text matching mockup 3
                      Center(
                        child: Text(
                          "© 2024 SIGNCONNECT SYSTEMS • MADE WITH ❤ FOR ACCESSIBILITY   |   PRIVACY POLICY   TERMS OF SERVICE   SYSTEM STATUS: OPTIMAL",
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                            letterSpacing: 0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCameraCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCardSecondary,
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
                "Camera Status",
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              Switch(
                value: _socket.isCameraEnabled,
                activeColor: AppTheme.brandOrangeDark,
                onChanged: (val) => _socket.toggleCamera(val),
              ),
            ],
          ),
          Text(
            "Enable real-time gesture tracking using your primary device camera.",
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: Row(
              children: [
                const Icon(Icons.videocam_outlined, color: AppTheme.textSecondary, size: 20),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "ACTIVE DEVICE",
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    Text(
                      "Logitech StreamCam 1080p",
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMicSensitivityCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCardSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mic_none_outlined, color: AppTheme.brandOrange, size: 18),
              const SizedBox(width: 8),
              Text(
                "Microphone Sensitivity",
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Slider(
            value: _socket.micSensitivity,
            activeColor: AppTheme.brandOrangeDark,
            inactiveColor: AppTheme.borderColor,
            onChanged: (val) => _socket.setMicSensitivity(val),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("MIN", style: GoogleFonts.jetBrainsMono(fontSize: 9, color: AppTheme.textMuted)),
              Text(
                "${(_socket.micSensitivity * 100).toInt()}% OPTIMAL",
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.brandOrangeDark,
                ),
              ),
              Text("MAX", style: GoogleFonts.jetBrainsMono(fontSize: 9, color: AppTheme.textMuted)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "Determines when the AI should listen for audio prompts to complement sign detection.",
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVocabChip(String label, IconData icon) {
    final isSelected = _socket.vocabularyFocus == label;
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected ? Colors.white : AppTheme.textPrimary,
      ),
      label: Text(label),
      selected: isSelected,
      selectedColor: AppTheme.brandOrangeDark,
      backgroundColor: AppTheme.bgCardSecondary,
      labelStyle: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: isSelected ? Colors.white : AppTheme.textPrimary,
      ),
      onSelected: (val) {
        if (val) _socket.setVocabularyFocus(label);
      },
    );
  }

  Widget _buildStatusBadge(IconData icon, String title, String subtitle, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAboutTextColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "SignConnect was born from the vision of bridge-building between the hearing and Deaf communities. Leveraging state-of-the-art neural networks, our platform provides millisecond-latency translation that preserves the nuance, emotion, and speed of natural conversation.",
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: AppTheme.textSecondary,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Text("VERSION  ", style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.textMuted)),
            Text("1.0.4-beta", style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text("LICENSE  ", style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.textMuted)),
            Text("Proprietary", style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          ],
        ),
      ],
    );
  }

  Widget _buildTeamG4Card() {
    return TeamCard(
      title: "Team G4",
      subtitle: "DEVELOPMENT & VISION",
      description: "Responsible for the core engine, UI/UX architecture, and real-time data processing pipelines.",
      avatarWidget: Container(
        color: AppTheme.bgCardSecondary,
        child: const Icon(Icons.groups_outlined, size: 36, color: AppTheme.brandOrange),
      ),
    );
  }

  Widget _buildMentorCard() {
    return TeamCard(
      title: "Ms. Shubhangi Nagpure",
      subtitle: "PROJECT LEAD & MENTOR",
      description: "Guiding the academic and ethical framework of SignConnect, ensuring accessibility and accuracy.",
      avatarWidget: Container(
        color: AppTheme.bgCardSecondary,
        child: const Icon(Icons.person_outline, size: 36, color: AppTheme.brandOrange),
      ),
    );
  }
}
