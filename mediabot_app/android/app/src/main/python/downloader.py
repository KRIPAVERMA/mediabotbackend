"""
MediaBot on-device downloader using yt-dlp.
Runs inside Chaquopy's embedded Python on Android.
Downloads use the user's own IP — no server needed, no YouTube blocking.
"""

import os
import json
import yt_dlp


def download_media(url, output_dir, mode):
    """
    Download media from YouTube / Instagram / Facebook.

    Args:
        url: The media URL to download.
        output_dir: Directory to save the file.
        mode: One of 'youtube-video', 'youtube-mp3', 'instagram-video',
              'instagram-mp3', 'facebook-video', 'facebook-mp3'.

    Returns:
        JSON string with {status, filename, filepath, title} or {status, error}.
    """
    try:
        is_audio = mode.endswith("-mp3")

        # Common options
        ydl_opts = {
            "no_warnings": True,
            "noplaylist": True,
            "quiet": True,
            "no_color": True,
            # Avoid geo-restricted issues
            "geo_bypass": True,
        }

        if is_audio:
            # Extract best audio — no ffmpeg on Android, download native m4a/mp4a
            # (m4a plays fine on all Android media players)
            ydl_opts.update({
                "format": "bestaudio[ext=m4a]/bestaudio[ext=mp4]/bestaudio/best[height<=480]",
                "outtmpl": os.path.join(output_dir, "%(title).80s.%(ext)s"),
                # No postprocessors — ffmpeg is not available on-device
            })
        else:
            # Download video — use a pre-merged single file to avoid ffmpeg merge
            # bestvideo+bestaudio format requires ffmpeg, so prefer best[ext=mp4]
            ydl_opts.update({
                "format": "best[ext=mp4]/best[height<=720][ext=mp4]/best",
                "outtmpl": os.path.join(output_dir, "%(title).80s.%(ext)s"),
            })

        # For Instagram / Facebook, add cookies handling
        platform = mode.split("-")[0]
        if platform in ("instagram", "facebook"):
            ydl_opts["http_headers"] = {
                "User-Agent": "Mozilla/5.0 (Linux; Android 13; Pixel 7) "
                              "AppleWebKit/537.36 (KHTML, like Gecko) "
                              "Chrome/120.0.0.0 Mobile Safari/537.36"
            }

        # Run download
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=True)
            title = info.get("title", "media")

            # Find the actual downloaded file
            filepath = ydl.prepare_filename(info)
            if not os.path.exists(filepath):
                # Try to find any recently created file
                files = sorted(
                    [os.path.join(output_dir, f) for f in os.listdir(output_dir)],
                    key=os.path.getmtime,
                    reverse=True
                )
                if files:
                    filepath = files[0]
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
        JSON string with {status, title, duration, thumbnail} or {status, error}.
    """
    try:
        ydl_opts = {
            "quiet": True,
            "no_warnings": True,
            "no_color": True,
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
