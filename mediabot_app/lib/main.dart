import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'services/auth_service.dart';
import 'screens/auth_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/share_download_screen.dart';

/// Global navigator key so we can push screens from outside widget tree.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.init();
  // LocalHistoryService is initialized inside AuthService.init() via setUser()
  runApp(const MediaBotApp());
}

class MediaBotApp extends StatefulWidget {
  const MediaBotApp({super.key});

  @override
  State<MediaBotApp> createState() => _MediaBotAppState();
}

class _MediaBotAppState extends State<MediaBotApp> {
  bool _isAuthenticated = AuthService.isLoggedIn;
  StreamSubscription<List<SharedMediaFile>>? _intentSub;

  void _onAuthenticated() => setState(() => _isAuthenticated = true);
  void _onLoggedOut() => setState(() => _isAuthenticated = false);

  @override
  void initState() {
    super.initState();
    _initSharingIntent();
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    super.dispose();
  }

  void _initSharingIntent() {
    // While app is running in foreground/background
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> files) {
        if (files.isNotEmpty) {
          final url = files.first.path.trim();
          if (url.isNotEmpty) _openShareScreen(url);
        }
      },
    );

    // URL that launched the app from a share action
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> files) {
      if (files.isNotEmpty) {
        final url = files.first.path.trim();
        if (url.isNotEmpty) _openShareScreen(url);
      }
      ReceiveSharingIntent.instance.reset();
    });
  }

  void _openShareScreen(String url) {
    // Wait until the navigator is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ShareDownloadScreen(sharedUrl: url),
          fullscreenDialog: true,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediaBot',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0D17),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFA78BFA),
          secondary: Color(0xFFF472B6),
          surface: Color(0xFF0B0D17),
        ),
      ),
      home: _isAuthenticated
          ? ChatScreen(onLogout: _onLoggedOut)
          : AuthScreen(onAuthenticated: _onAuthenticated),
    );
  }
}
