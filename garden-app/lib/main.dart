import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/caregiver/onboarding_wizard_screen.dart';
import 'screens/test_agentes_screen.dart';
import 'screens/client/marketplace_screen.dart';
import 'screens/admin/admin_panel_screen.dart';
import 'screens/client/my_pets_screen.dart';
import 'screens/client/caregiver_profile_screen.dart';
import 'screens/client/booking_screen.dart';
import 'screens/client/payment_screen.dart';
import 'screens/caregiver/caregiver_home_screen.dart';

// ── Paleta oficial GARDEN ──────────────────────────────────
const kBackgroundColor = Color(0xFF0A0E1A);
const kSurfaceColor    = Color(0xFF1A1F2E);
const kPrimaryColor    = Color(0xFF4F8EF7);
const kAccentColor     = Color(0xFFFF6B35);
const kTextPrimary     = Colors.white;
const kTextSecondary   = Color(0xFFB0B8C8);

// ── Router ─────────────────────────────────────────────────
final GoRouter _router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/test',
      name: 'test',
      builder: (context, state) => const TestAgentesScreen(),
    ),
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      name: 'register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/caregiver/onboarding',
      name: 'caregiverOnboarding',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return OnboardingWizardScreen(
          initialEmail: extra['email'] as String? ?? '',
          initialPassword: extra['password'] as String? ?? '',
        );
      },
    ),
    GoRoute(
      path: '/marketplace',
      name: 'marketplace',
      builder: (context, state) => const MarketplaceScreen(),
    ),
    GoRoute(
      path: '/admin',
      name: 'admin',
      builder: (context, state) => const AdminPanelScreen(),
    ),
    GoRoute(
      path: '/my-pets',
      name: 'myPets',
      builder: (context, state) => const MyPetsScreen(),
    ),
    GoRoute(
      path: '/caregiver/home',
      name: 'caregiverHome',
      builder: (context, state) => const CaregiverHomeScreen(),
    ),
    GoRoute(
      path: '/caregiver/:id',
      name: 'caregiverProfile',
      builder: (context, state) => CaregiverProfileScreen(
        caregiverId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/booking/:caregiverId',
      name: 'booking',
      builder: (context, state) => BookingScreen(
        caregiverId: state.pathParameters['caregiverId']!,
      ),
    ),
    GoRoute(
      path: '/payment/:bookingId',
      name: 'payment',
      builder: (context, state) => PaymentScreen(
        bookingId: state.pathParameters['bookingId']!,
      ),
    ),

  ],
);

// ── App Entry Point ────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GardenApp());
}

class GardenApp extends StatelessWidget {
  const GardenApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'GARDEN',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: kPrimaryColor,
        scaffoldBackgroundColor: kBackgroundColor,
        colorScheme: const ColorScheme.dark(
          primary: kPrimaryColor,
          secondary: kAccentColor,
          surface: kSurfaceColor,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: kTextPrimary,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kSurfaceColor,
          foregroundColor: kTextPrimary,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimaryColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white),
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withOpacity(0.08),
          hintStyle: const TextStyle(color: kTextSecondary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}
