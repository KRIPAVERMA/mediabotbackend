/**
 * Email Utility – sends verification emails using Nodemailer.
 *
 * Uses a free Gmail App Password or any SMTP credentials.
 * Configure via environment variables:
 *   SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM
 *
 * For quick testing, set SMTP_USER and SMTP_PASS to a Gmail account
 * with "App Passwords" enabled (2FA required).
 */

const nodemailer = require("nodemailer");

// ── SMTP Configuration ──────────────────────────────────────
const SMTP_HOST = process.env.SMTP_HOST || "smtp-relay.brevo.com";
const SMTP_PORT = parseInt(process.env.SMTP_PORT || "587", 10);
const SMTP_USER = process.env.SMTP_USER || "";
const SMTP_PASS = process.env.SMTP_PASS || "";
const SMTP_FROM = process.env.SMTP_FROM || "MediaBot <kripaverma410@gmail.com>";

let transporter = null;

function getTransporter() {
  if (transporter) return transporter;

  if (!SMTP_USER || !SMTP_PASS) {
    console.warn("⚠ SMTP credentials not set. Email sending will be simulated.");
    return null;
  }

  transporter = nodemailer.createTransport({
    host: SMTP_HOST,
    port: SMTP_PORT,
    secure: false,
    auth: {
      user: SMTP_USER,
      pass: SMTP_PASS,
    },
    connectionTimeout: 10000,
    greetingTimeout: 10000,
    socketTimeout: 15000,
  });

  return transporter;
}

/**
 * Send a 6-digit verification code via email.
 * Returns true if sent (or simulated), false on error.
 */
async function sendVerificationEmail(toEmail, code, userName) {
  const t = getTransporter();

  const htmlContent = `
  <div style="font-family: 'Segoe UI', Arial, sans-serif; max-width: 500px; margin: 0 auto; background: linear-gradient(135deg, #0B0D17 0%, #1A1D2E 100%); border-radius: 16px; overflow: hidden;">
    <div style="background: linear-gradient(135deg, #A78BFA, #F472B6); padding: 30px; text-align: center;">
      <h1 style="margin: 0; color: white; font-size: 28px;">🤖 MediaBot</h1>
      <p style="margin: 8px 0 0; color: rgba(255,255,255,0.9); font-size: 14px;">Email Verification</p>
    </div>
    <div style="padding: 30px; color: #E0E0E0;">
      <p style="font-size: 16px;">Hi ${userName || "there"} 👋,</p>
      <p style="font-size: 14px; line-height: 1.6;">Welcome to MediaBot! Use the code below to verify your email address:</p>
      <div style="text-align: center; margin: 25px 0;">
        <div style="display: inline-block; background: rgba(167,139,250,0.15); border: 2px solid #A78BFA; border-radius: 12px; padding: 16px 32px; letter-spacing: 8px; font-size: 32px; font-weight: 700; color: #A78BFA;">
          ${code}
        </div>
      </div>
      <p style="font-size: 13px; color: #999; text-align: center;">This code expires in <strong>10 minutes</strong>.</p>
      <p style="font-size: 13px; color: #999; text-align: center; margin-top: 20px;">If you didn't request this, you can safely ignore this email.</p>
    </div>
    <div style="background: rgba(255,255,255,0.03); padding: 15px; text-align: center; border-top: 1px solid rgba(255,255,255,0.05);">
      <p style="margin: 0; font-size: 11px; color: #666;">MediaBot – Download videos & audio from YouTube, Instagram & Facebook</p>
    </div>
  </div>`;

  if (!t) {
    // Simulate sending — log to console
    console.log(`\n📧 ── SIMULATED EMAIL ──────────────────────`);
    console.log(`   To:   ${toEmail}`);
    console.log(`   Code: ${code}`);
    console.log(`──────────────────────────────────────────────\n`);
    return true;
  }

  try {
    const sendPromise = t.sendMail({
      from: SMTP_FROM,
      to: toEmail,
      subject: `MediaBot – Your verification code is ${code}`,
      html: htmlContent,
    });
    const timeoutPromise = new Promise((_, reject) =>
      setTimeout(() => reject(new Error("SMTP timeout after 15s")), 15000)
    );
    const info = await Promise.race([sendPromise, timeoutPromise]);
    console.log(`📧 Verification email sent to ${toEmail}`);
    console.log(`   MessageId: ${info.messageId}`);
    console.log(`   Accepted:  ${JSON.stringify(info.accepted)}`);
    console.log(`   Rejected:  ${JSON.stringify(info.rejected)}`);
    console.log(`   Response:  ${info.response}`);
    return true;
  } catch (err) {
    console.error("Email send error:", err.message);
    return false;
  }
}

module.exports = { sendVerificationEmail };
