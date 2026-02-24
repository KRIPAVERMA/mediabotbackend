import 'package:flutter/material.dart';
import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/local_history_service.dart';
import '../services/ytdlp_service.dart';
import '../widgets/animated_background.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<dynamic> _history = [];
  Map<String, dynamic>? _stats;
  bool _loading = true;
  bool _isFetching = false;
  int _page = 1;
  int _totalPages = 1;

  // Tracks which history items are being re-downloaded
  final Set<int> _reDownloading = {};
  // Set when a new download fires while _loadData is already running
  bool _pendingRefresh = false;
  // Debug info shown on screen
  String _debugInfo = '';

  @override
  void initState() {
    super.initState();
    _loadData();
    // Refresh whenever a new download is recorded
    AuthService.historyNotifier.addListener(_onNewDownload);
  }

  @override
  void dispose() {
    AuthService.historyNotifier.removeListener(_onNewDownload);
    super.dispose();
  }

  void _onNewDownload() {
    _page = 1;
    if (_isFetching) {
      // A fetch is in progress; mark a pending refresh so it re-runs after
      _pendingRefresh = true;
    } else {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    // Prevent overlapping requests (rapid refresh clicks)
    if (_isFetching) return;
    _isFetching = true;

    if (mounted) setState(() => _loading = true);
    try {
      final loggedIn = AuthService.isLoggedIn;
      final hasToken = AuthService.token != null;
      final email = AuthService.currentUser?['email'] ?? 'null';
      print('[History] _loadData: loggedIn=$loggedIn, token=$hasToken, email=$email');

      // ── Try server history first (if logged in) ──
      bool serverOk = false;
      List<dynamic> serverHistory = [];
      Map<String, dynamic>? serverStats;
      int sTotalPages = 1;
      int sPage = 1;

      if (loggedIn) {
        try {
          final results = await Future.wait([
            AuthService.getHistory(page: _page),
            AuthService.getStats(),
          ]);
          final histResult = results[0];
          final statsResult = results[1];
          final hCount = (histResult['history'] as List?)?.length ?? 0;
          print('[History] server: success=${histResult['success']}, count=$hCount');

          if (histResult['success'] == true) {
            serverHistory = histResult['history'] ?? [];
            final pagination = histResult['pagination'];
            if (pagination != null) {
              sTotalPages = pagination['pages'] ?? 1;
              sPage = pagination['page'] ?? 1;
            }
            serverOk = true;
          }
          if (statsResult['success'] == true && statsResult['stats'] != null) {
            serverStats = statsResult['stats'];
          }
        } catch (e) {
          print('[History] server fetch error: $e');
        }
      }

      // ── Load local history ──
      final localData = LocalHistoryService.getPage(page: _page);
      final localHistory = localData['history'] as List<Map<String, dynamic>>;
      final localStats = LocalHistoryService.getStats();
      print('[History] local: ${localHistory.length} items, server: ${serverHistory.length} items, serverOk=$serverOk');

      // ── Merge: prefer server if it has data, else use local ──
      if (mounted) {
        setState(() {
          if (serverOk && serverHistory.isNotEmpty) {
            // Server has data — use it
            _history = serverHistory;
            _totalPages = sTotalPages;
            _page = sPage;
            _stats = serverStats;
            _debugInfo = 'Server: ${serverHistory.length} items ($email)';
          } else if (localHistory.isNotEmpty) {
            // Server empty/failed but local has data — use local
            _history = localHistory;
            final localPagination = localData['pagination'] as Map<String, dynamic>?;
            _totalPages = localPagination?['pages'] ?? 1;
            _page = localPagination?['page'] ?? 1;
            _stats = {'totalDownloads': localStats['totalDownloads'], 'videoDownloads': localStats['videoDownloads'], 'audioDownloads': localStats['audioDownloads']};
            _debugInfo = 'Local: ${localHistory.length} items${loggedIn ? '' : ' (not logged in)'}';
          } else {
            // Both empty
            _history = [];
            _totalPages = 1;
            _stats = serverStats;
            _debugInfo = loggedIn ? 'No history on server or device ($email)' : 'Not logged in, no local history';
          }
          _loading = false;
        });
      }
    } catch (e) {
      print('[History] ERROR: $e');
      if (mounted) {
        // Even on error, try to show local history
        final localData = LocalHistoryService.getPage(page: _page);
        final localHistory = localData['history'] as List<Map<String, dynamic>>;
        final localStats = LocalHistoryService.getStats();
        setState(() {
          if (localHistory.isNotEmpty) {
            _history = localHistory;
            final localPagination = localData['pagination'] as Map<String, dynamic>?;
            _totalPages = localPagination?['pages'] ?? 1;
            _page = localPagination?['page'] ?? 1;
            _stats = {'totalDownloads': localStats['totalDownloads'], 'videoDownloads': localStats['videoDownloads'], 'audioDownloads': localStats['audioDownloads']};
            _debugInfo = 'Local fallback: ${localHistory.length} items (server error)';
          } else {
            _history = [];
            _stats = null;
            _debugInfo = 'Error: $e';
          }
          _loading = false;
        });
        if (localHistory.isEmpty) {
          _showSnack('Failed to load history: ${e.toString().replaceFirst("Exception: ", "")}');
        }
      }
    } finally {
      _isFetching = false;
      // If a new download came in while we were fetching, refresh once more
      if (_pendingRefresh && mounted) {
        _pendingRefresh = false;
        _loadData();
      }
    }
  }

  /// Map platform + format to the mode ID used by YtDlpService.
  String _getModeId(String platform, String format) {
    final p = platform.toLowerCase();
    final f = format.toUpperCase();
    if (p == 'youtube') return f == 'MP3' ? 'youtube-mp3' : 'youtube-video';
    if (p == 'instagram') return f == 'MP3' ? 'instagram-mp3' : 'instagram-video';
    if (p == 'facebook') return f == 'MP3' ? 'facebook-mp3' : 'facebook-video';
    return 'youtube-video';
  }

  /// Re-download a history item on this device via yt-dlp.
  Future<void> _reDownloadItem(Map<String, dynamic> item) async {
    final id = item['id'] as int? ?? 0;
    final url = item['url'] ?? '';
    final platform = item['platform'] ?? '';
    final format = item['format'] ?? 'MP4';

    if (url.isEmpty) { _showSnack('No URL saved for this item.'); return; }

    setState(() => _reDownloading.add(id));
    try {
      final modeId = _getModeId(platform, format);
      final filePath = await YtDlpService.download(url: url, mode: modeId);
      if (!mounted) return;
      _showSnack('✅ Downloaded: ${filePath.split('/').last}');
      try { await OpenFile.open(filePath); } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      _showSnack('❌ ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _reDownloading.remove(id));
    }
  }

  /// Open the original URL in the external browser.
  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) { _showSnack('Invalid URL'); return; }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _showSnack('Could not open URL');
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(),
                if (_stats != null) _buildStats(),
                Expanded(
                  child: RefreshIndicator(
                    color: const Color(0xFFA78BFA),
                    backgroundColor: const Color(0xFF1A1D2E),
                    onRefresh: () async {
                      _page = 1;
                      await _loadData();
                    },
                    child: _loading ? _buildLoading() : _buildHistoryList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white70),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          const Text('📋', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Download History',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20, color: Colors.white54),
            onPressed: _loadData,
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final s = _stats!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statChip('Total', '${s['totalDownloads'] ?? 0}', const Color(0xFFA78BFA)),
          _statChip('Video', '${s['videoDownloads'] ?? 0}', const Color(0xFF60A5FA)),
          _statChip('Audio', '${s['audioDownloads'] ?? 0}', const Color(0xFFF472B6)),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
      ],
    );
  }

  Widget _buildLoading() {
    return const Center(child: CircularProgressIndicator(color: Color(0xFFA78BFA)));
  }

  Widget _buildHistoryList() {
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📭', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('No downloads yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.5))),
            const SizedBox(height: 4),
            Text('Your download history will appear here',
                style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.3))),
            if (_debugInfo.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _debugInfo,
                  style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.25)),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _history.length,
            itemBuilder: (context, index) => _buildHistoryItem(_history[index]),
          ),
        ),
        if (_totalPages > 1) _buildPagination(),
      ],
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> item) {
    final platform = item['platform'] ?? '';
    final format = item['format'] ?? '';
    final url = item['url'] ?? '';
    final createdAt = item['created_at'] ?? '';
    final id = item['id'] as int? ?? 0;

    String icon = '🎬';
    if (platform == 'YouTube') icon = format == 'MP3' ? '🎵' : '🎬';
    if (platform == 'Instagram') icon = format == 'MP3' ? '🎧' : '📸';
    if (platform == 'Facebook') icon = format == 'MP3' ? '🔊' : '📘';

    Color platformColor = const Color(0xFFA78BFA);
    if (platform == 'YouTube') platformColor = const Color(0xFFEF4444);
    if (platform == 'Instagram') platformColor = const Color(0xFFF472B6);
    if (platform == 'Facebook') platformColor = const Color(0xFF60A5FA);

    // Convert to IST (UTC+5:30) regardless of device timezone
    String dateStr = '';
    try {
      DateTime dt;
      if (createdAt is String && createdAt.isNotEmpty) {
        dt = DateTime.parse(createdAt); // 'Z' suffix handled as UTC
        if (!dt.isUtc) dt = dt.toUtc();
      } else {
        dt = DateTime.now().toUtc();
      }
      final ist = dt.add(const Duration(hours: 5, minutes: 30));
      final nowIst = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

      final h = ist.hour.toString().padLeft(2, '0');
      final m = ist.minute.toString().padLeft(2, '0');
      final timeStr = '$h:$m IST';
      final day = ist.day.toString().padLeft(2, '0');
      final month = ist.month.toString().padLeft(2, '0');

      if (ist.year == nowIst.year && ist.month == nowIst.month && ist.day == nowIst.day) {
        dateStr = 'Today  $timeStr';
      } else if (ist.year == nowIst.year && ist.month == nowIst.month && ist.day == nowIst.day - 1) {
        dateStr = 'Yesterday  $timeStr';
      } else {
        dateStr = '$day/$month/${ist.year}  $timeStr';
      }
    } catch (_) {
      dateStr = createdAt.toString();
    }

    // Truncate URL for display
    String displayUrl = url;
    if (displayUrl.length > 50) {
      displayUrl = '${displayUrl.substring(0, 50)}...';
    }

    final isReDownloading = _reDownloading.contains(id);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: platformColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(icon, style: const TextStyle(fontSize: 22)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: platformColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(platform, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: platformColor)),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(format, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.6))),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _openUrl(url),
                child: Text(
                  displayUrl,
                  style: TextStyle(
                    fontSize: 12,
                    color: const Color(0xFF60A5FA).withValues(alpha: 0.8),
                    decoration: TextDecoration.underline,
                    decorationColor: const Color(0xFF60A5FA).withValues(alpha: 0.4),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 3),
              Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3))),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Re-download button
            if (isReDownloading)
              const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFA78BFA)),
              )
            else
              Tooltip(
                message: 'Re-download',
                child: IconButton(
                  icon: const Icon(Icons.cloud_download_outlined, size: 20, color: Color(0xFFA78BFA)),
                  onPressed: () => _reDownloadItem(item),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ),

          ],
        ),
      ),
    );
  }

  Future<void> _openDownloadedFile(Map<String, dynamic> item) async {
    final filename = item['filename'] ?? '';
    final storedPath = item['filePath'] ?? '';

    if (filename.isEmpty && storedPath.isEmpty) {
      _showSnack('File info not available');
      return;
    }

    // Prefer the stored full path (local history), fall back to Download folder
    String filePath = storedPath;
    if (filePath.isEmpty || !await File(filePath).exists()) {
      final downloadDir = Directory('/storage/emulated/0/Download');
      filePath = '${downloadDir.path}/$filename';
    }

    if (!await File(filePath).exists()) {
      _showSnack('File not found: $filename');
      return;
    }

    try {
      final result = await OpenFile.open(filePath);
      if (result.type != ResultType.done) {
        _showSnack('Could not open file: ${result.message}');
      }
    } catch (e) {
      _showSnack('Error opening file: $e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A1D2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white54),
            onPressed: _page > 1
                ? () {
                    _page--;
                    _loadData();
                  }
                : null,
          ),
          Text('$_page / $_totalPages', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.white54),
            onPressed: _page < _totalPages
                ? () {
                    _page++;
                    _loadData();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
