import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/socket_service.dart';

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
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/images/app_logo.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.brandOrangeLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text("🤟", style: TextStyle(fontSize: 18)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
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
    final socket = SocketService();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.brandOrange,
              radius: 20,
              child: Text(
                socket.userName.isNotEmpty ? socket.userName[0].toUpperCase() : "U",
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(socket.userName, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text(socket.userEmail, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textMuted)),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(),
            const SizedBox(height: 8),
            _profileDetailRow("Active Mode", socket.currentRole == AppRole.deaf ? "🤟 Deaf Mode (MediaPipe)" : "🎙️ Hearing Mode (Speech STT)"),
            const SizedBox(height: 8),
            _profileDetailRow("Room Code", socket.currentRoomId),
            const SizedBox(height: 8),
            _profileDetailRow("Vocabulary", socket.vocabularyFocus),
            const SizedBox(height: 8),
            _profileDetailRow("Mic Sensitivity", "${(socket.micSensitivity * 100).toInt()}%"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onNavigate("login");
            },
            child: const Text("Sign Out", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              _showEditProfileDialog(context);
            },
            child: const Text("Edit Profile"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Done"),
          )
        ],
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context) {
    final socket = SocketService();
    final nameController = TextEditingController(text: socket.userName);
    final emailController = TextEditingController(text: socket.userEmail);
    AppRole editRole = socket.currentRole;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text("Edit Account Profile", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: "Full Name", prefixIcon: Icon(Icons.person)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: "Email Address", prefixIcon: Icon(Icons.email)),
                    ),
                    const SizedBox(height: 16),
                    Text("Role Preference", style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppTheme.textMuted)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text("🤟 Deaf Mode"),
                          selected: editRole == AppRole.deaf,
                          onSelected: (val) => setModalState(() => editRole = AppRole.deaf),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text("🎙️ Hearing Mode"),
                          selected: editRole == AppRole.hearing,
                          onSelected: (val) => setModalState(() => editRole = AppRole.hearing),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    socket.updateUserProfile(
                      name: nameController.text,
                      email: emailController.text,
                      role: editRole,
                    );
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Account Profile updated successfully!")),
                    );
                  },
                  child: const Text("Save Changes"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _profileDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textMuted)),
        Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
