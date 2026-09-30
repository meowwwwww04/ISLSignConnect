import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'widgets/sidebar_nav.dart';
import 'screens/auth/login_screen.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'screens/onboarding/calibration_screen.dart';
import 'screens/onboarding/experience_screen.dart';
import 'screens/onboarding/room_join_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings_screen.dart';
import 'services/auth_service.dart';
import 'services/socket_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SignConnectApp());
}

class SignConnectApp extends StatelessWidget {
  const SignConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SignConnect ISL Translator',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const MainAppShell(),
    );
  }
}

class MainAppShell extends StatefulWidget {
  const MainAppShell({super.key});

  @override
  State<MainAppShell> createState() => _MainAppShellState();
}

class _MainAppShellState extends State<MainAppShell> {
  int _onboardingStep = -1; // -1: loading, 1: Login, 2: Welcome, 3: Calibration, 4: Experience, 5: RoomJoin, 0: MainApp
  String _activeRoute = "dashboard";

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final auth = AuthService();
      final result = await auth.restoreSession();
      if (result.success && result.account != null) {
        final socket = SocketService();
        socket.updateUserProfile(
          name: result.account!.name,
          email: result.account!.email,
          role: result.account!.role,
        );
        if (mounted) {
          setState(() {
            _onboardingStep = 0; // Skip to main app
          });
        }
        return;
      }
    } catch (e) {
      // Session restore failed, show login
    }
    if (mounted) {
      setState(() {
        _onboardingStep = 1; // Show login
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading screen while restoring session
    if (_onboardingStep == -1) {
      return const Scaffold(
        backgroundColor: Color(0xFF090D16),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF38BDF8)),
              SizedBox(height: 16),
              Text('SignConnect', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    // Show Onboarding & Auth flow first (Step 1 is LoginScreen)
    if (_onboardingStep > 0) {
      switch (_onboardingStep) {
        case 1:
          return LoginScreen(
            onLoginSuccess: () => setState(() => _onboardingStep = 2),
            onGuestAccess: () => setState(() => _onboardingStep = 5),
          );
        case 2:
          return WelcomeScreen(
            onNext: () => setState(() => _onboardingStep = 3),
          );
        case 3:
          return CalibrationScreen(
            onNext: () => setState(() => _onboardingStep = 4),
          );
        case 4:
          return ExperienceScreen(
            onNext: () => setState(() => _onboardingStep = 5),
            onBack: () => setState(() => _onboardingStep = 3),
          );
        case 5:
          return RoomJoinScreen(
            onComplete: () => setState(() => _onboardingStep = 0),
          );
      }
    }

    // Main App with Desktop Sidebar / Mobile Layout
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      body: Row(
        children: [
          if (isDesktop)
            SidebarNav(
              activeRoute: _activeRoute,
              onNavigate: (route) {
                if (route == "login") {
                  setState(() => _onboardingStep = 1);
                } else if (route == "calibration") {
                  setState(() => _onboardingStep = 3);
                } else if (route == "room_join") {
                  setState(() => _onboardingStep = 5);
                } else {
                  setState(() => _activeRoute = route);
                }
              },
            ),
          Expanded(
            child: _buildActiveScreen(),
          ),
        ],
      ),
      bottomNavigationBar: !isDesktop
          ? BottomNavigationBar(
              currentIndex: _activeRoute == "settings" ? 1 : 0,
              selectedItemColor: AppTheme.brandOrangeDark,
              unselectedItemColor: AppTheme.textMuted,
              onTap: (index) {
                setState(() {
                  _activeRoute = index == 1 ? "settings" : "dashboard";
                });
              },
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.grid_view_rounded),
                  label: "Dashboard",
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings_outlined),
                  label: "Settings",
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildActiveScreen() {
    switch (_activeRoute) {
      case "settings":
        return SettingsScreen(
          onLogout: () {
            setState(() {
              _onboardingStep = 1; // Go back to login
              _activeRoute = 'dashboard';
            });
          },
        );
      case "dashboard":
      default:
        return DashboardScreen(
          onNavigate: (route) {
            if (route == "login") {
              setState(() => _onboardingStep = 1);
            } else if (route == "calibration") {
              setState(() => _onboardingStep = 3);
            } else if (route == "room_join") {
              setState(() => _onboardingStep = 5);
            } else {
              setState(() => _activeRoute = route);
            }
          },
        );
    }
  }
}
