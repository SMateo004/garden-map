import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import 'caregiver_profile_data_screen.dart';
import 'verification_screen.dart';
import 'email_verification_screen.dart';

/// Post-registration guided setup flow for caregivers.
///
/// Steps:
///   0 → Professional Profile  (CaregiverProfileDataScreen)
///   1 → Identity Verification (VerificationScreen)
///   2 → Email Verification    (EmailVerificationScreen)
///
/// The flow runs only once after registration. If the user exits mid-flow,
/// re-entering `/caregiver/setup` resumes at the earliest incomplete step.
/// On completion, auto-submits the profile and navigates to `/caregiver/home`.
class CaregiverSetupFlowScreen extends StatefulWidget {
  const CaregiverSetupFlowScreen({super.key});

  @override
  State<CaregiverSetupFlowScreen> createState() => _CaregiverSetupFlowScreenState();
}

class _CaregiverSetupFlowScreenState extends State<CaregiverSetupFlowScreen> {
  static const _baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://garden-api-1ldd.onrender.com/api',
  );

  static const _totalSteps = 3;

  int _currentStep = 0;
  bool _isLoading = true;
  String _token = '';
  Map<String, dynamic>? _profile;

  final _stepLabels = const [
    'Perfil profesional',
    'Verificacion de identidad',
    'Verificacion de email',
  ];

  final _stepIcons = const [
    Icons.person_outline_rounded,
    Icons.verified_user_outlined,
    Icons.email_outlined,
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('access_token') ?? '';
    await _loadProfileAndDetermineStep();
  }

  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      };

  /// Load the caregiver profile and compute the earliest incomplete step.
  Future<void> _loadProfileAndDetermineStep() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/caregiver/my-profile'),
        headers: _authHeaders,
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        _profile = data['data'];
      }
    } catch (_) {}

    if (_profile != null) {
      final step = _computeResumeStep(_profile!);
      setState(() {
        _currentStep = step;
        _isLoading = false;
      });
    } else {
      // Fallback: start from the beginning
      setState(() => _isLoading = false);
    }
  }

  /// Determines the first step that hasn't been completed yet.
  int _computeResumeStep(Map<String, dynamic> profile) {
    // Step 0: Professional profile — check key required fields
    final bio = (profile['bio'] as String? ?? '').trim();
    final bioDetail = (profile['bioDetail'] as String? ?? '').trim();
    final experienceDesc = (profile['experienceDescription'] as String? ?? '').trim();
    final whyCaregiver = (profile['whyCaregiver'] as String? ?? '').trim();
    final whatDiffers = (profile['whatDiffers'] as String? ?? '').trim();
    final handleAnxious = (profile['handleAnxious'] as String? ?? '').trim();
    final emergencyResponse = (profile['emergencyResponse'] as String? ?? '').trim();
    final sizesAccepted = (profile['sizesAccepted'] as List?) ?? [];
    final animalTypes = (profile['animalTypes'] as List?) ?? [];

    final profileComplete = bio.length >= 45 &&
        bioDetail.length >= 3 &&
        experienceDesc.length >= 15 &&
        whyCaregiver.length >= 3 &&
        whatDiffers.length >= 3 &&
        handleAnxious.isNotEmpty &&
        emergencyResponse.isNotEmpty &&
        sizesAccepted.isNotEmpty &&
        animalTypes.isNotEmpty;

    if (!profileComplete) return 0;

    // Step 1: Identity verification
    final identityStatus = (profile['identityVerificationStatus'] as String? ?? '').toUpperCase();
    if (identityStatus != 'VERIFIED' && identityStatus != 'APPROVED') return 1;

    // Step 2: Email verification
    final emailVerified = profile['emailVerified'] == true;
    final userEmailVerified = (profile['user'] as Map<String, dynamic>?)?['emailVerified'] == true;
    if (!emailVerified && !userEmailVerified) return 2;

    // All done — shouldn't be here, redirect to home
    return _totalSteps;
  }

  void _advanceStep() {
    if (_currentStep + 1 >= _totalSteps) {
      _completeFlow();
    } else {
      setState(() => _currentStep++);
    }
  }

  Future<void> _completeFlow() async {
    setState(() => _isLoading = true);

    // Try auto-submit profile for approval
    try {
      await http.post(
        Uri.parse('$_baseUrl/caregiver/profile/submit'),
        headers: _authHeaders,
      );
    } catch (_) {
      // Non-blocking — profile may already be approved
    }

    // Mark setup complete in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('caregiver_setup_complete', true);

    if (!mounted) return;
    context.go('/caregiver/home');
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bg,
        body: const Center(child: CircularProgressIndicator(color: GardenColors.primary)),
      );
    }

    // If all steps done already, go home
    if (_currentStep >= _totalSteps) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _completeFlow());
      return Scaffold(backgroundColor: bg, body: const Center(child: CircularProgressIndicator(color: GardenColors.primary)));
    }

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top progress header ────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              decoration: BoxDecoration(
                color: surface,
                border: Border(
                  bottom: BorderSide(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
                ),
              ),
              child: Column(
                children: [
                  // Step counter
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: GardenColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Paso ${_currentStep + 1} de $_totalSteps',
                          style: const TextStyle(
                            color: GardenColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _stepLabels[_currentStep],
                        style: TextStyle(
                          color: textColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (_currentStep + 1) / _totalSteps,
                      backgroundColor: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
                      color: GardenColors.primary,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Step dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_totalSteps, (i) {
                      final isActive = i == _currentStep;
                      final isDone = i < _currentStep;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              width: isActive ? 32 : 28,
                              height: isActive ? 32 : 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isDone
                                    ? GardenColors.success
                                    : isActive
                                        ? GardenColors.primary
                                        : (isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.06)),
                                border: isActive
                                    ? Border.all(color: GardenColors.primary.withOpacity(0.3), width: 2)
                                    : null,
                              ),
                              child: Icon(
                                isDone ? Icons.check_rounded : _stepIcons[i],
                                size: isActive ? 18 : 16,
                                color: isDone || isActive ? Colors.white : subtextColor,
                              ),
                            ),
                            if (i < _totalSteps - 1) ...[
                              Container(
                                width: 24,
                                height: 2,
                                color: i < _currentStep
                                    ? GardenColors.success
                                    : (isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.08)),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),

            // ── Step content ────────────────────────────────────────
            Expanded(child: _buildStepContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return CaregiverProfileDataScreen(
          embeddedMode: true,
          onSaveComplete: _advanceStep,
        );
      case 1:
        return VerificationScreen(
          onComplete: _advanceStep,
          showAppBar: false,
        );
      case 2:
        return EmailVerificationScreen(
          onComplete: _advanceStep,
          showAppBar: false,
        );
      default:
        return const Center(child: CircularProgressIndicator(color: GardenColors.primary));
    }
  }
}
