import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_state.dart';
import 'secure_storage_service.dart';

enum SocialProvider { google, apple, facebook }

class SocialUserData {
  final String? idToken;
  final String? email;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? photoUrl;
  final SocialProvider provider;

  const SocialUserData({
    this.idToken,
    required this.email,
    required this.firstName,
    required this.lastName,
    this.phone,
    this.photoUrl,
    required this.provider,
  });
}

class SocialLoginResult {
  final bool success;
  final bool userExists;
  final String? error;
  // Populated when userExists == true
  final String? accessToken;
  final String? refreshToken;
  final String? role;
  final String? activeRole;
  final String? userName;
  // True when this call just created a brand-new CLIENT account via social
  // pre-registration (phone/dateOfBirth/address still missing — must be
  // completed from "Mi Perfil" before the user can book).
  final bool isNewAccount;
  // Google's profile photo, if it provided one — used to decide whether the
  // mandatory-photo gate (CLIENT role) needs to intercept navigation.
  final String? profilePicture;
  // Populated when userExists == false AND the auto pre-registration itself
  // failed (e.g. registrations paused, invalid invite code) — caller should
  // show the error rather than silently falling back to the manual form.
  final SocialUserData? userData;

  const SocialLoginResult({
    required this.success,
    required this.userExists,
    this.error,
    this.accessToken,
    this.refreshToken,
    this.role,
    this.activeRole,
    this.userName,
    this.isNewAccount = false,
    this.profilePicture,
    this.userData,
  });
}

class SocialAuthService {
  static String get _baseUrl => const String.fromEnvironment(
      'API_URL',
      defaultValue: 'https://api.gardenbo.com/api');

  // ── Google ──────────────────────────────────────────────────────────────

  /// Lee el resultado pendiente de un signInWithRedirect de Google (si lo hubo).
  /// Devuelve null si no hay resultado pendiente.
  static Future<SocialUserData?> getGoogleRedirectResult() async {
    try {
      final result = await FirebaseAuth.instance.getRedirectResult();
      final user = result.user;
      if (user == null) return null;
      final idToken = await user.getIdToken();
      final parts = (user.displayName ?? '').split(' ');
      return SocialUserData(
        idToken: idToken,
        email: user.email ?? '',
        firstName: parts.isNotEmpty ? parts.first : '',
        lastName: parts.length > 1 ? parts.sublist(1).join(' ') : '',
        photoUrl: user.photoURL,
        provider: SocialProvider.google,
      );
    } catch (e) {
      debugPrint('[SocialAuth] getRedirectResult error: $e');
      return null;
    }
  }

  static Future<SocialUserData?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // En web usamos el paquete google_sign_in con el client ID web
        // (usa GIS de Google en lugar del OAuth flow de Firebase, evitando
        // el bug de popup/redirect colgado en Flutter web).
        const webClientId =
            '1067635397531-d9v8mtsm3to56m71krq6h5g01p1081vh.apps.googleusercontent.com';
        final googleSignIn = GoogleSignIn(
          clientId: webClientId,
          scopes: ['email', 'profile'],
        );
        final googleUser = await googleSignIn.signIn();
        if (googleUser == null) return null;

        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        final result = await FirebaseAuth.instance.signInWithCredential(credential);
        final user = result.user;
        if (user == null) return null;
        final idToken = await user.getIdToken();
        final parts = (user.displayName ?? '').split(' ');
        return SocialUserData(
          idToken: idToken,
          email: user.email ?? '',
          firstName: parts.isNotEmpty ? parts.first : '',
          lastName: parts.length > 1 ? parts.sublist(1).join(' ') : '',
          photoUrl: user.photoURL,
          provider: SocialProvider.google,
        );
      }

      // Mobile — no pasamos clientId; el plugin lee CLIENT_ID de GoogleService-Info.plist (iOS)
      // y oauth_client de google-services.json (Android).
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final result = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = result.user;
      if (user == null) return null;
      final idToken = await user.getIdToken();
      final parts = (googleUser.displayName ?? '').split(' ');
      return SocialUserData(
        idToken: idToken,
        email: googleUser.email,
        firstName: parts.isNotEmpty ? parts.first : '',
        lastName: parts.length > 1 ? parts.sublist(1).join(' ') : '',
        photoUrl: googleUser.photoUrl,
        provider: SocialProvider.google,
      );
    } catch (e) {
      debugPrint('[SocialAuth] Google error: $e');
      return null;
    }
  }

  // ── Apple ───────────────────────────────────────────────────────────────

  static Future<SocialUserData?> signInWithApple() async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(oauthCredential);
      final idToken = await userCredential.user?.getIdToken();

      // Apple solo entrega nombre en el PRIMER login
      final firstName = appleCredential.givenName ??
          userCredential.user?.displayName?.split(' ').first ??
          '';
      final lastName = appleCredential.familyName ??
          (userCredential.user?.displayName?.split(' ')
                  .skip(1)
                  .join(' ') ??
              '');

      return SocialUserData(
        idToken: idToken,
        email: appleCredential.email ?? userCredential.user?.email ?? '',
        firstName: firstName,
        lastName: lastName,
        provider: SocialProvider.apple,
      );
    } catch (e) {
      debugPrint('[SocialAuth] Apple error: $e');
      return null;
    }
  }

  // ── Facebook ─────────────────────────────────────────────────────────────

  static Future<SocialUserData?> signInWithFacebook() async {
    try {
      if (kIsWeb) {
        final provider = FacebookAuthProvider()
          ..addScope('email')
          ..addScope('public_profile');
        final result = await FirebaseAuth.instance.signInWithPopup(provider);
        final user = result.user;
        if (user == null) return null;
        final idToken = await user.getIdToken();
        final parts = (user.displayName ?? '').split(' ');
        return SocialUserData(
          idToken: idToken,
          email: user.email ?? '',
          firstName: parts.isNotEmpty ? parts.first : '',
          lastName: parts.length > 1 ? parts.sublist(1).join(' ') : '',
          photoUrl: user.photoURL,
          provider: SocialProvider.facebook,
        );
      }

      // Mobile
      final loginResult = await FacebookAuth.instance.login(
        permissions: ['email', 'public_profile'],
      );
      if (loginResult.status != LoginStatus.success) return null;

      final credential =
          FacebookAuthProvider.credential(loginResult.accessToken!.tokenString);
      final result = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = result.user;
      if (user == null) return null;
      final idToken = await user.getIdToken();

      final fbData = await FacebookAuth.instance.getUserData(
        fields: 'name,email,first_name,last_name',
      );
      final parts = (user.displayName ?? '').split(' ');
      return SocialUserData(
        idToken: idToken,
        email: user.email ?? '',
        firstName: fbData['first_name'] as String? ?? (parts.isNotEmpty ? parts.first : ''),
        lastName: fbData['last_name'] as String? ?? (parts.length > 1 ? parts.sublist(1).join(' ') : ''),
        photoUrl: user.photoURL,
        provider: SocialProvider.facebook,
      );
    } catch (e) {
      debugPrint('[SocialAuth] Facebook error: $e');
      return null;
    }
  }

  // ── Backend login ─────────────────────────────────────────────────────────

  /// Verifica el token contra el backend.
  /// - Si el usuario existe → devuelve tokens y role (login normal)
  /// - Si NO existe → crea automáticamente una cuenta CLIENT (dueño de
  ///   mascota) con los datos que el proveedor entregue en este momento, y
  ///   entra directo a la app. El teléfono/fecha de nacimiento/dirección
  ///   quedan pendientes — se completan después desde "Mi Perfil".
  ///   Los cuidadores NUNCA se crean por este camino: si alguien con
  ///   intención de ser cuidador usa este botón, igual entra como dueño de
  ///   mascota — para registrarse como cuidador hay que usar el formulario
  ///   completo, que no muestra estos botones sociales.
  static Future<SocialLoginResult> loginWithBackend(
      SocialUserData data) async {
    if (data.idToken == null) {
      return const SocialLoginResult(
          success: false, userExists: false, error: 'Token vacío');
    }

    try {
      final providerName = data.provider.name; // 'google' | 'apple' | 'facebook'
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/social/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'provider': providerName,
          'idToken': data.idToken,
        }),
      );

      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200 && body['success'] == true) {
        return _persistAndBuildResult(body['data'] as Map<String, dynamic>, isNewAccount: false);
      }

      if (res.statusCode == 404) {
        // Cuenta no existe → crearla automáticamente como CLIENT (pre-registro)
        return _registerClientWithBackend(data);
      }

      return SocialLoginResult(
        success: false,
        userExists: false,
        error: body['error']?['message'] as String? ?? 'Error al iniciar sesión',
      );
    } catch (e) {
      return const SocialLoginResult(
          success: false, userExists: false, error: 'Error de conexión');
    }
  }

  /// Crea una cuenta CLIENT instantánea con los datos mínimos del proveedor
  /// social (nombre, apellido, email, foto) y loguea directo — sin pedir
  /// teléfono ni fecha de nacimiento. Llamado solo desde [loginWithBackend]
  /// cuando el email no tiene cuenta existente.
  static Future<SocialLoginResult> _registerClientWithBackend(SocialUserData data) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/social/register-client'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'provider': data.provider.name,
          'idToken': data.idToken,
        }),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 201 && body['success'] == true) {
        return _persistAndBuildResult(body['data'] as Map<String, dynamic>, isNewAccount: true);
      }

      return SocialLoginResult(
        success: false,
        userExists: false,
        error: (body['error'] as Map<String, dynamic>?)?['message'] as String? ??
            'No se pudo crear tu cuenta. Intenta de nuevo.',
      );
    } catch (e) {
      return const SocialLoginResult(
          success: false, userExists: false, error: 'Error de conexión');
    }
  }

  /// Guarda tokens + datos de usuario (común a login y registro social).
  static Future<SocialLoginResult> _persistAndBuildResult(
    Map<String, dynamic> d, {
    required bool isNewAccount,
  }) async {
    final user = d['user'] as Map<String, dynamic>;
    final role = user['role'] as String;
    final activeRole = user['activeRole'] as String?;
    final name = '${user['firstName']} ${user['lastName']}';

    final accessToken  = d['accessToken']  as String;
    final refreshToken = d['refreshToken'] as String;
    await SecureStorageService.saveAccessToken(accessToken);
    await SecureStorageService.saveRefreshToken(refreshToken);
    await AuthState.update(accessToken);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role',  role);
    await prefs.setString('user_id',    user['id'] as String? ?? '');
    await prefs.setString('user_name',  name);
    await prefs.setString('user_photo', user['profilePicture'] as String? ?? '');
    String effectiveActiveRole = '';
    if (activeRole != null && activeRole.isNotEmpty && activeRole != role) {
      await prefs.setString('active_role', activeRole);
      effectiveActiveRole = activeRole;
    } else {
      await prefs.remove('active_role');
    }
    AuthState.updateRole(role: role, activeRole: effectiveActiveRole);

    return SocialLoginResult(
      success: true,
      userExists: true,
      accessToken: accessToken,
      refreshToken: refreshToken,
      role: role,
      activeRole: activeRole,
      userName: name,
      isNewAccount: isNewAccount,
      profilePicture: user['profilePicture'] as String?,
    );
  }
}
