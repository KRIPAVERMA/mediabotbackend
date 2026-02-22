import 'dart:convert';
import 'package:flutter/services.dart';

/// Service that bridges Flutter → Android (Kotlin) → Chaquopy (Python) → yt-dlp.
/// Downloads run on-device using the user's own IP, avoiding server-side YouTube blocks.
class YtDlpService {
  static const _channel = MethodChannel('yt_dlp_channel');

  /// Download media using on-device yt-dlp.
  /// Returns the file path on success, throws on failure.
  static Future<String> download({
    required String url,
    required String mode,
  }) async {
    final response = await _channel.invokeMethod<String>('download', {
      'url': url,
      'mode': mode,
    });

    if (response == null) {
      throw Exception('No response from native downloader');
    }

    final result = jsonDecode(response) as Map<String, dynamic>;

    if (result['status'] == 'success') {
      return result['filepath'] as String;
    } else {
      throw Exception(result['error'] ?? 'Download failed');
    }
  }

  /// Get media info without downloading.
  /// Returns a map with title, duration, thumbnail.
  static Future<Map<String, dynamic>> getInfo(String url) async {
    final response = await _channel.invokeMethod<String>('getInfo', {
      'url': url,
    });

    if (response == null) {
      throw Exception('No response from native info fetcher');
    }

    final result = jsonDecode(response) as Map<String, dynamic>;

    if (result['status'] == 'success') {
      return result;
    } else {
      throw Exception(result['error'] ?? 'Failed to get info');
    }
  }
}
