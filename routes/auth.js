/**
 * Auth Routes – /api/auth/*
 *   POST /signup       → create account, send verification email
 *   POST /verify       → verify email with 6-digit code
 *   POST /login        → sign in, get JWT
 *   POST /resend-code  → resend verification code
 *   GET  /me           → get current user (protected)
 */

const express = require("express");
const router = express.Router();
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const crypto = require("crypto");

const db = require("../db/database");
const { sendVerificationEmail } = require("../utils/email");
const { authMiddleware, JWT_SECRET } = require("../middleware/auth");

const TOKEN_EXPIRY = "30d"; // tokens last 30 days

// ── Helper: generate 6-digit code ──────────────────────────
function generateCode() {
  return crypto.randomInt(100000, 999999).toString();
}

// ── POST /api/auth/signup ──────────────────────────────────
router.post("/signup", async (req, res) => {
  try {
    const { email, password, name } = req.body;

    if (!email || !password) {
      return res.status(400).json({ error: "Email and password are required." });
    }
    if (password.length < 6) {
      return res.status(400).json({ error: "Password must be at least 6 characters." });
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      return res.status(400).json({ error: "Invalid email format." });
    }

    // Check if user already exists
    const existing = db.prepare("SELECT id, verified FROM users WHERE email = ?").get(email.toLowerCase());
    if (existing) {
      if (existing.verified) {
        return res.status(409).json({ error: "An account with this email already exists. Please sign in." });
      }
      // Not yet verified — resend code
      const code = generateCode();
      const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
      db.prepare("INSERT INTO email_verifications (user_id, code, expires_at) VALUES (?, ?, ?)")
        .run(existing.id, code, expiresAt);

      await sendVerificationEmail(email, code, name || "");
      return res.json({
        message: "Account exists but isn't verified. A new verification code has been sent.",
        needsVerification: true,
      });
    }

    // Hash password & create user
    const passwordHash = await bcrypt.hash(password, 12);
    const result = db.prepare("INSERT INTO users (email, password_hash, name) VALUES (?, ?, ?)")
      .run(email.toLowerCase(), passwordHash, name || "");

    const userId = result.lastInsertRowid;

    // Generate verification code
    const code = generateCode();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
    db.prepare("INSERT INTO email_verifications (user_id, code, expires_at) VALUES (?, ?, ?)")
      .run(userId, code, expiresAt);

    // Send email
    await sendVerificationEmail(email, code, name || "");

    res.status(201).json({
      message: "Account created! Check your email for the verification code.",
      needsVerification: true,
    });
  } catch (err) {
    console.error("Signup error:", err);
    res.status(500).json({ error: "Server error during signup." });
  }
});

// ── POST /api/auth/verify ──────────────────────────────────
router.post("/verify", (req, res) => {
  try {
    const { email, code } = req.body;
    if (!email || !code) {
      return res.status(400).json({ error: "Email and code are required." });
    }

    const user = db.prepare("SELECT id, verified FROM users WHERE email = ?").get(email.toLowerCase());
    if (!user) {
      return res.status(404).json({ error: "No account found with this email." });
    }
    if (user.verified) {
      return res.json({ message: "Email already verified. You can sign in." });
    }

    // Find valid code
    const verification = db.prepare(`
      SELECT id FROM email_verifications
      WHERE user_id = ? AND code = ? AND used = 0 AND expires_at > datetime('now')
      ORDER BY id DESC LIMIT 1
    `).get(user.id, code.toString());

    if (!verification) {
      return res.status(400).json({ error: "Invalid or expired code. Please request a new one." });
    }

    // Mark code as used & user as verified
    db.prepare("UPDATE email_verifications SET used = 1 WHERE id = ?").run(verification.id);
    db.prepare("UPDATE users SET verified = 1 WHERE id = ?").run(user.id);

    // Generate JWT
    const token = jwt.sign({ userId: user.id, email: email.toLowerCase() }, JWT_SECRET, {
      expiresIn: TOKEN_EXPIRY,
    });

    const userData = db.prepare("SELECT id, email, name, created_at FROM users WHERE id = ?").get(user.id);

    res.json({
      message: "Email verified successfully! 🎉",
      token,
      user: userData,
    });
  } catch (err) {
    console.error("Verify error:", err);
    res.status(500).json({ error: "Server error during verification." });
  }
});

// ── POST /api/auth/login ───────────────────────────────────
router.post("/login", async (req, res) => {
  try {
    const { email, password } = req.body;
    if (!email || !password) {
      return res.status(400).json({ error: "Email and password are required." });
    }

    const user = db.prepare("SELECT * FROM users WHERE email = ?").get(email.toLowerCase());
    if (!user) {
      return res.status(401).json({ error: "Invalid email or password." });
    }

    if (!user.verified) {
      return res.status(403).json({
        error: "Email not verified. Please check your inbox or request a new code.",
        needsVerification: true,
      });
    }

    const match = await bcrypt.compare(password, user.password_hash);
    if (!match) {
      return res.status(401).json({ error: "Invalid email or password." });
    }

    const token = jwt.sign({ userId: user.id, email: user.email }, JWT_SECRET, {
      expiresIn: TOKEN_EXPIRY,
    });

    res.json({
      message: "Signed in successfully!",
      token,
      user: { id: user.id, email: user.email, name: user.name, created_at: user.created_at },
    });
  } catch (err) {
    console.error("Login error:", err);
    res.status(500).json({ error: "Server error during login." });
  }
});

// ── POST /api/auth/resend-code ─────────────────────────────
router.post("/resend-code", async (req, res) => {
  try {
    const { email } = req.body;
    if (!email) return res.status(400).json({ error: "Email is required." });

    const user = db.prepare("SELECT id, name, verified FROM users WHERE email = ?").get(email.toLowerCase());
    if (!user) return res.status(404).json({ error: "No account found with this email." });
    if (user.verified) return res.json({ message: "Email already verified. You can sign in." });

    const code = generateCode();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
    db.prepare("INSERT INTO email_verifications (user_id, code, expires_at) VALUES (?, ?, ?)")
      .run(user.id, code, expiresAt);

    await sendVerificationEmail(email, code, user.name || "");

    res.json({ message: "A new verification code has been sent to your email." });
  } catch (err) {
    console.error("Resend code error:", err);
    res.status(500).json({ error: "Server error." });
  }
});

// ── GET /api/auth/me (protected) ───────────────────────────
router.get("/me", authMiddleware, (req, res) => {
  const user = db.prepare("SELECT id, email, name, created_at FROM users WHERE id = ?").get(req.userId);
  if (!user) return res.status(404).json({ error: "User not found." });
  res.json({ user });
});

module.exports = router;
