import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'widgets/sidebar_nav.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'screens/onboarding/calibration_screen.dart';
import 'screens/onboarding/experience_screen.dart';
import 'screens/onboarding/room_join_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings_screen.dart';

void main() {
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
  int _onboardingStep = 1; // 1: Welcome, 2: Calibration, 3: Experience, 4: RoomJoin, 0: MainApp
  String _activeRoute = "dashboard";

  @override
  Widget build(BuildContext context) {
    // Show Onboarding flow first
    if (_onboardingStep > 0) {
      switch (_onboardingStep) {
        case 1:
          return WelcomeScreen(
            onNext: () => setState(() => _onboardingStep = 2),
          );
        case 2:
          return CalibrationScreen(
            onNext: () => setState(() => _onboardingStep = 3),
          );
        case 3:
          return ExperienceScreen(
            onNext: () => setState(() => _onboardingStep = 4),
            onBack: () => setState(() => _onboardingStep = 2),
          );
        case 4:
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
                if (route == "calibration") {
                  setState(() => _onboardingStep = 2);
                } else if (route == "room_join") {
                  setState(() => _onboardingStep = 4);
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
        return const SettingsScreen();
      case "dashboard":
      default:
        return DashboardScreen(
          onNavigate: (route) {
            if (route == "calibration") {
              setState(() => _onboardingStep = 2);
            } else if (route == "room_join") {
              setState(() => _onboardingStep = 4);
            } else {
              setState(() => _activeRoute = route);
            }
          },
        );
    }
  }
}
