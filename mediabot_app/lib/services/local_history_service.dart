import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores download history locally on-device using SharedPreferences.
/// History is scoped per-user so different accounts never share data.
class LocalHistoryService {
  static String? _userId;
  static String get _key =>
      _userId != null ? 'local_download_history_$_userId' : 'local_download_history_guest';
  static List<Map<String, dynamic>> _cache = [];

  /// Call this after login/logout so history is scoped to the right user.
  /// Pass null to switch to guest/logged-out scope.
  static Future<void> setUser(String? userId) async {
    _userId = userId;
    _cache = [];
    await _loadFromDisk();
  }

  /// Load history from disk into memory cache.
  static Future<void> init() async => _loadFromDisk();

  static Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _cache = list.cast<Map<String, dynamic>>();
      } catch (_) {
        _cache = [];
      }
    } else {
      _cache = [];
    }
  }

  /// Add a successful download to local history.
  static Future<void> addEntry({
    required String url,
    required String mode,
    required String platform,
    required String format,
    required String filename,
    required String filePath,
  }) async {
    final entry = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'url': url,
      'mode': mode,
      'platform': platform,
      'format': format,
      'filename': filename,
      'filePath': filePath,
      'status': 'success',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    _cache.insert(0, entry); // newest first

    // Keep at most 200 entries
    if (_cache.length > 200) _cache = _cache.sublist(0, 200);

    await _save();
  }

  /// Get all local history entries (newest first).
  static List<Map<String, dynamic>> getAll() => List.unmodifiable(_cache);

  /// Get paginated history.
  static Map<String, dynamic> getPage({int page = 1, int limit = 20}) {
    final total = _cache.length;
    final offset = (page - 1) * limit;
    final end = (offset + limit).clamp(0, total);
    final items = offset < total ? _cache.sublist(offset, end) : <Map<String, dynamic>>[];
    return {
      'history': items,
      'pagination': {
        'page': page,
        'limit': limit,
        'total': total,
        'pages': (total / limit).ceil().clamp(1, 9999),
      },
    };
  }

  /// Get stats from local history.
  static Map<String, dynamic> getStats() {
    int audio = 0, video = 0, youtube = 0, instagram = 0, facebook = 0;
    for (final e in _cache) {
      if (e['format'] == 'MP3') audio++;
      if (e['format'] == 'MP4') video++;
      final p = (e['platform'] as String? ?? '').toLowerCase();
      if (p == 'youtube') youtube++;
      if (p == 'instagram') instagram++;
      if (p == 'facebook') facebook++;
    }
    return {
      'totalDownloads': _cache.length,
      'audioDownloads': audio,
      'videoDownloads': video,
      'youtube': youtube,
      'instagram': instagram,
      'facebook': facebook,
    };
  }

  /// Delete a local history entry by id.
  static Future<bool> deleteEntry(int id) async {
    final before = _cache.length;
    _cache.removeWhere((e) => e['id'] == id);
    if (_cache.length < before) {
      await _save();
      return true;
    }
    return false;
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_cache));
  }
}
