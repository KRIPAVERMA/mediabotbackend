import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ApiService {
  // ── CHANGE THIS to your server's address ──
  // • For emulator:   http://10.0.2.2:3000
  // • For real device: http://<your-pc-ip>:3000
  // • For deployed:    https://your-server.example.com
  static String baseUrl = 'http://10.0.2.2:3000';

  /// Downloads a file from the API and saves it to the device.
  /// Returns the saved file path on success, or throws on error.
  static Future<String> download({
    required String url,
    required String mode,
    required String format,
  }) async {
    final uri = Uri.parse('$baseUrl/api/download');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: '{"url":"$url","mode":"$mode"}',
    ).timeout(const Duration(minutes: 5));

    if (response.statusCode != 200) {
      // Try to extract error message
      String errMsg = 'Download failed (${response.statusCode})';
      try {
        final body = response.body;
        // Simple JSON parse for "error" field
        final match = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(body);
        if (match != null) errMsg = match.group(1)!;
      } catch (_) {}
      throw Exception(errMsg);
    }

    // Determine filename from Content-Disposition or generate one
    String filename = 'mediabot_${DateTime.now().millisecondsSinceEpoch}.${format.toLowerCase()}';
    final disposition = response.headers['content-disposition'];
    if (disposition != null) {
      final match = RegExp(r'filename="?([^";\n]+)"?').firstMatch(disposition);
      if (match != null) filename = match.group(1)!;
    }

    // Save to downloads-accessible directory
    final dir = await _getDownloadDir();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(response.bodyBytes);
    return file.path;
  }

  static Future<Directory> _getDownloadDir() async {
    // Try external storage first (visible in file manager)
    if (Platform.isAndroid) {
      final extDir = Directory('/storage/emulated/0/Download');
      if (await extDir.exists()) return extDir;
    }
    // Fallback to app directory
    return await getApplicationDocumentsDirectory();
  }
}
