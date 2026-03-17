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
import 'screens/caregiver/verification_screen.dart';
import 'screens/client/my_bookings_screen.dart';
import 'theme/garden_theme.dart';

// ── Compatibilidad con sistema anterior (Legacy Constants) ──
const kBackgroundColor = GardenColors.background;
const kSurfaceColor    = GardenColors.surface;
const kPrimaryColor    = GardenColors.primary;
const kAccentColor     = GardenColors.accent;
const kTextPrimary     = GardenColors.textPrimary;
const kTextSecondary   = GardenColors.textSecondary;

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
      path: '/caregiver/verification',
      name: 'caregiverVerification',
      builder: (context, state) => const VerificationScreen(),
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
    GoRoute(
      path: '/my-bookings',
      name: 'myBookings',
      builder: (context, state) => const MyBookingsScreen(),
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
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        return MaterialApp.router(
          title: 'GARDEN',
          debugShowCheckedModeBanner: false,
          routerConfig: _router,
          theme: gardenTheme(dark: themeNotifier.isDark),
        );
      },
    );
  }
}
