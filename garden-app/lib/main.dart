import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/client/client_welcome_screen.dart';
import 'screens/client/landing_screen.dart';
import 'screens/caregiver/onboarding_wizard_screen.dart';
import 'screens/test_agentes_screen.dart';
import 'screens/client/marketplace_screen.dart';
import 'screens/admin/admin_panel_screen.dart';
import 'screens/admin/admin_identity_review_screen.dart';
import 'screens/admin/admin_reservation_detail_screen.dart';
import 'screens/client/my_pets_screen.dart';
import 'screens/client/caregiver_profile_screen.dart';
import 'screens/client/booking_screen.dart';
import 'screens/client/payment_screen.dart';
import 'screens/client/booking_confirmed_screen.dart';
import 'screens/caregiver/caregiver_home_screen.dart';
import 'screens/caregiver/verification_screen.dart';
import 'screens/caregiver/caregiver_edit_profile_screen.dart';
import 'screens/client/my_bookings_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/caregiver/caregiver_profile_data_screen.dart';
import 'screens/caregiver/caregiver_setup_flow_screen.dart';
import 'screens/wallet/wallet_screen.dart';
import 'screens/service/service_execution_screen.dart';
import 'screens/service/meet_and_greet_screen.dart';
import 'screens/service/gps_tracking_screen.dart';
import 'screens/dispute/dispute_screen.dart';
import 'screens/client/favorites_screen.dart';
import 'screens/client/client_shell_screen.dart';
import 'screens/onboarding/mobile_splash_screen.dart';
import 'screens/onboarding/mobile_onboarding_screen.dart';
import 'screens/onboarding/mobile_service_selector_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'theme/garden_theme.dart';

// ── Compatibilidad con sistema anterior (Legacy Constants) ──
const kBackgroundColor = GardenColors.background;
const kSurfaceColor    = GardenColors.surface;
const kPrimaryColor    = GardenColors.primary;
const kAccentColor     = GardenColors.accent;
const kTextPrimary     = GardenColors.textPrimary;
const kTextSecondary   = GardenColors.textSecondary;

// ── Mobile Auth Gate ───────────────────────────────────────
// En móvil, verifica sesión guardada y redirige al home correcto.
// En web, se usa la LandingScreen normal.
class _MobileAuthGate extends StatefulWidget {
  const _MobileAuthGate();
  @override
  State<_MobileAuthGate> createState() => _MobileAuthGateState();
}

class _MobileAuthGateState extends State<_MobileAuthGate> {
  @override
  void initState() {
    super.initState();
    // Esperar a que el árbol de widgets esté listo antes de navegar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/splash');
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: GardenColors.background,
      body: Center(child: CircularProgressIndicator(color: GardenColors.primary, strokeWidth: 2)),
    );
  }
}

// ── Router ─────────────────────────────────────────────────
final GoRouter _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'landing',
      builder: (context, state) =>
          kIsWeb ? const LandingScreen() : const _MobileAuthGate(),
    ),
    GoRoute(
      path: '/splash',
      name: 'splash',
      builder: (context, state) => const MobileSplashScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      name: 'onboarding',
      builder: (context, state) => const MobileOnboardingScreen(),
    ),
    GoRoute(
      path: '/service-selector',
      name: 'serviceSelector',
      builder: (context, state) => const MobileServiceSelectorScreen(),
    ),
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
          resumeMode: extra['resumeMode'] as bool? ?? false,
        );
      },
    ),
    GoRoute(
      path: '/client-welcome',
      name: 'clientWelcome',
      builder: (context, state) => const ClientWelcomeScreen(),
    ),
    GoRoute(
      path: '/marketplace',
      name: 'marketplace',
      builder: (context, state) {
        final q = state.uri.queryParameters;
        if (!kIsWeb) {
          return ClientShellScreen(
            initialTab: 0,
            initialService: q['service'],
          );
        }
        return MarketplaceScreen(
          initialService: q['service'],
          initialZone: q['zone'],
          initialSize: q['size'],
        );
      },
    ),
    GoRoute(
      path: '/my-bookings-tab',
      name: 'myBookingsTab',
      builder: (context, state) =>
          kIsWeb ? const MyBookingsScreen() : const ClientShellScreen(initialTab: 1),
    ),
    GoRoute(
      path: '/my-pets-tab',
      name: 'myPetsTab',
      builder: (context, state) =>
          kIsWeb ? const MyPetsScreen() : const ClientShellScreen(initialTab: 2),
    ),
    GoRoute(
      path: '/admin',
      name: 'admin',
      builder: (context, state) => const AdminPanelScreen(),
    ),
    GoRoute(
      path: '/admin/identity-reviews/:id',
      name: 'adminIdentityReview',
      builder: (context, state) => AdminIdentityReviewScreen(
        sessionId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/admin/reservations/:id',
      name: 'adminReservationDetail',
      builder: (context, state) => AdminReservationDetailScreen(
        bookingId: state.pathParameters['id']!,
      ),
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
      path: '/caregiver/setup',
      name: 'caregiverSetup',
      builder: (context, state) => const CaregiverSetupFlowScreen(),
    ),
    GoRoute(
      path: '/caregiver/verification',
      name: 'caregiverVerification',
      builder: (context, state) => const VerificationScreen(),
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
      path: '/booking-confirmed/:bookingId',
      name: 'bookingConfirmed',
      builder: (context, state) {
        final bookingId = state.pathParameters['bookingId']!;
        final extra = state.extra as Map<String, dynamic>?;
        return BookingConfirmedScreen(
          bookingId: bookingId,
          bookingData: extra,
        );
      },
    ),
    GoRoute(
      path: '/wallet',
      name: 'wallet',
      builder: (context, state) => const WalletScreen(),
    ),
    GoRoute(
      path: '/my-bookings',
      name: 'myBookings',
      builder: (context, state) => const MyBookingsScreen(),
    ),

    GoRoute(
      path: '/profile',
      name: 'profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/chat/:bookingId',
      name: 'chat',
      builder: (context, state) {
        final bookingId = state.pathParameters['bookingId']!;
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return ChatScreen(
          bookingId: bookingId,
          otherPersonName: extra['otherPersonName'] as String? ?? 'Usuario',
          otherPersonPhoto: extra['otherPersonPhoto'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/caregiver/edit-profile',
      name: 'caregiverEditProfile',
      builder: (context, state) => const CaregiverEditProfileScreen(),
    ),
    GoRoute(
      path: '/caregiver/profile-data',
      name: 'caregiverProfileData',
      builder: (context, state) => const CaregiverProfileDataScreen(),
    ),
    GoRoute(
      path: '/caregiver/:id',
      name: 'caregiverProfile',
      builder: (context, state) => CaregiverProfileScreen(
        caregiverId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/service/:bookingId',
      name: 'serviceExecution',
      builder: (context, state) {
        final bookingId = state.pathParameters['bookingId']!;
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return ServiceExecutionScreen(
          bookingId: bookingId,
          role: extra['role'] as String? ?? 'CLIENT',
          token: extra['token'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/favorites',
      name: 'favorites',
      builder: (context, state) => const FavoritesScreen(),
    ),
    GoRoute(
      path: '/dispute/:bookingId',
      name: 'dispute',
      builder: (context, state) {
        final bookingId = state.pathParameters['bookingId']!;
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return DisputeScreen(
          bookingId: bookingId,
          role: extra['role'] as String? ?? 'CLIENT',
          clientReasons: (extra['clientReasons'] as List?)?.cast<String>(),
        );
      },
    ),
    GoRoute(
      path: '/meet-and-greet/:bookingId',
      name: 'meetAndGreet',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return MeetAndGreetScreen(
          bookingId: state.pathParameters['bookingId']!,
          role: extra['role'] as String? ?? 'CLIENT',
        );
      },
    ),
    GoRoute(
      path: '/gps/:bookingId',
      name: 'gpsTracking',
      builder: (context, state) {
        final bookingId = state.pathParameters['bookingId']!;
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return GpsTrackingScreen(
          bookingId: bookingId,
          role: extra['role'] as String? ?? 'CLIENT',
          petName: extra['petName'] as String? ?? '',
          token: extra['token'] as String? ?? '',
          petPhoto: extra['petPhoto'] as String?,
        );
      },
    ),
  ],
);

// ── App Entry Point ────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GardenApp());
}

class GardenApp extends StatelessWidget {
  const GardenApp({super.key});

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
