import 'dart:async';
import 'package:flutter/material.dart';
import '../models/chat_models.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/local_history_service.dart';
import 'package:open_file/open_file.dart';

/// Full-screen handler for URLs shared to MediaBot from other apps.
/// Flow: check login → choose platform mode → download → done.
class ShareDownloadScreen extends StatefulWidget {
  final String sharedUrl;
  const ShareDownloadScreen({super.key, required this.sharedUrl});

  @override
  State<ShareDownloadScreen> createState() => _ShareDownloadScreenState();
}

enum _ShareState { checkingAuth, needsLogin, choosingMode, downloading, done, error }

class _ShareDownloadScreenState extends State<ShareDownloadScreen> {
  _ShareState _state = _ShareState.checkingAuth;

  // Login form
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loginLoading = false;
  String? _loginError;
  bool _obscurePass = true;

  // Download
  String? _filePath;
  String? _errorMsg;
  DownloadMode? _chosenMode;
  double _downloadProgress = 0;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    // Short delay so the screen can render before we check state
    Future.delayed(const Duration(milliseconds: 200), _checkAuth);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _progressTimer?.cancel();
    super.dispose();
  }

  void _checkAuth() {
    setState(() {
      _state = AuthService.isLoggedIn ? _ShareState.choosingMode : _ShareState.needsLogin;
    });
  }

  /// Detect which platform the URL belongs to.
  String _detectPlatform(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('youtube.com') || lower.contains('youtu.be')) return 'YouTube';
    if (lower.contains('instagram.com')) return 'Instagram';
    if (lower.contains('facebook.com') || lower.contains('fb.watch')) return 'Facebook';
    return 'Unknown';
  }

  List<DownloadMode> _modesForPlatform(String platform) {
    return downloadModes.where((m) => m.platform == platform).toList();
  }

  // ── Login ────────────────────────────────────────────────

  Future<void> _doLogin() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _loginError = 'Please enter email and password.');
      return;
    }
    setState(() { _loginLoading = true; _loginError = null; });
    try {
      await AuthService.login(email: email, password: pass);
      setState(() { _loginLoading = false; _state = _ShareState.choosingMode; });
    } catch (e) {
      setState(() {
        _loginLoading = false;
        _loginError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── Download ─────────────────────────────────────────────

  Future<void> _startDownload(DownloadMode mode) async {
    setState(() {
      _chosenMode = mode;
      _state = _ShareState.downloading;
      _downloadProgress = 0;
    });

    // Fake progress animation while yt-dlp runs
    _progressTimer = Timer.periodic(const Duration(milliseconds: 300), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_downloadProgress < 0.85) _downloadProgress += 0.03;
      });
    });

    try {
      final path = await ApiService.download(
        url: widget.sharedUrl,
        mode: mode.id,
        format: mode.format,
      );
      _progressTimer?.cancel();

      final filename = path.split('/').last;
      await LocalHistoryService.addEntry(
        url: widget.sharedUrl,
        mode: mode.id,
        platform: mode.platform,
        format: mode.format,
        filename: filename,
        filePath: path,
      );

      setState(() {
        _filePath = path;
        _downloadProgress = 1.0;
        _state = _ShareState.done;
      });

      // Auto-open file
      try { await OpenFile.open(path); } catch (_) {}
    } catch (e) {
      _progressTimer?.cancel();
      setState(() {
        _errorMsg = e.toString().replaceFirst('Exception: ', '');
        _state = _ShareState.error;
      });
    }
  }

  // ── UI ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D17),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(colors: [Color(0xFFA78BFA), Color(0xFFF472B6)]),
            ),
            alignment: Alignment.center,
            child: const Text('🤖', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 10),
          const Text('MediaBot',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 22),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _ShareState.checkingAuth:
        return _buildLoading('Starting up…');
      case _ShareState.needsLogin:
        return _buildLoginForm();
      case _ShareState.choosingMode:
        return _buildModeChooser();
      case _ShareState.downloading:
        return _buildDownloading();
      case _ShareState.done:
        return _buildDone();
      case _ShareState.error:
        return _buildError();
    }
  }

  Widget _buildLoading(String msg) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: Color(0xFFA78BFA)),
        const SizedBox(height: 16),
        Text(msg, style: const TextStyle(color: Colors.white70)),
      ]),
    );
  }

  // ── Login form ──────────────────────────────────────────

  Widget _buildLoginForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Text('Sign in to MediaBot',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 6),
          Text('Log in to download: ${widget.sharedUrl.length > 50 ? '${widget.sharedUrl.substring(0, 50)}…' : widget.sharedUrl}',
              style: const TextStyle(fontSize: 12, color: Colors.white38)),
          const SizedBox(height: 28),
          _inputField(_emailCtrl, 'Email', Icons.email_outlined, false),
          const SizedBox(height: 14),
          _inputField(_passCtrl, 'Password', Icons.lock_outline, true),
          if (_loginError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_loginError!, style: const TextStyle(color: Color(0xFFFC8181), fontSize: 13)),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: _loginLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFA78BFA)))
                : _gradientButton('Sign In', _doLogin),
          ),
        ],
      ),
    );
  }

  Widget _inputField(TextEditingController ctrl, String hint, IconData icon, bool isPass) {
    return TextField(
      controller: ctrl,
      obscureText: isPass && _obscurePass,
      keyboardType: isPass ? TextInputType.visiblePassword : TextInputType.emailAddress,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white38, size: 18),
        suffixIcon: isPass
            ? IconButton(
                icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white38, size: 18),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              )
            : null,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: Color(0xFFA78BFA), width: 1.5),
        ),
      ),
    );
  }

  // ── Mode chooser ─────────────────────────────────────────

  Widget _buildModeChooser() {
    final platform = _detectPlatform(widget.sharedUrl);
    final modes = platform == 'Unknown'
        ? downloadModes
        : _modesForPlatform(platform);

    String platformIcon = '🔗';
    if (platform == 'YouTube') platformIcon = '▶️';
    if (platform == 'Instagram') platformIcon = '📸';
    if (platform == 'Facebook') platformIcon = '📘';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(platformIcon, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(platform == 'Unknown' ? 'Shared Link' : '$platform Link',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
              const Text('How would you like to download it?',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
            ]),
          ]),
          const SizedBox(height: 10),
          // URL preview
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Text(
              widget.sharedUrl,
              style: const TextStyle(fontSize: 11, color: Colors.white54),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 24),
          const Text('Choose format', style: TextStyle(fontSize: 13, color: Colors.white38, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ...modes.map((mode) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _modeCard(mode),
          )),
        ],
      ),
    );
  }

  Widget _modeCard(DownloadMode mode) {
    final isAudio = mode.format == 'MP3';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _startDownload(mode),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: isAudio
                  ? [const Color(0xFFA78BFA).withValues(alpha: 0.15), const Color(0xFFF472B6).withValues(alpha: 0.08)]
                  : [const Color(0xFF34D399).withValues(alpha: 0.12), const Color(0xFF06B6D4).withValues(alpha: 0.06)],
            ),
            border: Border.all(
              color: isAudio
                  ? const Color(0xFFA78BFA).withValues(alpha: 0.3)
                  : const Color(0xFF34D399).withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Text(mode.icon, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(mode.label,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text(mode.desc, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isAudio
                      ? const Color(0xFFA78BFA).withValues(alpha: 0.2)
                      : const Color(0xFF34D399).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(mode.format,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isAudio ? const Color(0xFFA78BFA) : const Color(0xFF34D399))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Downloading ──────────────────────────────────────────

  Widget _buildDownloading() {
    final mode = _chosenMode;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(mode?.icon ?? '⬇️', style: const TextStyle(fontSize: 52)),
            const SizedBox(height: 20),
            Text('Downloading ${mode?.format ?? ''}…',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 8),
            Text(mode?.label ?? '', style: const TextStyle(fontSize: 13, color: Colors.white54)),
            const SizedBox(height: 30),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _downloadProgress,
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFA78BFA)),
              ),
            ),
            const SizedBox(height: 12),
            Text('${(_downloadProgress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 13, color: Colors.white38)),
          ],
        ),
      ),
    );
  }

  // ── Done ─────────────────────────────────────────────────

  Widget _buildDone() {
    final mode = _chosenMode;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [const Color(0xFF34D399), const Color(0xFF06B6D4)],
                ),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 20),
            const Text('Download Complete!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 8),
            Text('Saved as ${mode?.format ?? 'file'}',
                style: const TextStyle(fontSize: 13, color: Colors.white54)),
            if (_filePath != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_filePath!,
                    style: const TextStyle(fontSize: 11, color: Colors.white38),
                    textAlign: TextAlign.center),
              ),
            ],
            const SizedBox(height: 30),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (_filePath != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      if (_filePath != null) OpenFile.open(_filePath!);
                    },
                  ),
                ),
              _gradientButton('Done', () => Navigator.of(context).pop()),
            ]),
          ],
        ),
      ),
    );
  }

  // ── Error ─────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('❌', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 20),
            const Text('Download Failed',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_errorMsg ?? 'Unknown error',
                  style: const TextStyle(color: Color(0xFFFC8181), fontSize: 13),
                  textAlign: TextAlign.center),
            ),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => setState(() {
                    _state = _ShareState.choosingMode;
                    _errorMsg = null;
                  }),
                  child: const Text('Try Again'),
                ),
              ),
              _gradientButton('Close', () => Navigator.of(context).pop()),
            ]),
          ],
        ),
      ),
    );
  }

  // ── Helper widgets ────────────────────────────────────────

  Widget _gradientButton(String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(colors: [Color(0xFFA78BFA), Color(0xFFF472B6)]),
          ),
          child: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 14)),
        ),
      ),
    );
  }
}
