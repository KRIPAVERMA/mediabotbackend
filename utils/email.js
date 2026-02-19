/**
 * Email Utility – sends verification emails using Brevo HTTP API.
 *
 * Uses Brevo's transactional email REST API (HTTPS port 443)
 * instead of SMTP, because many free hosting providers (Render, etc.)
 * block outbound SMTP connections on ports 587/465.
 *
 * Configure via environment variables:
 *   BREVO_API_KEY  – your Brevo API key (or SMTP key, which also works)
 *   SMTP_PASS      – fallback: same Brevo key
 *   SMTP_FROM      – sender email (must be verified in Brevo)
 */

const https = require("https");

// Brevo API key: prefer BREVO_API_KEY, fall back to SMTP_PASS (same key works for both)
const BREVO_API_KEY = process.env.BREVO_API_KEY || process.env.SMTP_PASS || "";
const SENDER_EMAIL = (process.env.SMTP_FROM || "kripaverma410@gmail.com").replace(/.*<(.+)>/, "$1");
const SENDER_NAME = "MediaBot";

/**
 * Send an email via Brevo HTTP API.
 * Returns a promise that resolves to the parsed JSON response.
 */
function brevoSendEmail(payload) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(payload);
    const options = {
      hostname: "api.brevo.com",
      port: 443,
      path: "/v3/smtp/email",
      method: "POST",
      headers: {
        "accept": "application/json",
        "api-key": BREVO_API_KEY,
        "content-type": "application/json",
        "content-length": Buffer.byteLength(data),
      },
      timeout: 15000,
    };

    const req = https.request(options, (res) => {
      let body = "";
      res.on("data", (chunk) => (body += chunk));
      res.on("end", () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try { resolve(JSON.parse(body)); } catch { resolve({ raw: body }); }
        } else {
          reject(new Error(`Brevo API ${res.statusCode}: ${body}`));
        }
      });
    });

    req.on("error", (err) => reject(err));
    req.on("timeout", () => { req.destroy(); reject(new Error("Brevo API request timeout (15s)")); });
    req.write(data);
    req.end();
  });
}

/**
 * Send a 6-digit verification code via email.
 * Returns true if sent (or simulated), false on error.
 */
async function sendVerificationEmail(toEmail, code, userName) {
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

  if (!BREVO_API_KEY) {
    // Simulate sending — log to console
    console.log(`\n📧 ── SIMULATED EMAIL (no API key) ─────────`);
    console.log(`   To:   ${toEmail}`);
    console.log(`   Code: ${code}`);
    console.log(`──────────────────────────────────────────────\n`);
    return true;
  }

  try {
    const result = await brevoSendEmail({
      sender: { name: SENDER_NAME, email: SENDER_EMAIL },
      to: [{ email: toEmail }],
      subject: `MediaBot – Your verification code is ${code}`,
      htmlContent: htmlContent,
    });
    console.log(`📧 Verification email sent to ${toEmail} via Brevo API`);
    console.log(`   Response: ${JSON.stringify(result)}`);
    return true;
  } catch (err) {
    console.error("Brevo API email error:", err.message);
    return false;
  }
}

module.exports = { sendVerificationEmail };
