/**
 * Download Controller — Async Job-Based Architecture
 *
 * Render free tier has a 30-second HTTP timeout. yt-dlp downloads can take
 * 1-3 minutes, so we use an async pattern:
 *
 *   POST /api/download       → validates, queues job, returns { jobId } instantly
 *   GET  /api/download/:id   → poll job status  { status, progress, ... }
 *   GET  /api/download/:id/file → stream the finished file to the client
 *
 * Jobs live in an in-memory Map (fine for a single-instance free tier).
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

const VALID_MODES = [
  "youtube-video", "youtube-mp3",
  "instagram-video", "instagram-mp3",
  "facebook-video", "facebook-mp3",
];

// ── In-memory job store ─────────────────────────────────────────
const jobs = new Map();

// Auto-cleanup: delete finished jobs & files older than 10 minutes
setInterval(() => {
  const TEN_MIN = 10 * 60 * 1000;
  for (const [id, job] of jobs) {
    if (Date.now() - job.createdAt > TEN_MIN) {
      if (job.filePath) {
        fs.unlink(job.filePath, () => {});
      }
      jobs.delete(id);
    }
  }
}, 60_000);

// ─────────────────────────────────────────────────────────────────
// POST /api/download  — start a download job
// ─────────────────────────────────────────────────────────────────
function handleDownload(req, res) {
  const { url, mode } = req.body;

  // 1. Validate mode
  if (!mode || !VALID_MODES.includes(mode)) {
    return res.status(400).json({
      error: `Invalid mode. Choose one of: ${VALID_MODES.join(", ")}`,
    });
  }

  const expectedPlatform = mode.startsWith("youtube") ? "youtube"
    : mode.startsWith("instagram") ? "instagram"
    : "facebook";
  const isAudio = mode.endsWith("mp3");

  // 2. Validate URL
  const { valid, error } = validateURL(url, expectedPlatform);
  if (!valid) {
    return res.status(400).json({ error });
  }

  // 3. Create job & return immediately
  const jobId = uuidv4();
  const job = {
    status: "processing",
    progress: "Starting download…",
    error: null,
    filePath: null,
    fileName: null,
    format: isAudio ? "MP3" : "MP4",
    createdAt: Date.now(),
  };
  jobs.set(jobId, job);

  // Return instantly (within Render's 30 s window)
  res.json({ jobId });

  // 4. Run yt-dlp in background
  const safeURL = sanitizeURL(url.trim());
  const outputTemplate = path.join(DOWNLOADS_DIR, `${jobId}.%(ext)s`);

  const commonFlags = [
    '--no-playlist',
    '--retries 3',
    '--fragment-retries 3',
    '--no-check-certificates',
    '--no-warnings',
    expectedPlatform === 'youtube'
      ? '--extractor-args "youtube:player_client=android,web"'
      : '--user-agent "Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"',
  ].join(' ');

  let command;
  if (isAudio) {
    command = `yt-dlp -x --audio-format mp3 ${commonFlags} -o "${outputTemplate}" "${safeURL}"`;
  } else {
    command = `yt-dlp -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" --merge-output-format mp4 ${commonFlags} -o "${outputTemplate}" "${safeURL}"`;
  }

  job.progress = "Downloading…";

  exec(command, { timeout: 300_000, maxBuffer: 50 * 1024 * 1024 }, (execErr, _stdout, stderr) => {
    if (execErr) {
      const rawMsg = (stderr || execErr.message || "").toString().toLowerCase();
      console.error("yt-dlp error:", rawMsg.slice(0, 500));
      cleanupPartialFiles(jobId);

      if (rawMsg.includes("private") || rawMsg.includes("login") || rawMsg.includes("age-restricted") || rawMsg.includes("sign in")) {
        job.status = "error";
        job.error = expectedPlatform === 'instagram'
          ? 'This Instagram post is private or requires login.'
          : 'This content is private or age-restricted.';
      } else if (rawMsg.includes("404") || rawMsg.includes("not found") || rawMsg.includes("unavailable") || rawMsg.includes("deleted")) {
        job.status = "error";
        job.error = 'Content not found or deleted.';
      } else if (rawMsg.includes("429") || rawMsg.includes("too many") || rawMsg.includes("rate limit")) {
        job.status = "error";
        job.error = 'Temporarily blocked by platform. Try again in a moment.';
      } else {
        job.status = "error";
        job.error = 'Download failed. Check URL is valid and content is public.';
      }
      return;
    }

    // Find the output file
    const expectedExt = isAudio ? ".mp3" : ".mp4";
    let outputFile = path.join(DOWNLOADS_DIR, `${jobId}${expectedExt}`);

    if (!fs.existsSync(outputFile)) {
      const files = fs.readdirSync(DOWNLOADS_DIR).filter(f => f.startsWith(jobId));
      if (files.length > 0) {
        outputFile = path.join(DOWNLOADS_DIR, files[0]);
      } else {
        job.status = "error";
        job.error = "Download completed but output file not found.";
        return;
      }
    }

    const ext = path.extname(outputFile);
    job.filePath = outputFile;
    job.fileName = `${jobId}${ext}`;
    job.status = "done";
    job.progress = "Ready!";

    // Record history
    _recordHistory(req, url, mode, expectedPlatform, job.format, job.fileName);
  });
}

// ─────────────────────────────────────────────────────────────────
// GET /api/download/:id  — poll job status
// ─────────────────────────────────────────────────────────────────
function getJobStatus(req, res) {
  const job = jobs.get(req.params.id);
  if (!job) {
    return res.status(404).json({ error: "Job not found or expired." });
  }
  res.json({
    status: job.status,
    progress: job.progress,
    error: job.error,
    format: job.format,
  });
}

// ─────────────────────────────────────────────────────────────────
// GET /api/download/:id/file  — stream the finished file
// ─────────────────────────────────────────────────────────────────
function getJobFile(req, res) {
  const job = jobs.get(req.params.id);
  if (!job) {
    return res.status(404).json({ error: "Job not found or expired." });
  }
  if (job.status !== "done" || !job.filePath) {
    return res.status(400).json({ error: "File not ready yet.", status: job.status });
  }
  if (!fs.existsSync(job.filePath)) {
    return res.status(410).json({ error: "File expired. Start a new download." });
  }

  res.download(job.filePath, job.fileName, (err) => {
    if (err && !res.headersSent) {
      console.error("Send error:", err.message);
      return res.status(500).json({ error: "Failed to send file." });
    }
    // Cleanup after successful send
    fs.unlink(job.filePath, () => {});
    jobs.delete(req.params.id);
  });
}

// ── Helpers ──────────────────────────────────────────────────────

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
    // Silently ignore
  }
}

module.exports = { handleDownload, getJobStatus, getJobFile };
