import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../widgets/step_indicator.dart';
import '../../widgets/experience_card.dart';
import '../../services/socket_service.dart';

class ExperienceScreen extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  const ExperienceScreen({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<ExperienceScreen> createState() => _ExperienceScreenState();
}

class _ExperienceScreenState extends State<ExperienceScreen> {
  AppRole _selectedRole = AppRole.deaf;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header matching mockup 2
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "SignConnect",
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.brandOrangeDark,
                    ),
                  ),
                  const StepIndicator(currentStep: 3, totalSteps: 4),
                ],
              ),
            ),
            const Divider(color: AppTheme.borderColor, height: 1),

            // Content Body matching mockup 2 layout exactly
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Choose your\ntranslation experience.",
                          style: GoogleFonts.outfit(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.brandOrangeDark,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Select how you'll primarily use SignConnect. You can change this later in settings.",
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Card 1: Deaf Mode
                        ExperienceCard(
                          icon: const Text("🖐", style: TextStyle(fontSize: 24)),
                          title: "I am Deaf / Hard of Hearing",
                          description: "AI translates speech into sign-language clips in real-time.",
                          isSelected: _selectedRole == AppRole.deaf,
                          onTap: () => setState(() => _selectedRole = AppRole.deaf),
                        ),

                        const SizedBox(height: 16),

                        // Card 2: Hearing Mode
                        ExperienceCard(
                          icon: const Icon(Icons.mic_none_outlined, size: 26, color: AppTheme.textPrimary),
                          title: "I am a Hearing User",
                          description: "AI translates signs into high-accuracy live transcriptions.",
                          isSelected: _selectedRole == AppRole.hearing,
                          onTap: () => setState(() => _selectedRole = AppRole.hearing),
                        ),

                        const SizedBox(height: 24),

                        // Info banner box matching mockup 2
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFAF2E6),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFEADBCE)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline, size: 20, color: AppTheme.textSecondary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  "SignConnect adapts its interface based on your choice. Deaf users get optimized visual sign-clips, while hearing users see a live captioning dashboard.",
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Continue CTA
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              SocketService().setRole(_selectedRole);
                              widget.onNext();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.brandOrangeDark,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: const Text("Continue"),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Back Link
                        Center(
                          child: TextButton(
                            onPressed: widget.onBack,
                            child: Text(
                              "Go back to calibration",
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                                decoration: TextDecoration.underline,
                              ),
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
