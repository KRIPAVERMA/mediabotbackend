import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'local_history_service.dart';

/// Manages user authentication state, JWT tokens, and API calls.
class AuthService {
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';

  static String? _token;
  static Map<String, dynamic>? _currentUser;

  /// Get the current JWT token (or null).
  static String? get token => _token;

  /// Get the current user info (or null).
  static Map<String, dynamic>? get currentUser => _currentUser;

  /// Whether the user is currently logged in.
  static bool get isLoggedIn => _token != null && _currentUser != null;

  // ── Initialize: load token from storage ──────────────────

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    final userJson = prefs.getString(_userKey);
    if (userJson != null) {
      try {
        _currentUser = jsonDecode(userJson);
      } catch (_) {
        _currentUser = null;
      }
    }

    // Validate token is still good
    if (_token != null) {
      try {
        final res = await http.get(
          Uri.parse('${ApiService.baseUrl}/api/auth/me'),
          headers: {'Authorization': 'Bearer $_token'},
        ).timeout(const Duration(seconds: 5));

        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          _currentUser = body['user'];
          await prefs.setString(_userKey, jsonEncode(_currentUser));
        } else {
          // Token expired
          await logout();
        }
      } catch (_) {
        // Network error — keep cached user, don't logout
      }
    }
    // Scope local history to this user (or guest if not logged in)
    await LocalHistoryService.setUser(_currentUser != null ? _currentUser!['id']?.toString() : null);
  }

  // ── Sign Up ──────────────────────────────────────────────

  static Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    String name = '',
  }) async {
    final res = await http.post(
      Uri.parse('${ApiService.baseUrl}/api/auth/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password, 'name': name}),
    ).timeout(const Duration(seconds: 15));

    final body = jsonDecode(res.body);
    if (res.statusCode == 201 || res.statusCode == 200) {
      return {'success': true, 'message': body['message'] ?? 'Account created!', 'needsVerification': body['needsVerification'] ?? true};
    } else {
      return {'success': false, 'message': body['error'] ?? 'Signup failed.'};
    }
  }

  // ── Verify Email ─────────────────────────────────────────

  static Future<Map<String, dynamic>> verifyEmail({
    required String email,
    required String code,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiService.baseUrl}/api/auth/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code}),
    ).timeout(const Duration(seconds: 15));

    final body = jsonDecode(res.body);
    if (res.statusCode == 200 && body['token'] != null) {
      _token = body['token'];
      _currentUser = body['user'];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, _token!);
      await prefs.setString(_userKey, jsonEncode(_currentUser));
      await LocalHistoryService.setUser(_currentUser!['id']?.toString());
      return {'success': true, 'message': body['message'] ?? 'Verified!'};
    } else {
      return {'success': false, 'message': body['error'] ?? body['message'] ?? 'Verification failed.'};
    }
  }

  // ── Resend Verification Code ─────────────────────────────

  static Future<Map<String, dynamic>> resendCode({required String email}) async {
    final res = await http.post(
      Uri.parse('${ApiService.baseUrl}/api/auth/resend-code'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    ).timeout(const Duration(seconds: 15));

    final body = jsonDecode(res.body);
    return {'success': res.statusCode == 200, 'message': body['message'] ?? body['error'] ?? 'Request failed.'};
  }

  // ── Forgot Password ──────────────────────────────────────

  static Future<Map<String, dynamic>> forgotPassword({required String email}) async {
    final res = await http.post(
      Uri.parse('${ApiService.baseUrl}/api/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    ).timeout(const Duration(seconds: 15));

    final body = jsonDecode(res.body);
    return {'success': res.statusCode == 200, 'message': body['message'] ?? body['error'] ?? 'Request failed.'};
  }

  // ── Reset Password ───────────────────────────────────────

  static Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiService.baseUrl}/api/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code, 'newPassword': newPassword}),
    ).timeout(const Duration(seconds: 15));

    final body = jsonDecode(res.body);
    if (res.statusCode == 200 && body['token'] != null) {
      _token = body['token'];
      _currentUser = body['user'];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, _token!);
      await prefs.setString(_userKey, jsonEncode(_currentUser));
      await LocalHistoryService.setUser(_currentUser!['id']?.toString());
      return {'success': true, 'message': body['message'] ?? 'Password reset!'};
    }
    return {'success': false, 'message': body['error'] ?? body['message'] ?? 'Reset failed.'};
  }

  // ── Login ────────────────────────────────────────────────

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiService.baseUrl}/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    ).timeout(const Duration(seconds: 15));

    final body = jsonDecode(res.body);
    if (res.statusCode == 200 && body['token'] != null) {
      _token = body['token'];
      _currentUser = body['user'];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, _token!);
      await prefs.setString(_userKey, jsonEncode(_currentUser));
      await LocalHistoryService.setUser(_currentUser!['id']?.toString());
      return {'success': true, 'message': body['message'] ?? 'Signed in!'};
    } else if (res.statusCode == 403 && body['needsVerification'] == true) {
      return {'success': false, 'message': body['error'], 'needsVerification': true};
    } else {
      return {'success': false, 'message': body['error'] ?? 'Login failed.'};
    }
  }

  // ── Logout ───────────────────────────────────────────────

  static Future<void> logout() async {
    _token = null;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await LocalHistoryService.setUser(null);
  }

  // ── Get History ──────────────────────────────────────────

  static Future<Map<String, dynamic>> getHistory({int page = 1, int limit = 20}) async {
    if (_token == null) return {'success': false, 'message': 'Not logged in'};

    final res = await http.get(
      Uri.parse('${ApiService.baseUrl}/api/history?page=$page&limit=$limit'),
      headers: {'Authorization': 'Bearer $_token'},
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode == 200) {
      return {'success': true, ...jsonDecode(res.body)};
    }
    return {'success': false, 'message': 'Failed to load history.'};
  }

  // ── Get Stats ────────────────────────────────────────────

  static Future<Map<String, dynamic>> getStats() async {
    if (_token == null) return {'success': false, 'message': 'Not logged in'};

    final res = await http.get(
      Uri.parse('${ApiService.baseUrl}/api/history/stats'),
      headers: {'Authorization': 'Bearer $_token'},
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode == 200) {
      return {'success': true, ...jsonDecode(res.body)};
    }
    return {'success': false, 'message': 'Failed to load stats.'};
  }

  // ── Delete History Item ──────────────────────────────────

  static Future<bool> deleteHistoryItem(int id) async {
    if (_token == null) return false;

    final res = await http.delete(
      Uri.parse('${ApiService.baseUrl}/api/history/$id'),
      headers: {'Authorization': 'Bearer $_token'},
    ).timeout(const Duration(seconds: 10));

    return res.statusCode == 200;
  }
}
