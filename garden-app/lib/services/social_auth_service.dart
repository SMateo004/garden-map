import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  // Populated when userExists == false (register flow)
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
    this.userData,
  });
}

class SocialAuthService {
  static String get _baseUrl => const String.fromEnvironment(
      'API_URL',
      defaultValue: 'https://api.gardenbo.com/api');

  // ── Google ──────────────────────────────────────────────────────────────

  static Future<SocialUserData?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile');
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
          provider: SocialProvider.google,
        );
      }

      // Mobile
      final googleUser = await GoogleSignIn(
        clientId: '1067635397531-d9v8mtsm3to56m71krq6h5g01p1081vh.apps.googleusercontent.com',
      ).signIn();
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
  /// - Si el usuario existe → devuelve tokens y role
  /// - Si no existe → devuelve userData para pre-llenar el register
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
        final d = body['data'] as Map<String, dynamic>;
        final user = d['user'] as Map<String, dynamic>;
        final role = user['role'] as String;
        final activeRole = user['activeRole'] as String?;
        final name = '${user['firstName']} ${user['lastName']}';

        // Persist tokens + roles — mismas claves que AuthService
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token',  d['accessToken'] as String);
        await prefs.setString('refresh_token', d['refreshToken'] as String);
        await prefs.setString('user_role',     role);
        await prefs.setString('user_id',       user['id'] as String? ?? '');
        await prefs.setString('user_name',     name);
        await prefs.setString('user_photo',    user['profilePicture'] as String? ?? '');
        // Save active_role only if it overrides the permanent role
        if (activeRole != null && activeRole.isNotEmpty && activeRole != role) {
          await prefs.setString('active_role', activeRole);
        } else {
          await prefs.remove('active_role');
        }

        return SocialLoginResult(
          success: true,
          userExists: true,
          accessToken: d['accessToken'] as String,
          refreshToken: d['refreshToken'] as String,
          role: role,
          activeRole: activeRole,
          userName: name,
        );
      }

      if (res.statusCode == 404) {
        // Email not found → send user to register with pre-filled data
        return SocialLoginResult(
          success: true,
          userExists: false,
          userData: data,
        );
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
}
