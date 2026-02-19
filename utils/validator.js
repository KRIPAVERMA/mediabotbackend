/**
 * URL Validation Utility
 * Validates and sanitizes YouTube, Instagram & Facebook URLs.
 * Accepts all common URL variants: mobile, share, short links, etc.
 */

// ── YouTube ─────────────────────────────────────────────────────
const YOUTUBE_PATTERNS = [
  /^https?:\/\/(www\.|m\.|music\.)?youtube\.com\/watch\?/,          // youtube.com/watch?v=...
  /^https?:\/\/youtu\.be\/[\w-]+/,                                   // youtu.be/ID
  /^https?:\/\/(www\.|m\.)?youtube\.com\/shorts\/[\w-]+/,            // shorts
  /^https?:\/\/(www\.|m\.)?youtube\.com\/embed\/[\w-]+/,             // embed
  /^https?:\/\/(www\.|m\.)?youtube\.com\/v\/[\w-]+/,                 // old embed
  /^https?:\/\/(www\.|m\.)?youtube\.com\/live\/[\w-]+/,              // live
  /^https?:\/\/music\.youtube\.com\/watch\?/,                        // YouTube Music
  /^https?:\/\/(www\.)?youtube\.com\/clip\/[\w-]+/,                  // clips
];

// ── Instagram ───────────────────────────────────────────────────
const INSTAGRAM_PATTERNS = [
  /^https?:\/\/(www\.)?instagram\.com\/(p|reel|reels|tv)\/[\w-]+/,              // posts, reels, tv
  /^https?:\/\/(www\.)?instagram\.com\/[\w._]+\/(p|reel|reels|tv)\/[\w-]+/,     // user/post
  /^https?:\/\/(www\.)?instagram\.com\/stories\/[\w._]+\/\d+/,                  // stories
  /^https?:\/\/(www\.)?instagram\.com\/[\w._]+\/?(\?|$)/,                       // profile page
  /^https?:\/\/instagr\.am\//,                                                  // short links
  /^https?:\/\/(www\.)?ddinstagram\.com\//,                                     // ddinstagram mirrors
];

// ── Facebook ────────────────────────────────────────────────────
const FACEBOOK_PATTERNS = [
  /^https?:\/\/(www\.|m\.|web\.|l\.)?facebook\.com\/.+\/videos\//,
  /^https?:\/\/(www\.|m\.|web\.)?facebook\.com\/watch/,
  /^https?:\/\/(www\.|m\.|web\.)?facebook\.com\/video\.php/,
  /^https?:\/\/(www\.|m\.|web\.)?facebook\.com\/reel\//,
  /^https?:\/\/(www\.|m\.|web\.)?facebook\.com\/share\/(v|r)\//,
  /^https?:\/\/(www\.|m\.|web\.)?facebook\.com\/story\.php/,
  /^https?:\/\/(www\.|m\.|web\.)?facebook\.com\/[\w.]+\/posts\//,
  /^https?:\/\/(www\.|m\.|web\.)?facebook\.com\/[\w.]+\/videos\//,
  /^https?:\/\/(www\.|m\.|web\.)?facebook\.com\/photo/,
  /^https?:\/\/fb\.watch\//,
  /^https?:\/\/fb\.gg\//,
  /^https?:\/\/(www\.|m\.|web\.)?facebook\.com\/[\d]+\/videos\//,
  /^https?:\/\/(www\.|m\.|web\.)?facebook\.com\/permalink\.php/,
];

/**
 * Detects the platform from a URL.
 * @param {string} url
 * @returns {"youtube"|"instagram"|"facebook"|null}
 */
function detectPlatform(url) {
  if (!url || typeof url !== "string") return null;
  const trimmed = url.trim();
  if (YOUTUBE_PATTERNS.some((p) => p.test(trimmed))) return "youtube";
  if (INSTAGRAM_PATTERNS.some((p) => p.test(trimmed))) return "instagram";
  if (FACEBOOK_PATTERNS.some((p) => p.test(trimmed))) return "facebook";
  return null;
}

/**
 * Validates a URL for a given platform.
 * @param {string} url
 * @param {"youtube"|"instagram"} expectedPlatform
 * @returns {{ valid: boolean, platform?: string, error?: string }}
 */
function validateURL(url, expectedPlatform) {
  if (!url || typeof url !== "string") {
    return { valid: false, error: "URL is required and must be a string." };
  }

  const trimmed = url.trim();

  if (trimmed.length > 2000) {
    return { valid: false, error: "URL is too long." };
  }

  const platform = detectPlatform(trimmed);

  if (!platform) {
    return {
      valid: false,
      error: "Invalid URL. Paste a full YouTube, Instagram, or Facebook link starting with http:// or https://",
    };
  }

  if (expectedPlatform && platform !== expectedPlatform) {
    return {
      valid: false,
      error: `Expected a ${expectedPlatform} URL but received a ${platform} URL.`,
    };
  }

  return { valid: true, platform };
}

/**
 * Sanitises a URL so it is safe to pass as a shell argument.
 * @param {string} url
 * @returns {string}
 */
function sanitizeURL(url) {
  return url.replace(/[^a-zA-Z0-9\-._~:/?#\[\]@!$&'()*+,;=%]/g, "");
}

module.exports = { validateURL, detectPlatform, sanitizeURL };
