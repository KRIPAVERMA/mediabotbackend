/**
 * Download Controller — Async Job-Based Architecture
 *
 * Render free tier has a 30-second HTTP timeout. Downloads can take
 * 1-3 minutes, so we use an async pattern:
 *
 *   POST /api/download            → validates, queues job, returns { jobId }
 *   GET  /api/download/:id        → poll job status
 *   GET  /api/download/:id/file   → stream the finished file
 *   GET  /api/download/debug/jobs → diagnostic info
 *
 * YouTube: uses Innertube API (Node.js native — avoids cloud IP bot detection)
 * Instagram / Facebook: uses yt-dlp CLI
 */

const { exec } = require("child_process");
const path = require("path");
const fs   = require("fs");
const { v4: uuidv4 } = require("uuid");
const jwt  = require("jsonwebtoken");
const { extractVideoId, getVideoInfo, downloadStream } = require("../utils/innertube");
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
  console.log(`[JOB ${jobId}] Created — ${mode} (${expectedPlatform})`);

  const safeURL = sanitizeURL(url.trim());

  if (expectedPlatform === "youtube") {
    _downloadYouTube(jobId, job, safeURL, isAudio, authToken, url, mode);
  } else {
    _downloadWithYtDlp(jobId, job, safeURL, isAudio, expectedPlatform, authToken, url, mode);
  }
}

/* ─────────────────────────────────────────────────────────────
   YouTube download via Innertube API  (avoids cloud IP bot detection)
   ───────────────────────────────────────────────────────────── */
async function _downloadYouTube(jobId, job, url, isAudio, authToken, origURL, mode) {
  try {
    job.progress = "Fetching video info…";

    const videoId = extractVideoId(url);
    if (!videoId) {
      job.status = "error";
      job.error = "Could not extract YouTube video ID from URL.";
      return;
    }
    console.log(`[JOB ${jobId}] Innertube: videoId=${videoId}`);

    const info = await getVideoInfo(videoId);
    const title = (info.title || "video").replace(/[<>:"/\\|?*]/g, "_");
    console.log(`[JOB ${jobId}] Title: ${title}, duration: ${info.duration}s, client: ${info.client}`);
    console.log(`[JOB ${jobId}] Streams — audio: ${info.audioStreams.length}, video: ${info.videoStreams.length}, muxed: ${info.muxedStreams.length}`);

    const ext = isAudio ? "mp3" : "mp4";
    const outputFile = path.join(DOWNLOADS_DIR, `${jobId}.${ext}`);

    if (isAudio) {
      // Pick best audio stream → download → convert to MP3 with ffmpeg
      const audio = info.audioStreams[0]; // sorted by bitrate descending
      if (!audio) {
        job.status = "error";
        job.error = "No audio stream available for this video.";
        return;
      }

      job.progress = "Downloading audio…";
      console.log(`[JOB ${jobId}] Audio: ${audio.mimeType}, bitrate: ${audio.bitrate}`);

      const tmpFile = path.join(DOWNLOADS_DIR, `${jobId}_raw.m4a`);
      const bytes = await downloadStream(audio.url, tmpFile);
      console.log(`[JOB ${jobId}] Downloaded ${bytes} bytes`);

      if (bytes === 0) {
        cleanupPartialFiles(jobId);
        job.status = "error";
        job.error = "Audio download returned empty file.";
        return;
      }

      // Convert to MP3
      job.progress = "Converting to MP3…";
      const ffmpegCmd = `ffmpeg -i "${tmpFile}" -vn -ab 192k -ar 44100 -f mp3 "${outputFile}" -y`;
      console.log(`[JOB ${jobId}] ffmpeg: ${ffmpegCmd}`);

      exec(ffmpegCmd, { timeout: 300_000, maxBuffer: 50 * 1024 * 1024 }, (err, stdout, stderr) => {
        fs.unlink(tmpFile, () => {}); // cleanup raw file

        if (err) {
          console.error(`[JOB ${jobId}] ffmpeg error:`, (stderr || err.message).slice(0, 500));
          cleanupPartialFiles(jobId);
          job.status = "error";
          job.error = "Audio conversion failed.";
          job.rawError = (stderr || err.message).slice(0, 300);
          return;
        }
        _finalizeJob(jobId, job, outputFile, authToken, origURL, mode, "youtube");
      });

    } else {
      // Video download — prefer muxed mp4, else download video+audio and merge
      if (info.muxedStreams.length > 0) {
        // Use muxed format (video+audio in one file)
        const muxed = info.muxedStreams[0]; // highest bitrate
        job.progress = "Downloading video…";
        console.log(`[JOB ${jobId}] Muxed: ${muxed.mimeType}, ${muxed.qualityLabel || muxed.quality}`);

        const bytes = await downloadStream(muxed.url, outputFile);
        console.log(`[JOB ${jobId}] Downloaded ${bytes} bytes`);

        if (bytes === 0) {
          cleanupPartialFiles(jobId);
          job.status = "error";
          job.error = "Video download returned empty file.";
          return;
        }
        _finalizeJob(jobId, job, outputFile, authToken, origURL, mode, "youtube");

      } else if (info.videoStreams.length > 0 && info.audioStreams.length > 0) {
        // Separate video + audio → merge with ffmpeg
        job.progress = "Downloading video + audio…";
        // Pick best mp4 video stream
        const videoStream = info.videoStreams.find(s => s.mimeType?.includes("video/mp4")) || info.videoStreams[0];
        const audioStream = info.audioStreams[0];

        console.log(`[JOB ${jobId}] Video: ${videoStream.mimeType} ${videoStream.qualityLabel || ""}`);
        console.log(`[JOB ${jobId}] Audio: ${audioStream.mimeType}`);

        const videoTmp = path.join(DOWNLOADS_DIR, `${jobId}_v.mp4`);
        const audioTmp = path.join(DOWNLOADS_DIR, `${jobId}_a.m4a`);

        const [vBytes, aBytes] = await Promise.all([
          downloadStream(videoStream.url, videoTmp),
          downloadStream(audioStream.url, audioTmp),
        ]);
        console.log(`[JOB ${jobId}] Video: ${vBytes}b, Audio: ${aBytes}b`);

        if (vBytes === 0 || aBytes === 0) {
          cleanupPartialFiles(jobId);
          job.status = "error";
          job.error = "Download returned empty streams.";
          return;
        }

        // Merge
        job.progress = "Merging audio + video…";
        const mergeCmd = `ffmpeg -i "${videoTmp}" -i "${audioTmp}" -c copy -movflags +faststart "${outputFile}" -y`;
        console.log(`[JOB ${jobId}] Merge: ${mergeCmd}`);

        exec(mergeCmd, { timeout: 300_000, maxBuffer: 50 * 1024 * 1024 }, (err) => {
          fs.unlink(videoTmp, () => {});
          fs.unlink(audioTmp, () => {});

          if (err) {
            console.error(`[JOB ${jobId}] Merge error:`, err.message);
            cleanupPartialFiles(jobId);
            job.status = "error";
            job.error = "Video merge failed.";
            return;
          }
          _finalizeJob(jobId, job, outputFile, authToken, origURL, mode, "youtube");
        });

      } else {
        job.status = "error";
        job.error = "No downloadable video stream found.";
      }
    }
  } catch (err) {
    console.error(`[JOB ${jobId}] Innertube error:`, err.message);
    cleanupPartialFiles(jobId);
    job.status = "error";
    job.error  = _classifyYtError(err);
    job.rawError = err.message.slice(0, 300);
  }
}

function _classifyYtError(err) {
  const msg = (err.message || "").toLowerCase();
  if (/private|login|sign.in|bot/.test(msg)) return "This content is private or requires authentication.";
  if (/not.found|unavailable|404|deleted|not.available/.test(msg)) return "Video not found or has been deleted.";
  if (/429|too.many|rate.limit/.test(msg)) return "Temporarily rate-limited. Try again in a moment.";
  if (/age|restricted/.test(msg)) return "This video is age-restricted.";
  if (/live/.test(msg)) return "Live streams are not supported.";
  return "YouTube download failed: " + (err.message || "").slice(0, 150);
}

/* ─────────────────────────────────────────────────────────────
   Instagram / Facebook download via yt-dlp CLI
   ───────────────────────────────────────────────────────────── */
function _downloadWithYtDlp(jobId, job, safeURL, isAudio, expectedPlatform, authToken, origURL, mode) {
  const outputTemplate = path.join(DOWNLOADS_DIR, `${jobId}.%(ext)s`);

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
    "--geo-bypass",
    socialFlags,
  ].join(" ");

  const command = isAudio
    ? `yt-dlp -x --audio-format mp3 -f "bestaudio/best" ${commonFlags} -o "${outputTemplate}" "${safeURL}"`
    : `yt-dlp -f "bv*[ext=mp4]+ba[ext=m4a]/bv*+ba/b" --merge-output-format mp4 ${commonFlags} -o "${outputTemplate}" "${safeURL}"`;

  job.progress = "Downloading…";
  console.log(`[JOB ${jobId}] CMD: ${command.slice(0, 300)}…`);

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

    _finalizeJob(jobId, job, outputFile, authToken, origURL, mode, expectedPlatform);
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

/** Verify output file, update job state, record history */
function _finalizeJob(jobId, job, outputFile, authToken, origURL, mode, platform) {
  if (!fs.existsSync(outputFile)) {
    job.status = "error";
    job.error  = "Download completed but no output file found.";
    console.error(`[JOB ${jobId}] Output missing: ${outputFile}`);
    cleanupPartialFiles(jobId);
    return;
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

  _recordHistory(authToken, origURL, mode, platform, job.format, job.fileName);
}

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
