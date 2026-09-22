import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../widgets/step_indicator.dart';
import '../../widgets/permission_card.dart';
import '../../widgets/webcam_view.dart';

class CalibrationScreen extends StatefulWidget {
  final VoidCallback onNext;

  const CalibrationScreen({super.key, required this.onNext});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  bool _cameraGranted = true;
  bool _micGranted = true;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header Bar matching mockup 1
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
                  const StepIndicator(currentStep: 2, totalSteps: 4),
                ],
              ),
            ),
            const Divider(color: AppTheme.borderColor, height: 1),

            // Main Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: isDesktop
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildLeftContent()),
                              Container(width: 1, height: 520, color: AppTheme.borderColor),
                              Expanded(child: _buildRightContent()),
                            ],
                          )
                        : Column(
                            children: [
                              _buildLeftContent(),
                              const Divider(color: AppTheme.borderColor, height: 1),
                              _buildRightContent(),
                            ],
                          ),
                  ),
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text("? Support", style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.textMuted)),
                      const SizedBox(width: 16),
                      Text("🛡 Privacy", style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.textMuted)),
                    ],
                  ),
                  Text(
                    "© 2024 SignConnect AI. v1.0.4-beta",
                    style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftContent() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.bgCardSecondary,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: Text(
              "⚙ Hardware Calibration",
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Allow access to translate your motion.",
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "SignConnect requires real-time video processing to translate Indian Sign Language (ISL) into text and speech. Your data is processed locally for speed and privacy.",
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          PermissionCard(
            icon: Icons.videocam_outlined,
            title: "Camera Access",
            description: "Used to track hand gestures, finger articulation, and facial expressions essential for ISL syntax.",
            isGranted: _cameraGranted,
            onTap: () => setState(() => _cameraGranted = !_cameraGranted),
          ),
          const SizedBox(height: 12),
          PermissionCard(
            icon: Icons.mic_none_outlined,
            title: "Microphone Access",
            description: "Used for two-way communication, allowing you to hear translated speech from signers.",
            isGranted: _micGranted,
            onTap: () => setState(() => _micGranted = !_micGranted),
          ),
          const SizedBox(height: 28),

          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: widget.onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.brandOrangeDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text("Allow & Continue"),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                child: const Text("Learn More"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRightContent() {
    return Container(
      color: AppTheme.bgCardSecondary.withValues(alpha: 0.5),
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          // Camera Preview Mock Window matching design
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: const Color(0xFF2B2623),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                )
              ],
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: const WebcamView(),
                ),

                // Liveness badge
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.brandOrange,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "TESTING PASSIVE LIVENESS...",
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

                // Tracking Stats Overlay
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("FPS: 60.2", style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white70)),
                      Text("LATENCY: 12ms", style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white70)),
                      Text("TRACKING: OPTIMAL", style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppTheme.accentGreen)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Metrics row matching mockup 1 (98% confidence, 21 joint points, 4K resolution)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetricItem("98%", "CONFIDENCE"),
              Container(width: 1, height: 30, color: AppTheme.borderColor),
              _buildMetricItem("21", "JOINT POINTS"),
              Container(width: 1, height: 30, color: AppTheme.borderColor),
              _buildMetricItem("4K", "RESOLUTION"),
            ],
          ),

          const SizedBox(height: 24),
          Text(
            "Tip: Ensure you are in a well-lit environment and your hands are fully visible within the frame.",
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: AppTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.brandOrangeDark,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppTheme.textMuted,
          ),
        ),
      ],
    );
  }
}
