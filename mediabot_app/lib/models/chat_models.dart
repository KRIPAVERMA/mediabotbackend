/// Represents a single download mode the bot supports.
class DownloadMode {
  final String id;        // e.g. "youtube-video"
  final String icon;      // emoji
  final String label;     // e.g. "YouTube Video"
  final String platform;  // "YouTube", "Instagram", "Facebook"
  final String format;    // "MP4", "MP3"
  final String desc;      // short description

  const DownloadMode({
    required this.id,
    required this.icon,
    required this.label,
    required this.platform,
    required this.format,
    required this.desc,
  });
}

const List<DownloadMode> downloadModes = [
  DownloadMode(id: 'youtube-video',   icon: '🎬', label: 'YouTube Video',   platform: 'YouTube',   format: 'MP4', desc: 'Download as MP4'),
  DownloadMode(id: 'youtube-mp3',     icon: '🎵', label: 'YouTube → MP3',   platform: 'YouTube',   format: 'MP3', desc: 'Extract audio'),
  DownloadMode(id: 'instagram-video', icon: '📸', label: 'Instagram Reel',  platform: 'Instagram', format: 'MP4', desc: 'Download video'),
  DownloadMode(id: 'instagram-mp3',   icon: '🎧', label: 'Instagram → MP3', platform: 'Instagram', format: 'MP3', desc: 'Extract audio'),
  DownloadMode(id: 'facebook-video',  icon: '📘', label: 'Facebook Video',  platform: 'Facebook',  format: 'MP4', desc: 'Download as MP4'),
  DownloadMode(id: 'facebook-mp3',    icon: '🔊', label: 'Facebook → MP3',  platform: 'Facebook',  format: 'MP3', desc: 'Extract audio'),
];

/// A chat message bubble.
enum MsgSender { bot, user }
enum MsgType { text, options, urlInput, progress }

class ChatMessage {
  final MsgSender sender;
  final MsgType type;
  final String text;
  final bool disabled;                  // for graying out old option/input rows
  final DownloadMode? selectedMode;     // used for urlInput type

  const ChatMessage({
    required this.sender,
    this.type = MsgType.text,
    this.text = '',
    this.disabled = false,
    this.selectedMode,
  });

  ChatMessage copyWith({bool? disabled}) => ChatMessage(
    sender: sender,
    type: type,
    text: text,
    disabled: disabled ?? this.disabled,
    selectedMode: selectedMode,
  );
}
