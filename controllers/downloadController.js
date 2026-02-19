/**
 * Download Controller — Async Job-Based Architecture
 *
 * Render free tier has a 30-second HTTP timeout. yt-dlp downloads can take
 * 1-3 minutes, so we use an async pattern:
 *
 *   POST /api/download            → validates, queues job, returns { jobId }
 *   GET  /api/download/:id        → poll job status
 *   GET  /api/download/:id/file   → stream the finished file
 *   GET  /api/download/debug/jobs → diagnostic info
 */

const { exec } = require("child_process");
const path = require("path");
const fs   = require("fs");
const { v4: uuidv4 } = require("uuid");
const jwt  = require("jsonwebtoken");
const { validateURL, sanitizeURL } = require("../utils/validator");
const db   = require("../db/database");
const { JWT_SECRET } = require("../middleware/auth");

const DOWNLOADS_DIR = path.join(__dirname, "..", "downloads");
if (!fs.existsSync(DOWNLOADS_DIR)) fs.mkdirSync(DOWNLOADS_DIR, { recursive: true });
console.log("[INIT] DOWNLOADS_DIR =", DOWNLOADS_DIR);

const VALID_MODES = [
  "youtube-video", "youtube-mp3",
  "instagram-video", "instagram-mp3",
  "facebook-video", "facebook-mp3",
];

/* ── In-memory job store ─────────────────────────────────────── */
const jobs = new Map();

// Auto-cleanup every 60 s — remove jobs & files older than 10 min
setInterval(() => {
  const TEN_MIN = 10 * 60 * 1000;
  for (const [id, job] of jobs) {
    if (Date.now() - job.createdAt > TEN_MIN) {
      if (job.filePath) fs.unlink(job.filePath, () => {});
      jobs.delete(id);
    }
  }
}, 60_000);

/* ─────────────────────────────────────────────────────────────
   POST /api/download  — start a download job
   ───────────────────────────────────────────────────────────── */
function handleDownload(req, res) {
  const { url, mode } = req.body;

  if (!mode || !VALID_MODES.includes(mode)) {
    return res.status(400).json({
      error: `Invalid mode. Choose one of: ${VALID_MODES.join(", ")}`,
    });
  }

  const expectedPlatform = mode.startsWith("youtube") ? "youtube"
    : mode.startsWith("instagram") ? "instagram" : "facebook";
  const isAudio = mode.endsWith("mp3");

  const { valid, error } = validateURL(url, expectedPlatform);
  if (!valid) return res.status(400).json({ error });

  // Capture auth header NOW (before req is recycled)
  const authToken = req.headers.authorization || null;

  const jobId = uuidv4();
  const job = {
    status:    "processing",
    progress:  "Starting download…",
    error:     null,
    filePath:  null,
    fileName:  null,
    fileSize:  0,
    format:    isAudio ? "MP3" : "MP4",
    createdAt: Date.now(),
  };
  jobs.set(jobId, job);
  res.json({ jobId });                       // ← within 30 s
  console.log(`[JOB ${jobId}] Created — ${mode}`);

  /* ── yt-dlp in background ── */
  const safeURL = sanitizeURL(url.trim());
  const outputTemplate = path.join(DOWNLOADS_DIR, `${jobId}.%(ext)s`);

  const ytFlags = [
    '--extractor-args "youtube:player_client=ios,web"',
    '--user-agent "com.google.ios.youtube/19.29.1 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X;)"',
  ].join(" ");

  const socialFlags = [
    '--user-agent "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36"',
  ].join(" ");

  const commonFlags = [
    "--no-playlist",
    "--retries 5",
    "--fragment-retries 5",
    "--no-check-certificates",
    "--force-ipv4",
    "--no-warnings",
    "--extractor-retries 3",
    "--socket-timeout 30",
    expectedPlatform === "youtube" ? ytFlags : socialFlags,
  ].join(" ");

  const command = isAudio
    ? `yt-dlp -x --audio-format mp3 ${commonFlags} -o "${outputTemplate}" "${safeURL}"`
    : `yt-dlp -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" --merge-output-format mp4 ${commonFlags} -o "${outputTemplate}" "${safeURL}"`;

  job.progress = "Downloading…";
  console.log(`[JOB ${jobId}] CMD: ${command.slice(0, 200)}…`);

  exec(command, { timeout: 300_000, maxBuffer: 50 * 1024 * 1024 }, (execErr, stdout, stderr) => {
    if (execErr) {
      const rawMsg = (stderr || execErr.message || "").toString().toLowerCase();
      const rawSnippet = (stderr || execErr.message || "").toString().slice(0, 300);
      console.error(`[JOB ${jobId}] FAIL:`, rawMsg.slice(0, 800));
      cleanupPartialFiles(jobId);

      if (/private|login|age.restricted|sign.in/.test(rawMsg)) {
        job.status = "error";
        job.error  = expectedPlatform === "instagram"
          ? "This Instagram post is private or requires login."
          : "This content is private or age-restricted.";
      } else if (/404|not.found|unavailable|deleted/.test(rawMsg)) {
        job.status = "error";
        job.error  = "Content not found or deleted.";
      } else if (/429|too.many|rate.limit/.test(rawMsg)) {
        job.status = "error";
        job.error  = "Temporarily blocked by platform. Try again in a moment.";
      } else {
        job.status = "error";
        job.error  = "Download failed. Check URL is valid and content is public.";
      }
      // Attach raw error for debugging
      job.rawError = rawSnippet;
      return;
    }

    console.log(`[JOB ${jobId}] stdout:`, (stdout || "").slice(0, 300));
    if (stderr) console.log(`[JOB ${jobId}] stderr:`, stderr.slice(0, 300));

    // Find output file
    const expectedExt = isAudio ? ".mp3" : ".mp4";
    const jobFiles = fs.readdirSync(DOWNLOADS_DIR).filter(f => f.startsWith(jobId));
    console.log(`[JOB ${jobId}] Files on disk:`, jobFiles);

    let outputFile = path.join(DOWNLOADS_DIR, `${jobId}${expectedExt}`);

    if (!fs.existsSync(outputFile)) {
      if (jobFiles.length > 0) {
        const preferred = jobFiles.find(f => f.endsWith(expectedExt));
        if (preferred) {
          outputFile = path.join(DOWNLOADS_DIR, preferred);
        } else {
          // pick largest
          let best = { name: jobFiles[0], size: 0 };
          for (const f of jobFiles) {
            const sz = fs.statSync(path.join(DOWNLOADS_DIR, f)).size;
            if (sz > best.size) best = { name: f, size: sz };
          }
          outputFile = path.join(DOWNLOADS_DIR, best.name);
        }
      } else {
        job.status = "error";
        job.error  = "Download completed but no output file found.";
        console.error(`[JOB ${jobId}] No files!`);
        return;
      }
    }

    const stat = fs.statSync(outputFile);
    console.log(`[JOB ${jobId}] File: ${outputFile} — ${stat.size} bytes`);

    if (stat.size === 0) {
      job.status = "error";
      job.error  = "Download produced an empty file. Content may be restricted.";
      cleanupPartialFiles(jobId);
      return;
    }

    const ext = path.extname(outputFile);
    job.filePath = outputFile;
    job.fileName = `mediabot_${Date.now()}${ext}`;
    job.fileSize = stat.size;
    job.status   = "done";
    job.progress = "Ready!";
    console.log(`[JOB ${jobId}] DONE — ${job.fileName} (${stat.size} bytes)`);

    _recordHistory(authToken, url, mode, expectedPlatform, job.format, job.fileName);
  });
}

/* ─────────────────────────────────────────────────────────────
   GET /api/download/:id  — poll job status
   ───────────────────────────────────────────────────────────── */
function getJobStatus(req, res) {
  const job = jobs.get(req.params.id);
  if (!job) return res.status(404).json({ error: "Job not found or expired." });

  res.json({
    status:   job.status,
    progress: job.progress,
    error:    job.error,
    rawError: job.rawError || null,
    format:   job.format,
    fileSize: job.fileSize || 0,
  });
}

/* ─────────────────────────────────────────────────────────────
   GET /api/download/:id/file  — stream the finished file
   ───────────────────────────────────────────────────────────── */
function getJobFile(req, res) {
  const jobId = req.params.id;
  const job   = jobs.get(jobId);
  console.log(`[FILE ${jobId}] Requested`);

  if (!job) {
    console.log(`[FILE ${jobId}] Not in map`);
    return res.status(404).json({ error: "Job not found or expired." });
  }
  if (job.status !== "done" || !job.filePath) {
    console.log(`[FILE ${jobId}] Not ready — ${job.status}`);
    return res.status(400).json({ error: "File not ready yet.", status: job.status });
  }

  const filePath = job.filePath;
  if (!fs.existsSync(filePath)) {
    console.log(`[FILE ${jobId}] NOT on disk: ${filePath}`);
    return res.status(410).json({ error: "File expired. Start a new download." });
  }

  const stat = fs.statSync(filePath);
  console.log(`[FILE ${jobId}] On disk — ${stat.size} bytes`);

  if (stat.size === 0) {
    return res.status(500).json({ error: "Downloaded file is empty." });
  }

  // MIME type
  const ext  = path.extname(filePath).toLowerCase();
  const mime = { ".mp3": "audio/mpeg", ".mp4": "video/mp4", ".m4a": "audio/mp4",
                 ".webm": "video/webm", ".mkv": "video/x-matroska", ".ogg": "audio/ogg" };
  const contentType = mime[ext] || "application/octet-stream";

  // Explicit headers
  res.setHeader("Content-Type",        contentType);
  res.setHeader("Content-Length",      stat.size);
  res.setHeader("Content-Disposition", `attachment; filename="${job.fileName}"`);

  console.log(`[FILE ${jobId}] Streaming ${stat.size} bytes (${contentType})…`);

  const stream = fs.createReadStream(filePath);

  stream.on("error", (err) => {
    console.error(`[FILE ${jobId}] Stream error:`, err.message);
    if (!res.headersSent) res.status(500).json({ error: "Failed to read file." });
  });

  // Delete file + job only AFTER response is fully flushed
  res.on("finish", () => {
    console.log(`[FILE ${jobId}] Sent — cleaning up`);
    fs.unlink(filePath, () => {});
    jobs.delete(jobId);
  });

  stream.pipe(res);
}

/* ─────────────────────────────────────────────────────────────
   GET /api/download/debug/jobs  — diagnostic endpoint
   ───────────────────────────────────────────────────────────── */
function debugJobs(_req, res) {
  const list = [];
  for (const [id, j] of jobs) {
    list.push({
      id, status: j.status, progress: j.progress, error: j.error,
      filePath: j.filePath, fileName: j.fileName, fileSize: j.fileSize,
      format: j.format, age: Math.round((Date.now() - j.createdAt) / 1000) + "s",
      fileOnDisk: j.filePath ? fs.existsSync(j.filePath) : false,
    });
  }

  let diskFiles = [];
  try {
    diskFiles = fs.readdirSync(DOWNLOADS_DIR).map(f => {
      const s = fs.statSync(path.join(DOWNLOADS_DIR, f));
      return { name: f, size: s.size, modified: s.mtime };
    });
  } catch (e) { diskFiles = [{ error: e.message }]; }

  res.json({ totalJobs: jobs.size, jobs: list, downloadsDir: DOWNLOADS_DIR, filesOnDisk: diskFiles });
}

/* ── Helpers ──────────────────────────────────────────────────── */
function cleanupPartialFiles(fileId) {
  try {
    for (const f of fs.readdirSync(DOWNLOADS_DIR)) {
      if (f.startsWith(fileId)) fs.unlinkSync(path.join(DOWNLOADS_DIR, f));
    }
  } catch { /* best-effort */ }
}

function _recordHistory(authToken, url, mode, platform, format, filename) {
  try {
    if (!authToken || !authToken.startsWith("Bearer ")) return;
    const token   = authToken.split(" ")[1];
    const decoded = jwt.verify(token, JWT_SECRET);
    if (!decoded.userId) return;

    const pName = platform.charAt(0).toUpperCase() + platform.slice(1);
    db.prepare(
      "INSERT INTO download_history (user_id, url, mode, platform, format, filename) VALUES (?, ?, ?, ?, ?, ?)"
    ).run(decoded.userId, url, mode, pName, format, filename || "");
    console.log(`[HISTORY] Saved for user ${decoded.userId}`);
  } catch (err) {
    console.error("[HISTORY] Error:", err.message);
  }
}

module.exports = { handleDownload, getJobStatus, getJobFile, debugJobs };
