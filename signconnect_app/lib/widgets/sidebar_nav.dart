import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class SidebarNav extends StatelessWidget {
  final String activeRoute;
  final Function(String) onNavigate;

  const SidebarNav({
    super.key,
    required this.activeRoute,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: AppTheme.bgCardSecondary,
        border: Border(
          right: BorderSide(color: AppTheme.borderColor, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo Header
          Row(
            children: [
              Text(
                "SignConnect",
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.brandOrangeDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "AI TRANSLATOR",
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMuted,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 36),

          // Nav Items
          _buildNavItem(context, Icons.grid_view_rounded, "Dashboard", "dashboard"),
          _buildNavItem(context, Icons.videocam_outlined, "Hardware", "hardware"),
          _buildNavItem(context, Icons.menu_book_outlined, "Vocabulary", "vocabulary"),
          _buildNavItem(context, Icons.school_outlined, "Tutorials", "tutorials"),
          _buildNavItem(context, Icons.settings_outlined, "Settings", "settings"),

          const Spacer(),

          // Start Calibration Action Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => onNavigate("calibration"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brandOrangeDark,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text("Start Calibration"),
            ),
          ),

          const SizedBox(height: 24),
          const Divider(color: AppTheme.borderColor),
          const SizedBox(height: 12),

          // Footer Links
          _buildFooterItem(context, Icons.help_outline, "Support"),
          const SizedBox(height: 8),
          _buildFooterItem(context, Icons.person_outline, "Account"),
        ],
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, IconData icon, String label, String route) {
    final bool isActive = activeRoute == route;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () {
            if (route == "hardware" || route == "settings") {
              onNavigate("settings");
            } else if (route == "vocabulary") {
              _showVocabularyModal(context);
            } else if (route == "tutorials") {
              _showTutorialsModal(context);
            } else {
              onNavigate("dashboard");
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isActive ? AppTheme.bgCard : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: isActive ? Border.all(color: AppTheme.borderColor) : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isActive ? AppTheme.brandOrangeDark : AppTheme.textSecondary,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? AppTheme.brandOrangeDark : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooterItem(BuildContext context, IconData icon, String label) {
    return InkWell(
      onTap: () {
        if (label == "Support") {
          _showSupportModal(context);
        } else {
          _showAccountModal(context);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.textMuted),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVocabularyModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("ISL Dictionary & Vocabulary", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Supported ISL gestures include:", style: GoogleFonts.plusJakartaSans(fontSize: 13)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ["Namaste", "House", "Book", "Help", "Time", "Food", "Water", "Love", "Yes", "No"]
                  .map((word) => Chip(
                        label: Text(word),
                        backgroundColor: AppTheme.brandOrangeLight,
                        labelStyle: const TextStyle(color: AppTheme.brandOrangeDark, fontWeight: FontWeight.bold),
                      ))
                  .toList(),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          )
        ],
      ),
    );
  }

  void _showTutorialsModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Interactive Tutorials", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          "1. Ensure high lighting in your room.\n2. Position your hands centered within the green tracking frame.\n3. Hold gestures steady for 0.5s for instant recognition.",
          style: GoogleFonts.plusJakartaSans(fontSize: 13, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Got It"),
          )
        ],
      ),
    );
  }

  void _showSupportModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Support & Help Desk", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          "For technical assistance or ISL dictionary additions, contact the SignConnect Team G4 support line:\n\nEmail: support@signconnect.org\nVersion: v1.0.4-beta",
          style: GoogleFonts.plusJakartaSans(fontSize: 13, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          )
        ],
      ),
    );
  }

  void _showAccountModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("User Profile Account", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          "User: SignConnect Member\nRole: Deaf User Mode Active\nStatus: Connected to Room",
          style: GoogleFonts.plusJakartaSans(fontSize: 13, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Done"),
          )
        ],
      ),
    );
  }
}
