import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/team_card.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onLogout;

  const SettingsScreen({super.key, this.onLogout});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SocketService _socket = SocketService();
  final AuthService _auth = AuthService();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();
  final _bioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAccountIntoControllers();
  }

  void _loadAccountIntoControllers() {
    final account = _auth.currentAccount;
    _nameController.text = account?.name ?? _socket.userName;
    _emailController.text = account?.email ?? _socket.userEmail;
    _phoneController.text = account?.phone ?? "";
    _locationController.text = account?.location ?? "";
    _bioController.text = account?.bio ?? "";
  }

  Future<void> _saveProfileEdits({AppRole? newRole}) async {
    final updated = await _auth.updateProfile(
      name: _nameController.text,
      email: _emailController.text,
      phone: _phoneController.text,
      location: _locationController.text,
      bio: _bioController.text,
      role: newRole,
      micSensitivity: _socket.micSensitivity,
      vocabularyFocus: _socket.vocabularyFocus,
    );
    if (!mounted) return;
    if (updated != null) {
      _socket.updateUserProfile(
        name: updated.name,
        email: updated.email,
        role: updated.role,
        micSensitivity: updated.micSensitivity,
        vocabularyFocus: updated.vocabularyFocus,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Profile saved for ${updated.name}"),
          backgroundColor: AppTheme.accentGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sign in to save profile changes.")),
      );
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Log out?", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          "You will need to sign in again to access your account.",
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Log Out"),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AuthService().signOut();
      if (widget.onLogout != null) widget.onLogout!();
    }
  }

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

                      // Section 0: My Account (editable profile)
                      _buildAccountSection(),

                      const SizedBox(height: 40),

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

  Widget _buildAccountSection() {
    final account = _auth.currentAccount;
    final name = account?.name ?? "Guest User";
    final email = account?.email ?? "guest@signconnect.local";
    final initials = name.trim().split(RegExp(r'\s+')).map((w) => w[0]).take(2).join().toUpperCase();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.brandOrange.withValues(alpha: 0.12),
            AppTheme.bgCard,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.brandOrange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_circle_outlined, color: AppTheme.brandOrange, size: 20),
              const SizedBox(width: 8),
              Text(
                "My Account",
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _showEditAccountSheet,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text("Edit"),
                style: TextButton.styleFrom(foregroundColor: AppTheme.brandOrangeDark),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppTheme.brandOrangeLight,
                child: Text(
                  initials,
                  style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.brandOrangeDark),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    Text(email, style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: AppTheme.textSecondary)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _accountMetaChip(
                          icon: account?.role == AppRole.hearing ? Icons.hearing : Icons.sign_language,
                          label: (account?.role ?? _socket.currentRole) == AppRole.deaf ? "Deaf Mode" : "Hearing Mode",
                        ),
                        if ((account?.phone ?? "").isNotEmpty)
                          _accountMetaChip(icon: Icons.phone_outlined, label: account!.phone!),
                        if ((account?.location ?? "").isNotEmpty)
                          _accountMetaChip(icon: Icons.location_on_outlined, label: account!.location!),
                      ],
                    ),
                    if ((account?.bio ?? "").isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(account!.bio!, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.textSecondary)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _confirmLogout,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: const Icon(Icons.logout, size: 18, color: Colors.redAccent),
              label: Text("Log Out", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: Colors.redAccent)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountMetaChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.bgCardSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.brandOrangeDark),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  void _showEditAccountSheet() {
    _loadAccountIntoControllers();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 720),
            decoration: const BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Edit Account Details", style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  Text(
                    "Update your personal details. Changes are saved to your account on this device.",
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: "Full Name", prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: "Email Address", prefixIcon: Icon(Icons.email_outlined)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: "Phone (optional)", prefixIcon: Icon(Icons.phone_outlined)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _locationController,
                    decoration: const InputDecoration(labelText: "City / Location (optional)", prefixIcon: Icon(Icons.location_on_outlined)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bioController,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: "About Me (optional)", prefixIcon: Icon(Icons.info_outline)),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _saveProfileEdits();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.brandOrangeDark,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: Text("Save Changes", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
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
                activeThumbColor: AppTheme.brandOrangeDark,
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
