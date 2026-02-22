import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  /// Incremented whenever a download is recorded — HistoryScreen listens to refresh.
  static final historyNotifier = ValueNotifier<int>(0);

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
        print('[AuthService.init] Validating token via /api/auth/me ...');
        final res = await http.get(
          Uri.parse('${ApiService.baseUrl}/api/auth/me'),
          headers: {'Authorization': 'Bearer $_token'},
        ).timeout(const Duration(seconds: 5));

        print('[AuthService.init] /api/auth/me status=${res.statusCode}');
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          _currentUser = body['user'];
          await prefs.setString(_userKey, jsonEncode(_currentUser));
          print('[AuthService.init] Token valid. User: ${_currentUser?['email']}');
        } else {
          // Token expired
          print('[AuthService.init] Token EXPIRED (status ${res.statusCode}). Logging out.');
          await logout();
        }
      } catch (e) {
        // Network error — keep cached user, don't logout
        print('[AuthService.init] Network error checking token: $e — keeping cached user');
      }
    } else {
      print('[AuthService.init] No token found in storage.');
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
    if (_token == null) {
      print('[getHistory] SKIPPED — no token');
      return {'success': false, 'message': 'Not logged in'};
    }

    try {
      print('[getHistory] GET ${ApiService.baseUrl}/api/history?page=$page&limit=$limit');
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/history?page=$page&limit=$limit'),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 10));

      print('[getHistory] status=${res.statusCode}, bodyLen=${res.body.length}');
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        print('[getHistory] success, historyCount=${(decoded['history'] as List?)?.length ?? 0}');
        return {'success': true, ...decoded};
      }
      print('[getHistory] FAILED status=${res.statusCode}, body=${res.body}');
      return {'success': false, 'message': 'Server returned ${res.statusCode}'};
    } catch (e) {
      print('[getHistory] ERROR: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
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

  // ── Record History (for on-device downloads) ─────────────

  /// Records a download in server history when the download was done
  /// on-device via yt-dlp (not through the server download endpoint).
  static Future<void> recordHistory({
    required String url,
    required String mode,
    String? platform,
    String? format,
    String? filename,
    String? title,
  }) async {
    print('[recordHistory] called. token=${_token != null ? "present" : "NULL"}, url=$url, mode=$mode');
    if (_token == null) {
      print('[recordHistory] SKIPPED — no token');
      return;
    }

    final body = jsonEncode({
      'url': url,
      'mode': mode,
      'platform': platform,
      'format': format,
      'filename': filename,
      'title': title,
    });
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_token',
    };

    // Try up to 2 times in case of transient network error
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        print('[recordHistory] attempt $attempt → POST ${ApiService.baseUrl}/api/history');
        final res = await http.post(
          Uri.parse('${ApiService.baseUrl}/api/history'),
          headers: headers,
          body: body,
        ).timeout(const Duration(seconds: 10));

        print('[recordHistory] attempt $attempt → status=${res.statusCode}, body=${res.body}');
        if (res.statusCode == 200 || res.statusCode == 201) {
          // Saved successfully — tell HistoryScreen to refresh
          historyNotifier.value++;
          return;
        }
        // Server returned an error — retry after short delay
        if (attempt < 2) await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        print('[recordHistory] attempt $attempt ERROR: $e');
        if (attempt < 2) await Future.delayed(const Duration(seconds: 2));
      }
    }
    print('[recordHistory] BOTH attempts failed — triggering refresh anyway');
    // Both attempts failed — still trigger a refresh so the screen at least tries
    historyNotifier.value++;
  }
}
