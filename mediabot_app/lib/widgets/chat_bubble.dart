import 'package:flutter/material.dart';
import '../models/chat_models.dart';

/// A single chat bubble (bot or user).
class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isBot = message.sender == MsgSender.bot;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment:
            isBot ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isBot) _avatar('🤖', isBot),
          if (isBot) const SizedBox(width: 8),
          Flexible(child: _bubble(isBot)),
          if (!isBot) const SizedBox(width: 8),
          if (!isBot) _avatar('😎', isBot),
        ],
      ),
    );
  }

  Widget _avatar(String emoji, bool isBot) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: isBot
            ? const LinearGradient(
                colors: [Color(0xFFA78BFA), Color(0xFFF472B6)])
            : null,
        color: isBot ? null : Colors.white.withValues(alpha: 0.08),
      ),
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 15)),
    );
  }

  Widget _bubble(bool isBot) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isBot
            ? Colors.white.withValues(alpha: 0.05)
            : const Color(0xFFA78BFA).withValues(alpha: 0.15),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isBot ? 4 : 16),
          topRight: Radius.circular(isBot ? 16 : 4),
          bottomLeft: const Radius.circular(16),
          bottomRight: const Radius.circular(16),
        ),
        border: Border.all(
          color: isBot
              ? Colors.white.withValues(alpha: 0.07)
              : const Color(0xFFA78BFA).withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        message.text,
        style: TextStyle(
          fontSize: 14,
          color: Colors.white.withValues(alpha: 0.9),
          height: 1.5,
        ),
      ),
    );
  }
}
