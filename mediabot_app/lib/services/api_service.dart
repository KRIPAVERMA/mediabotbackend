import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'auth_service.dart';

class ApiService {
  static String baseUrl = 'http://172.17.85.200:3000';

  /// Downloads a file directly from the local server.
  /// POST /api/download with url & mode → server runs yt-dlp and streams the file back.
  static Future<String> download({
    required String url,
    required String mode,
    required String format,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = AuthService.token;
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final res = await http.post(
      Uri.parse('$baseUrl/api/download'),
      headers: headers,
      body: jsonEncode({'url': url, 'mode': mode}),
    ).timeout(const Duration(minutes: 5));

    if (res.statusCode != 200) {
      String errMsg = 'Download failed (${res.statusCode})';
      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        if (body['error'] != null) errMsg = body['error'].toString();
      } catch (_) {}
      throw Exception(errMsg);
    }

    // Determine filename from Content-Disposition header
    String filename =
        'mediabot_${DateTime.now().millisecondsSinceEpoch}.${format.toLowerCase()}';
    final disposition = res.headers['content-disposition'];
    if (disposition != null) {
      final match =
          RegExp(r'filename="?([^";\n]+)"?').firstMatch(disposition);
      if (match != null) filename = match.group(1)!;
    }

    final dir = await _getDownloadDir();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(res.bodyBytes);
    return file.path;
  }

  static Future<Directory> _getDownloadDir() async {
    if (Platform.isAndroid) {
      final extDir = Directory('/storage/emulated/0/Download');
      if (await extDir.exists()) return extDir;
    }
    return await getApplicationDocumentsDirectory();
  }
}
