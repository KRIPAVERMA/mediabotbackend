import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D17),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildAppHeader(),
                const SizedBox(height: 28),
                _buildSection(
                  icon: '🤖',
                  title: 'About MediaBot',
                  child: const Text(
                    'MediaBot is a powerful media downloader app that lets you '
                    'save videos and extract audio from YouTube, Instagram, and Facebook '
                    '— directly to your device.\n\n'
                    'Simply share any reel, video, or post to MediaBot, choose your '
                    'preferred format (MP4 video or MP3 audio), and the download starts '
                    'instantly. No ads, no tracking, just fast and easy media saving.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.65,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _buildSection(
                  icon: '⚡',
                  title: 'Features',
                  child: Column(
                    children: const [
                      _FeatureRow(icon: '▶️', text: 'Download YouTube videos & reels'),
                      _FeatureRow(icon: '📸', text: 'Download Instagram reels & posts'),
                      _FeatureRow(icon: '📘', text: 'Download Facebook videos'),
                      _FeatureRow(icon: '🎵', text: 'Extract MP3 audio from any platform'),
                      _FeatureRow(icon: '📤', text: 'Share directly from Instagram / YouTube'),
                      _FeatureRow(icon: '📋', text: 'Full download history with stats'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _buildSection(
                  icon: '👨‍💻',
                  title: 'Developer',
                  child: Column(
                    children: [
                      _InfoRow(
                        label: 'Name',
                        value: 'Kripa Verma',
                        icon: Icons.person_outline_rounded,
                      ),
                      const SizedBox(height: 14),
                      _InfoRow(
                        label: 'Email',
                        value: 'kripaverma410@gmail.com',
                        icon: Icons.email_outlined,
                        copyable: true,
                      ),
                      const SizedBox(height: 14),
                      _InfoRow(
                        label: 'Phone',
                        value: '+91 8302310198',
                        icon: Icons.phone_outlined,
                        copyable: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _buildSection(
                  icon: '🛡️',
                  title: 'Legal',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _legalBlock(
                        'Terms of Use',
                        'MediaBot is designed for personal use only. Users are solely responsible for ensuring '
                        'they have the right to download and use any content. Please respect the copyright and '
                        'intellectual property rights of content creators and platform terms of service.',
                      ),
                      const SizedBox(height: 14),
                      _legalBlock(
                        'Privacy',
                        'MediaBot does not collect, store, or transmit any personal data or download history '
                        'to external servers. All data is stored locally on your device only.',
                      ),
                      const SizedBox(height: 14),
                      _legalBlock(
                        'Disclaimer',
                        'This application is an independent project and is not affiliated with, endorsed by, '
                        'or connected to YouTube, Instagram, Facebook, or any of their parent companies. '
                        'All trademarks belong to their respective owners.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                _buildCopyrightFooter(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── App Bar ───────────────────────────────────────────────────

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      backgroundColor: const Color(0xFF0B0D17),
      elevation: 0,
      pinned: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 20),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const Text(
        'About',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      centerTitle: true,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: Colors.white.withValues(alpha: 0.07),
        ),
      ),
    );
  }

  // ── App Header (logo + name + version) ───────────────────────

  Widget _buildAppHeader() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 32),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A1D2E), Color(0xFF0B0D17)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFA78BFA).withValues(alpha: 0.25),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Text('🤖', style: TextStyle(fontSize: 44)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'MediaBot',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFA78BFA), Color(0xFFF472B6)],
            ).createShader(bounds),
            child: const Text(
              'Media Downloader & Audio Extractor',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: const Text(
              'Version 1.0.0',
              style: TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section card ─────────────────────────────────────────────

  Widget _buildSection({required String icon, required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // ── Legal text block ─────────────────────────────────────────

  Widget _legalBlock(String heading, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFA78BFA)),
        ),
        const SizedBox(height: 5),
        Text(
          body,
          style: const TextStyle(
            fontSize: 12.5,
            color: Colors.white54,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  // ── Copyright footer ─────────────────────────────────────────

  Widget _buildCopyrightFooter() {
    return Column(
      children: [
        Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.15),
                Colors.transparent,
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFA78BFA), Color(0xFFF472B6)],
          ).createShader(bounds),
          child: const Text(
            'MediaBot',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '© 2026 MediaBot. All rights reserved.',
          style: const TextStyle(
              fontSize: 13, color: Colors.white54, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        const Text(
          'Developed & designed by Kripa Verma',
          style: TextStyle(fontSize: 12, color: Colors.white38),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        // Developer contact row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _contactChip(Icons.email_outlined, 'kripaverma410@gmail.com'),
            const SizedBox(width: 10),
            _contactChip(Icons.phone_outlined, '+91 83023 10198'),
          ],
        ),
        const SizedBox(height: 30),
        Text(
          'Made with ❤️ in India',
          style: TextStyle(
              fontSize: 12, color: Colors.white.withValues(alpha: 0.25)),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _contactChip(IconData icon, String label) {
    return GestureDetector(
      onTap: () => Clipboard.setData(ClipboardData(text: label)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: const Color(0xFFA78BFA)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────

class _FeatureRow extends StatelessWidget {
  final String icon;
  final String text;
  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool copyable;
  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
    this.copyable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFA78BFA).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: const Color(0xFFA78BFA), size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (copyable)
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$label copied'),
                  backgroundColor: const Color(0xFF1A1D2E),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.copy_rounded,
                  size: 15, color: Colors.white.withValues(alpha: 0.4)),
            ),
          ),
      ],
    );
  }
}
