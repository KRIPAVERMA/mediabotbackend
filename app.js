/**
 * app.js – Entry point for the Video-to-MP3 converter bot.
 *
 * Starts an Express server that exposes a single endpoint:
 *   POST /api/download  → accepts a YouTube URL, returns an MP3 file.
 */

require("dotenv").config();

const express = require("express");
const cors = require("cors");
const rateLimit = require("express-rate-limit");
const path = require("path");
const fs = require("fs");

const downloadRoute = require("./routes/download");
const authRoute = require("./routes/auth");
const historyRoute = require("./routes/history");

const app = express();
const PORT = process.env.PORT || 3000;

// ── Middleware ────────────────────────────────────────────────────

// Enable CORS for all origins (tighten in production)
app.use(cors());

// Parse JSON bodies (limit to 1 MB to prevent abuse)
app.use(express.json({ limit: "1mb" }));

// Basic rate limiter: max 10 requests per minute per IP
const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many requests. Please try again later." },
});
app.use("/api/", limiter);

// ── Serve the frontend ───────────────────────────────────────────
app.use(express.static(path.join(__dirname, "public")));

// ── Ensure downloads directory exists ────────────────────────────
const downloadsDir = path.join(__dirname, "downloads");
if (!fs.existsSync(downloadsDir)) {
  fs.mkdirSync(downloadsDir, { recursive: true });
}

// ── Routes ───────────────────────────────────────────────────────

app.use("/api/download", downloadRoute);
app.use("/api/auth", authRoute);
app.use("/api/history", historyRoute);

// Health-check endpoint
app.get("/health", (_req, res) => {
  let dbStatus = "unknown";
  try {
    const db = require("./db/database");
    const row = db.prepare("SELECT COUNT(*) AS cnt FROM users").get();
    dbStatus = `ok (${row.cnt} users)`;
  } catch (err) {
    dbStatus = `error: ${err.message}`;
  }
  res.json({ status: "ok", message: "Video-to-MP3 Bot is running.", db: dbStatus });
});

// System dependencies check endpoint
app.get("/check-dependencies", async (_req, res) => {
  const { exec } = require("child_process");
  const { promisify } = require("util");
  const execAsync = promisify(exec);
  
  const results = {
    ytdlp: { installed: false, version: null, error: null },
    ffmpeg: { installed: false, version: null, error: null },
    node: { version: process.version },
    platform: process.platform,
    downloadsDir: require("path").join(__dirname, "downloads")
  };

  try {
    const ytdlp = await execAsync("yt-dlp --version");
    results.ytdlp.installed = true;
    results.ytdlp.version = ytdlp.stdout.trim();
  } catch (err) {
    results.ytdlp.error = err.message;
  }

  try {
    const ffmpeg = await execAsync("ffmpeg -version");
    const versionMatch = ffmpeg.stdout.match(/ffmpeg version ([^\s]+)/);
    results.ffmpeg.installed = true;
    results.ffmpeg.version = versionMatch ? versionMatch[1] : "unknown";
  } catch (err) {
    results.ffmpeg.error = err.message;
  }

  // Check downloads directory
  const fs = require("fs");
  const downloadsPath = results.downloadsDir;
  results.downloadsDir = {
    path: downloadsPath,
    exists: fs.existsSync(downloadsPath),
    writable: false
  };
  
  if (results.downloadsDir.exists) {
    try {
      const testFile = require("path").join(downloadsPath, ".writetest");
      fs.writeFileSync(testFile, "test");
      fs.unlinkSync(testFile);
      results.downloadsDir.writable = true;
    } catch (err) {
      results.downloadsDir.writeError = err.message;
    }
  }

  res.json(results);
});

// Email test endpoint (temporary debug)
app.get("/test-email", async (_req, res) => {
  const https = require("https");
  const BREVO_KEY = process.env.BREVO_API_KEY || process.env.SMTP_PASS || "";
  const info = {
    brevo_key: BREVO_KEY ? `set (${BREVO_KEY.length} chars, starts: ${BREVO_KEY.substring(0, 8)}...)` : "NOT SET",
    method: "Brevo HTTP API (not SMTP)",
  };

  // Direct Brevo API call with full error details
  const payload = JSON.stringify({
    sender: { name: "MediaBot", email: "kripaverma410@gmail.com" },
    to: [{ email: "kripaverma410@gmail.com" }],
    subject: "MediaBot SMTP Test",
    htmlContent: "<p>If you see this, Brevo HTTP API works!</p>",
  });

  try {
    const result = await new Promise((resolve, reject) => {
      const req = https.request({
        hostname: "api.brevo.com",
        port: 443,
        path: "/v3/smtp/email",
        method: "POST",
        headers: {
          "accept": "application/json",
          "api-key": BREVO_KEY,
          "content-type": "application/json",
          "content-length": Buffer.byteLength(payload),
        },
        timeout: 15000,
      }, (resp) => {
        let body = "";
        resp.on("data", (c) => (body += c));
        resp.on("end", () => resolve({ status: resp.statusCode, body }));
      });
      req.on("error", (e) => reject(e));
      req.on("timeout", () => { req.destroy(); reject(new Error("timeout")); });
      req.write(payload);
      req.end();
    });
    info.api_status = result.status;
    info.api_response = result.body;
    info.sent = result.status >= 200 && result.status < 300;
  } catch (err) {
    info.sent = false;
    info.error = err.message;
  }
  res.json(info);
});

// ── 404 handler ──────────────────────────────────────────────────
app.use((_req, res) => {
  res.status(404).json({ error: "Route not found." });
});

// ── Global error handler ─────────────────────────────────────────
app.use((err, _req, res, _next) => {
  console.error("Unhandled error:", err);
  res.status(500).json({ error: "Internal server error.", detail: err.message || String(err) });
});

// ── Start server ─────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`🚀 Server running on http://localhost:${PORT}`);
});
