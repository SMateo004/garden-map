import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'firebase_options.dart';
import 'package:go_router/go_router.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/upload_profile_photo_screen.dart';
import 'screens/client/client_welcome_screen.dart';
import 'screens/client/about_screen.dart';
import 'screens/caregiver/onboarding_wizard_screen.dart';
import 'screens/test_agentes_screen.dart';
import 'screens/admin/admin_panel_screen.dart';
import 'screens/admin/admin_identity_review_screen.dart';
import 'screens/admin/admin_reservation_detail_screen.dart';
import 'screens/client/my_pets_screen.dart';
import 'screens/client/caregiver_profile_screen.dart';
import 'screens/client/booking_screen.dart';
import 'screens/client/payment_screen.dart';
import 'screens/client/slot_conflict_screen.dart';
import 'screens/client/booking_confirmed_screen.dart';
import 'screens/caregiver/caregiver_home_screen.dart';
import 'screens/caregiver/caregiver_pets_screen.dart';
import 'screens/caregiver/verification_screen.dart';
import 'screens/caregiver/trainings_screen.dart';
import 'screens/caregiver/caregiver_edit_profile_screen.dart';
import 'screens/client/my_bookings_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/caregiver/caregiver_profile_data_screen.dart';
import 'screens/caregiver/caregiver_setup_flow_screen.dart';
import 'screens/caregiver/become_caregiver_screen.dart';
import 'screens/caregiver/caregiver_guide_screen.dart';
import 'screens/wallet/wallet_screen.dart';
import 'screens/service/service_execution_screen.dart';
import 'screens/service/meet_and_greet_screen.dart';
import 'screens/service/gps_tracking_screen.dart';
import 'screens/dispute/dispute_screen.dart';
import 'screens/client/favorites_screen.dart';
import 'screens/client/client_shell_screen.dart';
import 'screens/client/web_shell_screen.dart';
import 'screens/onboarding/mobile_splash_screen.dart';
import 'screens/onboarding/mobile_onboarding_screen.dart';
import 'screens/onboarding/mobile_service_selector_screen.dart';
import 'screens/onboarding/maintenance_screen.dart';
import 'screens/onboarding/update_required_screen.dart';
import 'screens/caregiver/mobile_verify_screen.dart';
import 'screens/legal/legal_screen.dart';
import 'screens/support/help_center_screen.dart';
import 'screens/support/help_category_screen.dart';
import 'screens/support/help_article_screen.dart';
import 'data/help_center_content.dart';
import 'screens/caregiver/professional_register_screen.dart';
import 'screens/caregiver/company_register_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/forgot_password_code_screen.dart';
import 'screens/auth/forgot_password_new_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'theme/garden_theme.dart';
import 'services/local_notification_service.dart';
import 'services/fcm_service.dart';
import 'services/auth_state.dart'; // sessionExpiredNotifier + AuthState
import 'services/web_notification_service.dart';
import 'services/global_http_client.dart'; // maintenanceNotifier + networkErrorNotifier
import 'utils/web_redirect.dart';
import 'package:http/http.dart' as http;

// ── Build-time env (set via --dart-define) ─────────────────
const _kSentryDsn    = String.fromEnvironment('SENTRY_DSN');

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

// ── Rutas públicas (accesibles sin sesión) ──────────────────
const _publicPaths = {
  '/',
  '/splash',
  '/login',
  '/register',
  '/forgot-password',
  '/forgot-password/code',
  '/forgot-password/new',
  '/onboarding',
  '/about',
  '/become-caregiver',
  '/maintenance',
  '/update-required',
  '/privacy',
  '/terms',
  '/help-center',
  '/sign-in/profesional',
  '/caregiver/onboarding',
  '/caregiver/onboarding-profesional',
  '/client-welcome',
  '/service-selector', // accesible sin login (modo guest)
  '/marketplace',      // accesible sin login (modo guest)
  '/mobile-verify',    // verificación de identidad vía QR — no requiere sesión
  '/verify',           // alias legacy de /mobile-verify
};

// ── Guardia de rol ───────────────────────────────────────────
// Mapeo conservador de prefijos de ruta → rol requerido, SOLO para pantallas
// "home" exclusivas de cada rol. Deja fuera a propósito rutas compartidas o
// de flujos de transición (ej. /caregiver/onboarding, /caregiver/setup,
// /caregiver/verification), que un CLIENT convirtiéndose en CAREGIVER (o un
// CAREGIVER aún no aprobado) necesita poder visitar sin importar su rol
// efectivo actual.
const _roleRestrictedPrefixes = <String, String>{
  '/admin': 'ADMIN',
  '/caregiver/home': 'CAREGIVER',
  '/caregiver/pets': 'CAREGIVER',
  '/marketplace': 'CLIENT',
  '/my-bookings-tab': 'CLIENT',
  '/my-pets-tab': 'CLIENT',
  '/my-pets': 'CLIENT',
  '/service-selector': 'CLIENT',
};

// Home correcta para cada rol efectivo — mismo destino que usa el cambio de
// rol explícito en profile_screen.dart (_doSwitchRole).
String _homeForRole(String effectiveRole) {
  switch (effectiveRole) {
    case 'ADMIN':
      return '/admin';
    case 'CAREGIVER':
      return '/caregiver/home';
    default:
      return '/service-selector';
  }
}

// ── Router ─────────────────────────────────────────────────
final GoRouter _router = GoRouter(
  initialLocation: '/',
  // Redirige al login si se intenta acceder a una ruta protegida sin sesión.
  redirect: (context, state) {
    final path = state.matchedLocation;

    // Guardia de rol: se evalúa ANTES del chequeo de rutas públicas porque
    // /marketplace y /service-selector son públicas para invitados pero
    // igual deben respetar el rol efectivo de una sesión ya autenticada
    // (ej. tras un cambio de rol seguido de "atrás" en el navegador).
    if (AuthState.hasSession) {
      String? requiredRole;
      for (final entry in _roleRestrictedPrefixes.entries) {
        if (path == entry.key || path.startsWith('${entry.key}/')) {
          requiredRole = entry.value;
          break;
        }
      }
      if (requiredRole != null && AuthState.effectiveRole != requiredRole) {
        return _homeForRole(AuthState.effectiveRole);
      }
    }

    if (_publicPaths.any((p) => path == p || path.startsWith('$p/'))) {
      return null; // ruta pública — sin restricción
    }
    // AuthState.token es sincrónico (cacheado en memoria desde el startup).
    // Si está vacío → sesión inexistente o expirada → redirigir a login.
    if (!AuthState.hasSession) return '/login';
    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      name: 'landing',
      builder: (context, state) {
        if (kIsWeb) {
          // En web la landing vive en index.html (React). Redirigir siempre.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            redirectToReactLanding();
          });
          return const SizedBox.shrink();
        }
        return const _MobileAuthGate();
      },
    ),
    GoRoute(
      path: '/splash',
      name: 'splash',
      builder: (context, state) => const MobileSplashScreen(),
    ),
    GoRoute(
      path: '/maintenance',
      name: 'maintenance',
      builder: (context, state) => const MaintenanceScreen(),
    ),
    GoRoute(
      path: '/update-required',
      name: 'updateRequired',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return UpdateRequiredScreen(storeUrl: extra?['storeUrl'] as String? ?? '');
      },
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
    if (kDebugMode)
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
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: '/forgot-password/code',
      builder: (context, state) => ForgotPasswordCodeScreen(
        email: state.extra as String? ?? '',
      ),
    ),
    GoRoute(
      path: '/forgot-password/new',
      builder: (context, state) => ForgotPasswordNewScreen(
        tempToken: state.extra as String? ?? '',
      ),
    ),
    GoRoute(
      path: '/register',
      name: 'register',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return RegisterScreen(
          prefillFirstName: extra?['firstName'] as String?,
          prefillLastName: extra?['lastName'] as String?,
          prefillEmail: extra?['email'] as String?,
          fromSocial: extra?['fromSocial'] as bool? ?? false,
          caregiverOnly: extra?['caregiverOnly'] as bool? ?? false,
        );
      },
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
          clientConversionMode: extra['clientConversionMode'] as bool? ?? false,
        );
      },
    ),
    GoRoute(
      path: '/about',
      name: 'about',
      builder: (context, state) => const AboutScreen(),
    ),
    GoRoute(
      path: '/become-caregiver',
      name: 'becomeCaregiver',
      builder: (context, state) => const BecomeCaregiverScreen(),
    ),
    GoRoute(
      path: '/client-welcome',
      name: 'clientWelcome',
      builder: (context, state) => const ClientWelcomeScreen(),
    ),
    GoRoute(
      path: '/upload-profile-photo',
      name: 'uploadProfilePhoto',
      builder: (context, state) {
        final nextRoute = (state.extra as Map?)?['nextRoute'] as String? ?? '/service-selector';
        return UploadProfilePhotoScreen(nextRoute: nextRoute);
      },
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
        // Web: usar WebShellScreen con nav en el header
        // zone: normalizar a UPPERCASE para coincidir con kZoneLabels keys
        // size: aceptar tanto 'size' (SMALL/MEDIUM/LARGE) como 'sizesAccepted' legacy
        final rawZone = q['zone'];
        final rawSize = q['size'] ?? q['sizesAccepted'];
        final normalizedSize = const {
          'PEQUEÑO': 'SMALL', 'MEDIANO': 'MEDIUM', 'GRANDE': 'LARGE',
        }[rawSize] ?? rawSize;
        return WebShellScreen(
          initialTab: 0,
          initialService: q['service'],
          initialZone: rawZone != null ? rawZone.toUpperCase() : null,
          initialSize: normalizedSize,
          initialPetType: q['petType'],
        );
      },
    ),
    GoRoute(
      path: '/my-bookings-tab',
      name: 'myBookingsTab',
      builder: (context, state) =>
          kIsWeb ? const WebShellScreen(initialTab: 1) : const ClientShellScreen(initialTab: 1),
    ),
    GoRoute(
      path: '/my-pets-tab',
      name: 'myPetsTab',
      builder: (context, state) =>
          kIsWeb ? const WebShellScreen(initialTab: 2) : const ClientShellScreen(initialTab: 2),
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
      path: '/caregiver/pets',
      name: 'caregiverPets',
      builder: (context, state) => const CaregiverPetsScreen(),
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
      path: '/caregiver/trainings',
      name: 'caregiverTrainings',
      builder: (context, state) => const TrainingsScreen(),
    ),
    GoRoute(
      path: '/booking/:caregiverId',
      name: 'booking',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return BookingScreen(
          caregiverId: state.pathParameters['caregiverId']!,
          preloadedCaregiver: extra?['caregiver'] as Map<String, dynamic>?,
          preloadedPets: extra?['pets'] as List<dynamic>?,
          preloadedToken: extra?['token'] as String?,
          preloadedService: extra?['serviceType'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/payment/:bookingId',
      name: 'payment',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return PaymentScreen(
          bookingId: state.pathParameters['bookingId']!,
          mgData: extra?['mgData'] as Map<String, dynamic>?,
        );
      },
    ),
    // New flow: booking is NOT created yet — created when user presses "Generar QR"
    GoRoute(
      path: '/payment-new',
      name: 'paymentNew',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return PaymentScreen(
          bookingParams: extra?['bookingParams'] as Map<String, dynamic>?,
        );
      },
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
      path: '/slot-conflict/:bookingId',
      name: 'slotConflict',
      builder: (context, state) {
        final bookingId = state.pathParameters['bookingId']!;
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return SlotConflictScreen(
          bookingId: bookingId,
          serviceType: extra['serviceType'] as String? ?? 'PASEO',
          caregiverId: extra['caregiverId'] as String? ?? '',
        );
      },
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
      path: '/caregiver/onboarding-profesional',
      name: 'companyRegister',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return CompanyRegisterScreen(
          resumeMode: extra['resumeMode'] as bool? ?? false,
        );
      },
    ),
    GoRoute(
      path: '/caregiver/:id',
      name: 'caregiverProfile',
      builder: (context, state) => CaregiverProfileScreen(
        caregiverId: state.pathParameters['id']!,
        initialData: state.extra as Map<String, dynamic>?,
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
    // Ruta pública para verificación de identidad desde móvil (escaneando QR de web)
    GoRoute(
      path: '/mobile-verify',
      name: 'mobileVerify',
      builder: (context, state) {
        final token = state.uri.queryParameters['token'] ?? '';
        if (kDebugMode) debugPrint('[Router] /mobile-verify — token length: ${token.length}');
        return MobileVerifyScreen(token: token);
      },
    ),
    // Alias legacy: el backend generaba /verify antes de la corrección
    GoRoute(
      path: '/verify',
      redirect: (context, state) {
        final token = state.uri.queryParameters['token'] ?? '';
        return '/mobile-verify?token=${Uri.encodeComponent(token)}';
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
    GoRoute(
      path: '/help-center',
      name: 'helpCenter',
      builder: (context, state) => const HelpCenterScreen(),
    ),
    GoRoute(
      path: '/help-center/category',
      name: 'helpCenterCategory',
      builder: (context, state) {
        // `extra` no sobrevive a un refresh de página en Flutter Web (no va
        // codificado en la URL). Si llega null o de un tipo inesperado,
        // volvemos al índice del Centro de Ayuda en vez de crashear.
        final category = state.extra as HelpCategory?;
        if (category == null) {
          return const HelpCenterScreen();
        }
        return HelpCategoryScreen(category: category);
      },
    ),
    GoRoute(
      path: '/help-center/article',
      name: 'helpCenterArticle',
      builder: (context, state) {
        // Mismo caso: sin `extra` (p. ej. tras un refresh en web) no hay forma
        // de reconstruir el artículo, así que caemos de vuelta al índice.
        final extra = state.extra as Map<String, dynamic>?;
        final article = extra?['article'] as HelpArticle?;
        final categoryTitle = extra?['categoryTitle'] as String?;
        if (article == null || categoryTitle == null) {
          return const HelpCenterScreen();
        }
        return HelpArticleScreen(
          article: article,
          categoryTitle: categoryTitle,
        );
      },
    ),
    GoRoute(
      path: '/privacy',
      name: 'privacy',
      builder: (context, state) => const PrivacyPolicyScreen(),
    ),
    GoRoute(
      path: '/terms',
      name: 'terms',
      builder: (context, state) => const TermsOfServiceScreen(),
    ),
    GoRoute(
      path: '/sign-in/profesional',
      name: 'professionalRegister',
      builder: (context, state) => const ProfessionalRegisterScreen(),
    ),
    GoRoute(
      path: '/guia-cuidador',
      name: 'caregiverGuide',
      builder: (context, state) => const CaregiverGuideScreen(),
    ),
  ],
);

// ── App Entry Point ────────────────────────────────────────
Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Puerto de comunicación entre el foreground service GPS (Android) y el
  // isolate principal — debe registrarse antes de que cualquier pantalla
  // pueda llamar a GpsTrackingSession.start(). No aplica a iOS/web (ahí el
  // tracking en background no usa un isolate de servicio separado).
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    FlutterForegroundTask.initCommunicationPort();
  }

  // Cargar token en memoria PRIMERO — el GoRouter redirect y todas las
  // pantallas usan AuthState.token de forma sincrónica desde aquí en adelante.
  await AuthState.initialize();

  // Cargar preferencia de tema guardada antes de mostrar nada
  await themeNotifier.init();

  // Web: necesita options explícitas (no hay google-services.json en web)
  // Mobile: Firebase se inicializa nativamente vía google-services.json — sin options
  if (kIsWeb) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } else {
    await Firebase.initializeApp();
  }

  if (!kIsWeb) {
    // Crashlytics: captura errores de Flutter y de la plataforma nativa
    FlutterError.onError = (details) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      FcmService.reportErrorToAdmin(
        'Flutter error: ${details.exception}',
        details.stack?.toString() ?? '',
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      FcmService.reportErrorToAdmin('Platform error: $error', stack.toString());
      return true;
    };
  }

  // Notificaciones (FCM + locales): NO se esperan aquí. El diálogo de permiso
  // del sistema y los reintentos de red de FCM (hasta 12s) bloqueaban el
  // primer frame — la app se quedaba en la pantalla verde nativa hasta que
  // el usuario respondía el diálogo. Corren en segundo plano sin bloquear.
  if (!kIsWeb) {
    unawaited(_initNotificationsInBackground());
  }
}

Future<void> _initNotificationsInBackground() async {
  // Cada paso en su propio try/catch — si uno falla (ej. el plugin de
  // notificaciones locales no puede inicializar en un dispositivo puntual),
  // no debe tumbar los demás ni quedar como una excepción sin capturar en
  // este Future "unawaited" (eso disparaba una alerta de "crash" al agente
  // de resolución de errores por algo que en realidad es degradación
  // aislada — la app sigue funcionando, solo sin notificaciones locales).
  try {
    await LocalNotificationService.init();
  } catch (e, st) {
    debugPrint('LocalNotificationService.init failed: $e');
    FcmService.reportErrorToAdmin('LocalNotificationService.init failed: $e', st.toString());
  }
  try {
    await FcmService.init();
  } catch (e, st) {
    debugPrint('FcmService.init failed: $e');
    FcmService.reportErrorToAdmin('FcmService.init failed: $e', st.toString());
  }
  try {
    await LocalNotificationService.requestPermission();
  } catch (e, st) {
    debugPrint('LocalNotificationService.requestPermission failed: $e');
    FcmService.reportErrorToAdmin('LocalNotificationService.requestPermission failed: $e', st.toString());
  }
}

void main() async {
  // Injects GlobalHttpClient as the default client used by every top-level
  // http.get/post/... call in the app (235+ call sites, none of which need
  // to change). Lets us detect mid-session maintenance mode and network
  // failures globally — see services/global_http_client.dart.
  http.runWithClient(() => _runApp(), () => GlobalHttpClient());
}

Future<void> _runApp() async {
  // Sentry: error monitoring (solo si el DSN está configurado en build)
  if (_kSentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = _kSentryDsn;
        options.tracesSampleRate = 0.2;
        options.environment = const String.fromEnvironment('APP_ENV', defaultValue: 'production');
      },
      appRunner: () async {
        await _bootstrap();
        runApp(const GardenApp());
      },
    );
  } else {
    await _bootstrap();
    runApp(const GardenApp());
  }
}

class GardenApp extends StatefulWidget {
  const GardenApp({super.key});

  @override
  State<GardenApp> createState() => _GardenAppState();
}

class _GardenAppState extends State<GardenApp> {
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    // Inyectar router en FcmService para navegación desde notificaciones
    FcmService.setRouter(_router);
    // Escuchar sesión expirada globalmente: redirige al login desde cualquier pantalla.
    sessionExpiredNotifier.addListener(_onSessionExpired);
    // Escuchar mantenimiento activado mid-sesión (no solo al abrir la app).
    maintenanceNotifier.addListener(_onMaintenanceDetected);
    // Escuchar errores de red para mostrar un banner global.
    networkErrorNotifier.addListener(_onNetworkError);
  }

  @override
  void dispose() {
    sessionExpiredNotifier.removeListener(_onSessionExpired);
    maintenanceNotifier.removeListener(_onMaintenanceDetected);
    networkErrorNotifier.removeListener(_onNetworkError);
    _networkErrorTimer?.cancel();
    super.dispose();
  }

  void _onSessionExpired() {
    if (!sessionExpiredNotifier.value) return;
    sessionExpiredNotifier.value = false; // reset para no re-disparar
    // Limpiar token en memoria para que el redirect del router también bloquee
    // cualquier navegación hacia rutas protegidas.
    AuthState.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _router.go('/login');
      _scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Tu sesión ha expirado. Inicia sesión de nuevo.'),
          backgroundColor: Color(0xFFD32F2F),
          duration: Duration(seconds: 4),
        ),
      );
    });
  }

  void _onMaintenanceDetected() {
    if (!maintenanceNotifier.value) return;
    maintenanceNotifier.value = false; // reset para no re-disparar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _router.routerDelegate.currentConfiguration.uri.path;
      if (current == '/maintenance') return; // ya estamos ahí
      _router.go('/maintenance');
    });
  }

  // Debounce de 5s antes de mostrar el banner de "sin conexión" — sin esto,
  // el primer request que falla justo al reabrir la app (típico: la red/socket
  // todavía no terminó de reconectarse) disparaba el snackbar de inmediato,
  // aunque la siguiente request 1 segundo después ya funcionara bien. Ahora
  // solo se muestra si la falla de red sigue activa 5 segundos después.
  Timer? _networkErrorTimer;

  void _onNetworkError() {
    final message = networkErrorNotifier.value;
    _networkErrorTimer?.cancel();
    if (message == null) return; // recovery: cancelar cualquier aviso pendiente
    _networkErrorTimer = Timer(const Duration(seconds: 5), () {
      // Puede haber cambiado (o recuperado) mientras esperábamos — solo
      // mostrar si la falla sigue siendo la misma que disparó el timer.
      final stillFailing = networkErrorNotifier.value;
      if (stillFailing == null) return;
      final messenger = _scaffoldMessengerKey.currentState;
      if (messenger == null) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(stillFailing),
          backgroundColor: const Color(0xFF424242),
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        return MaterialApp.router(
          title: 'GARDEN',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: _scaffoldMessengerKey,
          routerConfig: _router,
          theme: gardenTheme(dark: themeNotifier.isDark),
          // Widget de error personalizado — evita la pantalla roja de Flutter en producción
          builder: (context, child) {
            ErrorWidget.builder = (details) => _GardenErrorWidget(
              error: details.exception.toString(),
            );
            final content = child ?? const SizedBox.shrink();
            // On web: wrap with overlay to show in-app notification toasts
            return kIsWeb
                ? WebNotificationOverlay(child: content)
                : content;
          },
        );
      },
    );
  }
}

// ── Error screen en producción ──────────────────────────────
class _GardenErrorWidget extends StatelessWidget {
  final String error;
  const _GardenErrorWidget({required this.error});

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF2EDE4),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🐾', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text(
                'Algo salió mal',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'El equipo GARDEN ya fue notificado.\nIntenta cerrar y abrir la app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    error,
                    style: const TextStyle(
                        color: Colors.red, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
