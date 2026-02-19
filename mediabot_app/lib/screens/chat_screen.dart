import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import '../models/chat_models.dart';
import '../services/api_service.dart';
import '../widgets/animated_background.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/option_cards.dart';
import '../widgets/progress_steps.dart';
import '../widgets/typing_indicator.dart';
import 'settings_sheet.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _urlCtrl = TextEditingController();

  // Chat items: each is either a ChatMessage, an OptionCards, a url-input row, or a progress widget
  final List<_ChatItem> _items = [];

  bool _showTyping = false;
  DownloadMode? _currentMode;
  int _progressStep = 0; // 0 = hidden, 1-4 = step

  @override
  void initState() {
    super.initState();
    _startConversation();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  // ── Conversation flow ───────────────────────────────────

  Future<void> _startConversation() async {
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() => _showTyping = true);
    _scrollToBottom();
    await Future.delayed(const Duration(milliseconds: 800));
    setState(() {
      _showTyping = false;
      _items.add(_ChatItem.text(
        MsgSender.bot,
        "Hey there! 👋 I'm MediaBot.\nI can download videos & extract audio from YouTube, Instagram & Facebook.\n\nWhat would you like to do?",
      ));
      _items.add(_ChatItem.options(disabled: false));
    });
    _scrollToBottom();
  }

  void _onModeSelected(DownloadMode mode) {
    setState(() {
      _currentMode = mode;
      _progressStep = 0;

      // Disable all previous option cards
      for (int i = 0; i < _items.length; i++) {
        if (_items[i].type == _ItemType.options) {
          _items[i] = _ChatItem.options(disabled: true);
        }
        if (_items[i].type == _ItemType.urlInput) {
          _items[i] = _ChatItem.urlInput(mode: _items[i].mode!, disabled: true);
        }
      }

      _items.add(_ChatItem.text(MsgSender.user, '${mode.icon} ${mode.label}'));
    });
    _scrollToBottom();

    Future.delayed(const Duration(milliseconds: 400), () {
      setState(() => _showTyping = true);
      _scrollToBottom();
    });

    Future.delayed(const Duration(milliseconds: 1000), () {
      setState(() {
        _showTyping = false;
        final warning = mode.platform != 'YouTube'
            ? '\n⚠ Only public posts/reels/videos are supported.'
            : '';
        _items.add(_ChatItem.text(
          MsgSender.bot,
          'Great choice! 🔥 Paste the ${mode.platform} link below and tap Go.$warning',
        ));
        _items.add(_ChatItem.urlInput(mode: mode, disabled: false));
      });
      _scrollToBottom();
      // Slightly delay to ensure the widget is built before focusing
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    });
  }

  Future<void> _onSubmitURL() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty || _currentMode == null) return;

    final mode = _currentMode!;
    _urlCtrl.clear();

    setState(() {
      // Disable the url input widget
      for (int i = 0; i < _items.length; i++) {
        if (_items[i].type == _ItemType.urlInput && !_items[i].disabled) {
          _items[i] = _ChatItem.urlInput(mode: _items[i].mode!, disabled: true);
        }
      }
      _items.add(_ChatItem.text(MsgSender.user, url));
      _progressStep = 1;
      _items.add(_ChatItem.progress());
    });
    _scrollToBottom();

    await Future.delayed(const Duration(milliseconds: 500));
    setState(() => _progressStep = 2);

    try {
      final filePath = await ApiService.download(
        url: url,
        mode: mode.id,
        format: mode.format,
      );

      setState(() => _progressStep = 3);
      await Future.delayed(const Duration(milliseconds: 400));
      setState(() => _progressStep = 4);
      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _progressStep = 0;
        _items.add(_ChatItem.text(
          MsgSender.bot,
          '✅ Done! Your ${mode.format} has been saved.\n📁 $filePath\n\nWant to download something else?',
        ));
        _items.add(_ChatItem.options(disabled: false));
      });
      _scrollToBottom();

      // Try to open the file
      try {
        await OpenFile.open(filePath);
      } catch (_) {}
    } catch (e) {
      setState(() {
        _progressStep = 0;
        String errMsg = e.toString().replaceFirst('Exception: ', '');
        _items.add(_ChatItem.text(
          MsgSender.bot,
          '❌ Error: $errMsg\n\nLet\'s try again — pick an option:',
        ));
        _items.add(_ChatItem.options(disabled: false));
      });
      _scrollToBottom();
    }
  }

  void _restart() {
    setState(() {
      _items.clear();
      _showTyping = false;
      _currentMode = null;
      _progressStep = 0;
      _urlCtrl.clear();
    });
    _startConversation();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Build ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildChat()),
                _buildBottomBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Color(0xFFA78BFA), Color(0xFFF472B6)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFA78BFA).withValues(alpha: 0.3),
                  blurRadius: 16,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Text('🤖', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'MediaBot',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF34D399).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '● Online',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF34D399)),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.settings,
                size: 20, color: Colors.white.withValues(alpha: 0.5)),
            onPressed: () => showModalBottomSheet(
              context: context,
              backgroundColor: const Color(0xFF1A1D2E),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => const SettingsSheet(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChat() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: _items.length + (_showTyping ? 1 : 0),
      itemBuilder: (context, index) {
        // Typing indicator at the end
        if (index == _items.length && _showTyping) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFA78BFA), Color(0xFFF472B6)],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text('🤖', style: TextStyle(fontSize: 15)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.07)),
                  ),
                  child: const TypingIndicator(),
                ),
              ],
            ),
          );
        }

        final item = _items[index];
        return _buildItem(item);
      },
    );
  }

  Widget _buildItem(_ChatItem item) {
    switch (item.type) {
      case _ItemType.message:
        return ChatBubble(message: item.message!);
      case _ItemType.options:
        return OptionCards(
          disabled: item.disabled,
          onSelect: _onModeSelected,
        );
      case _ItemType.urlInput:
        return _buildURLInput(item.mode!, item.disabled);
      case _ItemType.progress:
        return ProgressSteps(currentStep: _progressStep);
    }
  }

  Widget _buildURLInput(DownloadMode mode, bool disabled) {
    final placeholder = mode.platform == 'YouTube'
        ? 'https://www.youtube.com/watch?v=...'
        : mode.platform == 'Instagram'
            ? 'https://www.instagram.com/reel/...'
            : 'https://www.facebook.com/watch/...';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Opacity(
        opacity: disabled ? 0.35 : 1.0,
        child: IgnorePointer(
          ignoring: disabled,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: disabled ? null : _urlCtrl,
                  enabled: !disabled,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: placeholder,
                    hintStyle:
                        TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFFA78BFA), width: 1.5),
                    ),
                  ),
                  onSubmitted: (_) => _onSubmitURL(),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: disabled ? null : _onSubmitURL,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFA78BFA), Color(0xFFF472B6)],
                      ),
                    ),
                    child: const Text(
                      'Go →',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _restart,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Text(
              '↻ Start Over',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Internal item model for the chat list ──────────────────

enum _ItemType { message, options, urlInput, progress }

class _ChatItem {
  final _ItemType type;
  final ChatMessage? message;
  final bool disabled;
  final DownloadMode? mode;

  const _ChatItem._({
    required this.type,
    this.message,
    this.disabled = false,
    this.mode,
  });

  factory _ChatItem.text(MsgSender sender, String text) => _ChatItem._(
        type: _ItemType.message,
        message: ChatMessage(sender: sender, text: text),
      );

  factory _ChatItem.options({required bool disabled}) =>
      _ChatItem._(type: _ItemType.options, disabled: disabled);

  factory _ChatItem.urlInput(
          {required DownloadMode mode, required bool disabled}) =>
      _ChatItem._(type: _ItemType.urlInput, mode: mode, disabled: disabled);

  factory _ChatItem.progress() =>
      _ChatItem._(type: _ItemType.progress);
}
