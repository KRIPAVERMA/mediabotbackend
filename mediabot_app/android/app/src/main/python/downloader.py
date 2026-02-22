"""
MediaBot on-device downloader using yt-dlp.
Runs inside Chaquopy's embedded Python on Android.
Downloads use the user's own IP — no server needed, no YouTube blocking.

IMPORTANT: ffmpeg is NOT available on Android, so:
  - Video: must use pre-merged single-file formats (no bestvideo+bestaudio)
  - Audio: download native audio container (m4a/webm), no conversion to mp3
"""

import os
import json
import time
import yt_dlp


# ── shared HTTP headers ──────────────────────────────────────────────
_MOBILE_UA = (
    "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Mobile Safari/537.36"
)

_DESKTOP_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)


def _find_downloaded_file(output_dir, before_ts):
    """Find the most recently modified file created after before_ts."""
    candidates = []
    for f in os.listdir(output_dir):
        fp = os.path.join(output_dir, f)
        if os.path.isfile(fp) and os.path.getmtime(fp) >= before_ts:
            candidates.append(fp)
    if candidates:
        return max(candidates, key=os.path.getmtime)
    return None


def download_media(url, output_dir, mode):
    """
    Download media from YouTube / Instagram / Facebook.

    Args:
        url:        The media URL to download.
        output_dir: Directory to save the file.
        mode:       One of 'youtube-video', 'youtube-mp3',
                    'instagram-video', 'instagram-mp3',
                    'facebook-video', 'facebook-mp3'.

    Returns:
        JSON string  {status, filename, filepath, title}
                  or {status, error}.
    """
    try:
        is_audio = mode.endswith("-mp3")
        platform = mode.split("-")[0]   # youtube | instagram | facebook

        outtmpl = os.path.join(output_dir, "%(title).80s.%(ext)s")
        before_ts = time.time()

        # ── base options (all platforms) ────────────────────────────
        ydl_opts = {
            "no_warnings": True,
            "noplaylist":  True,
            "quiet":       True,
            "no_color":    True,
            "geo_bypass":  True,
            "socket_timeout": 30,
            "retries": 3,
            "outtmpl": outtmpl,
            # Refuse any format that would need a merge (no ffmpeg)
            "format_sort": ["res:720", "ext:mp4:m4a:mp3:ogg:webm"],
        }

        # ── format selection ────────────────────────────────────────
        if is_audio:
            # Pick the best single-stream audio file.
            # Prefer m4a (Android-native), fall back to anything.
            ydl_opts["format"] = (
                "bestaudio[ext=m4a]/"
                "bestaudio[ext=mp3]/"
                "bestaudio[ext=webm]/"
                "bestaudio/"
                "best"
            )
        else:
            # Pick the best *pre-merged* video (single file, no merge).
            # `best` in yt-dlp = best single-file format.
            # Prefer mp4 container; fall back to any extension.
            ydl_opts["format"] = (
                "best[ext=mp4][height<=720]/"
                "best[ext=mp4]/"
                "best[height<=720]/"
                "best"
            )

        # ── platform-specific tweaks ────────────────────────────────
        if platform == "youtube":
            ydl_opts["http_headers"] = {"User-Agent": _MOBILE_UA}

        elif platform == "instagram":
            ydl_opts["http_headers"] = {"User-Agent": _MOBILE_UA}

        elif platform == "facebook":
            ydl_opts["http_headers"] = {"User-Agent": _DESKTOP_UA}

        # ── download ────────────────────────────────────────────────
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=True)
            title = info.get("title", "media")

            # --- locate the file on disk ---
            filepath = ydl.prepare_filename(info)

            if not os.path.exists(filepath):
                # yt-dlp may have changed the extension
                found = _find_downloaded_file(output_dir, before_ts)
                if found:
                    filepath = found
                else:
                    return json.dumps({
                        "status": "error",
                        "error": "Download finished but file not found"
                    })

            filename = os.path.basename(filepath)
            return json.dumps({
                "status": "success",
                "title": title,
                "filename": filename,
                "filepath": filepath,
            })

    except Exception as e:
        return json.dumps({
            "status": "error",
            "error": str(e),
        })


def get_info(url):
    """
    Get video/audio info without downloading.

    Returns:
        JSON string  {status, title, duration, thumbnail}
                  or {status, error}.
    """
    try:
        ydl_opts = {
            "quiet": True,
            "no_warnings": True,
            "no_color": True,
            "http_headers": {"User-Agent": _MOBILE_UA},
        }
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            return json.dumps({
                "status": "success",
                "title": info.get("title", "Unknown"),
                "duration": info.get("duration", 0),
                "thumbnail": info.get("thumbnail", ""),
            })
    except Exception as e:
        return json.dumps({
            "status": "error",
            "error": str(e),
        })
