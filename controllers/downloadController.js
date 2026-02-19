/**
 * Download Controller
 * Handles multi-mode downloads:
 *   youtube-video   → download YouTube video as MP4
 *   youtube-mp3     → extract YouTube audio as MP3
 *   instagram-video → download Instagram reel/post video
 *   instagram-mp3   → extract Instagram audio as MP3
 *   facebook-video  → download Facebook video as MP4
 *   facebook-mp3    → extract Facebook audio as MP3
 */

const { exec } = require("child_process");
const path = require("path");
const fs = require("fs");
const { v4: uuidv4 } = require("uuid");
const jwt = require("jsonwebtoken");
const { validateURL, sanitizeURL } = require("../utils/validator");
const db = require("../db/database");
const { JWT_SECRET } = require("../middleware/auth");

const DOWNLOADS_DIR = path.join(__dirname, "..", "downloads");
if (!fs.existsSync(DOWNLOADS_DIR)) {
  fs.mkdirSync(DOWNLOADS_DIR, { recursive: true });
}

// Valid modes the API accepts
const VALID_MODES = ["youtube-video", "youtube-mp3", "instagram-video", "instagram-mp3", "facebook-video", "facebook-mp3"];

/**
 * POST /api/download
 * Body: { url: string, mode: string }
 */
async function handleDownload(req, res) {
  const { url, mode } = req.body;

  // ── 1. Validate mode ─────────────────────────────────────────
  if (!mode || !VALID_MODES.includes(mode)) {
    return res.status(400).json({
      error: `Invalid mode. Choose one of: ${VALID_MODES.join(", ")}`,
    });
  }

  const expectedPlatform = mode.startsWith("youtube") ? "youtube"
    : mode.startsWith("instagram") ? "instagram"
    : "facebook";
  const isAudio = mode.endsWith("mp3");

  // ── 2. Validate URL ──────────────────────────────────────────
  const { valid, error } = validateURL(url, expectedPlatform);
  if (!valid) {
    return res.status(400).json({ error });
  }

  const safeURL = sanitizeURL(url.trim());
  const fileId = uuidv4();
  const outputTemplate = path.join(DOWNLOADS_DIR, `${fileId}.%(ext)s`);

  // ── 3. Build yt-dlp command ──────────────────────────────────
  let command;
  if (isAudio) {
    // Extract audio as MP3
    command = `yt-dlp -x --audio-format mp3 --no-playlist -o "${outputTemplate}" "${safeURL}"`;
  } else {
    // Download best video (merge to mp4)
    command = `yt-dlp -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" --merge-output-format mp4 --no-playlist -o "${outputTemplate}" "${safeURL}"`;
  }

  try {
    // ── 4. Execute ──────────────────────────────────────────────
    await execPromise(command);

    // ── 5. Find the output file ─────────────────────────────────
    const expectedExt = isAudio ? ".mp3" : ".mp4";
    let outputFile = path.join(DOWNLOADS_DIR, `${fileId}${expectedExt}`);

    // Fallback: scan for any file starting with fileId
    if (!fs.existsSync(outputFile)) {
      const files = fs.readdirSync(DOWNLOADS_DIR).filter((f) => f.startsWith(fileId));
      if (files.length > 0) {
        outputFile = path.join(DOWNLOADS_DIR, files[0]);
      } else {
        return res.status(500).json({ error: "Download completed but output file not found." });
      }
    }

    const ext = path.extname(outputFile);
    const downloadName = `${fileId}${ext}`;

    // ── 5b. Record in download history (if user is authenticated) ─
    _recordHistory(req, url, mode, expectedPlatform, isAudio ? 'MP3' : 'MP4', downloadName);

    // ── 6. Stream back to user ──────────────────────────────────
    res.download(outputFile, downloadName, (err) => {
      // Cleanup
      fs.unlink(outputFile, (unlinkErr) => {
        if (unlinkErr) console.error("Cleanup error:", unlinkErr.message);
      });
      if (err && !res.headersSent) {
        console.error("Send error:", err.message);
        return res.status(500).json({ error: "Failed to send file." });
      }
    });
  } catch (execErr) {
    console.error("yt-dlp error:", execErr.message);
    cleanupPartialFiles(fileId);

    // Detect common Instagram private-post error
    const msg = execErr.message || "";
    if (expectedPlatform === "instagram" && (msg.includes("login") || msg.includes("private") || msg.includes("404"))) {
      return res.status(403).json({
        error: "This Instagram post appears to be private or unavailable. Only public posts/reels are supported.",
      });
    }

    return res.status(500).json({
      error: "Failed to download or convert. Make sure the URL is valid and the content is public.",
    });
  }
}

// ── Helpers ──────────────────────────────────────────────────────

function execPromise(command, timeoutMs = 300_000) {
  return new Promise((resolve, reject) => {
    exec(command, { timeout: timeoutMs }, (error, stdout, stderr) => {
      if (error) return reject(error);
      resolve(stdout);
    });
  });
}

function cleanupPartialFiles(fileId) {
  try {
    const files = fs.readdirSync(DOWNLOADS_DIR);
    for (const file of files) {
      if (file.startsWith(fileId)) {
        fs.unlinkSync(path.join(DOWNLOADS_DIR, file));
      }
    }
  } catch {
    // Best-effort cleanup
  }
}

/**
 * Silently record download in history if user has a valid JWT.
 * Does NOT block or fail the download if no token present.
 */
function _recordHistory(req, url, mode, platform, format, filename) {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) return;
    const token = authHeader.split(" ")[1];
    const decoded = jwt.verify(token, JWT_SECRET);
    if (!decoded.userId) return;

    const platformName = platform.charAt(0).toUpperCase() + platform.slice(1);
    db.prepare(
      "INSERT INTO download_history (user_id, url, mode, platform, format, filename) VALUES (?, ?, ?, ?, ?, ?)"
    ).run(decoded.userId, url, mode, platformName, format, filename || '');
  } catch {
    // Silently ignore — don't break the download for auth issues
  }
}

module.exports = { handleDownload };
