import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  final VoidCallback? onGuestAccess;

  const LoginScreen({
    super.key,
    required this.onLoginSuccess,
    this.onGuestAccess,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _isLoading = false;
  AppRole _selectedRole = AppRole.deaf;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleAuthentication() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final auth = AuthService();
    final socket = SocketService();
    AuthResult result;

    if (_isSignUp) {
      result = await auth.signUp(
        name: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
        role: _selectedRole,
      );
    } else {
      result = await auth.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
      // Keep role in sync with the account profile on sign-in.
      if (result.success && result.account != null) {
        _selectedRole = result.account!.role;
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!result.success) {
      setState(() => _errorMessage = result.message);
      return;
    }

    final account = result.account;
    socket.updateUserProfile(
      name: account?.name ?? "SignConnect User",
      email: account?.email ?? _emailController.text,
      role: account?.role ?? _selectedRole,
      micSensitivity: account?.micSensitivity,
      vocabularyFocus: account?.vocabularyFocus,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                result.message,
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.accentGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    widget.onLoginSuccess();
  }

  Future<void> _handleGuestSignIn() async {
    final socket = SocketService();
    final auth = AuthService();
    final result = await auth.signInGuest("", _selectedRole);
    if (result.success) {
      socket.updateUserProfile(
        name: result.account?.name ?? "Guest User",
        email: result.account?.email ?? "guest@signconnect.local",
        role: _selectedRole,
      );
    }
    if (widget.onGuestAccess != null) {
      widget.onGuestAccess!();
    } else {
      widget.onLoginSuccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Stack(
        children: [
          // Background Gradient Orbs
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.brandOrange.withValues(alpha: 0.15),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.brandOrange.withValues(alpha: 0.15),
                    blurRadius: 100,
                    spreadRadius: 50,
                  )
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueAccent.withValues(alpha: 0.12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent.withValues(alpha: 0.12),
                    blurRadius: 120,
                    spreadRadius: 60,
                  )
                ],
              ),
            ),
          ),

          // Main Center Card Container
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                constraints: BoxConstraints(maxWidth: isDesktop ? 960 : 480),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.borderColor),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 30,
                      offset: Offset(0, 10),
                    )
                  ],
                ),
                child: isDesktop
                    ? Row(
                        children: [
                          Expanded(child: _buildBrandingSide(context)),
                          Container(width: 1, height: 520, color: AppTheme.borderColor),
                          Expanded(child: _buildFormSide(context)),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildBrandingSide(context, compact: true),
                          const Divider(color: AppTheme.borderColor, height: 1),
                          _buildFormSide(context),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandingSide(BuildContext context, {bool compact = false}) {
    return Padding(
      padding: EdgeInsets.all(compact ? 24 : 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/images/app_logo.png',
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.brandOrange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.brandOrange.withValues(alpha: 0.5)),
                    ),
                    child: const Text("🤟", style: TextStyle(fontSize: 24)),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "SignConnect",
                    style: GoogleFonts.outfit(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    "AI ISL TRANSLATOR",
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: AppTheme.brandOrange,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            "Empowering Seamless Two-Way Communication",
            style: GoogleFonts.outfit(
              fontSize: compact ? 20 : 24,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Connect instantly with MediaPipe 21-joint sign language recognition, WebRTC 2-way calling, and real-time speech translation.",
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 32),
            _buildFeatureBullet(Icons.camera_front, "MediaPipe Hand Landmark Tracking"),
            const SizedBox(height: 12),
            _buildFeatureBullet(Icons.subtitles, "Live Speech-to-Text Subtitles"),
            const SizedBox(height: 12),
            _buildFeatureBullet(Icons.video_call_outlined, "Seamless WebRTC Call Engine"),
          ],
        ],
      ),
    );
  }

  Widget _buildFeatureBullet(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.accentGreen),
        const SizedBox(width: 10),
        Text(
          text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildFormSide(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mode Header (Sign In vs Register)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isSignUp ? "Create Account" : "Welcome Back",
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isSignUp = !_isSignUp;
                      _errorMessage = null;
                    });
                  },
                  child: Text(
                    _isSignUp ? "Sign In" : "Sign Up",
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.brandOrange,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              _isSignUp ? "Fill in your details to register" : "Enter your email and password to sign in",
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 20),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),

            // Mode Preference Selection (Deaf vs Hearing)
            Text(
              "PRIMARY APP ROLE",
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildRoleSelectChip(
                    role: AppRole.deaf,
                    title: "Deaf Mode",
                    emoji: "🤟",
                    activeColor: AppTheme.accentGreen,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildRoleSelectChip(
                    role: AppRole.hearing,
                    title: "Hearing Mode",
                    emoji: "🎙️",
                    activeColor: Colors.blueAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Name Input (Only on Sign Up)
            if (_isSignUp) ...[
              TextFormField(
                controller: _nameController,
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
                decoration: _inputDecoration(
                  label: "Full Name",
                  hint: "Enter your name",
                  icon: Icons.person_outline,
                ),
                validator: (val) {
                  if (_isSignUp && (val == null || val.trim().isEmpty)) {
                    return "Please enter your name";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
            ],

            // Email Input
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
              decoration: _inputDecoration(
                label: "Email Address",
                hint: "user@signconnect.org",
                icon: Icons.email_outlined,
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return "Email is required";
                if (!val.contains("@") || !val.contains(".")) return "Enter a valid email address";
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Password Input
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
              decoration: _inputDecoration(
                label: "Password",
                hint: "••••••••",
                icon: Icons.lock_outline,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: AppTheme.textMuted,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
              ),
              validator: (val) {
                if (val == null || val.isEmpty) return "Password is required";
                if (val.length < 6) return "Password must be at least 6 characters";
                return null;
              },
            ),

            const SizedBox(height: 24),

            // Primary Action Button (Sign In / Register)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleAuthentication,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.brandOrange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isSignUp ? "Create Account" : "Sign In",
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 14),

            // Guest Fast Access Button
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: _handleGuestSignIn,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.borderColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.flash_on_outlined, size: 16, color: AppTheme.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      "Continue as Guest",
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleSelectChip({
    required AppRole role,
    required String title,
    required String emoji,
    required Color activeColor,
  }) {
    final isSelected = _selectedRole == role;

    return InkWell(
      onTap: () => setState(() => _selectedRole = role),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.15) : AppTheme.bgCardSecondary,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? activeColor : AppTheme.borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: AppTheme.textMuted, size: 20),
      suffixIcon: suffixIcon,
      labelStyle: GoogleFonts.plusJakartaSans(color: AppTheme.textMuted, fontSize: 13),
      hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 13),
      filled: true,
      fillColor: AppTheme.bgDark,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.brandOrange, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }
}
