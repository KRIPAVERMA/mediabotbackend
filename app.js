/**
 * app.js – Entry point for the Video-to-MP3 converter bot.
 *
 * Starts an Express server that exposes a single endpoint:
 *   POST /api/download  → accepts a YouTube URL, returns an MP3 file.
 */

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

// Email test endpoint (temporary debug)
app.get("/test-email", async (_req, res) => {
  const BREVO_KEY = process.env.BREVO_API_KEY || process.env.SMTP_PASS || "";
  const info = {
    brevo_key: BREVO_KEY ? `set (${BREVO_KEY.length} chars, starts: ${BREVO_KEY.substring(0, 8)}...)` : "NOT SET",
    method: "Brevo HTTP API (not SMTP)",
  };
  try {
    const { sendVerificationEmail } = require("./utils/email");
    const result = await sendVerificationEmail("kripaverma410@gmail.com", "999999", "TestUser");
    info.sent = result;
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
