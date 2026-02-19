/**
 * URL Validation Utility
 * Validates and sanitizes YouTube & Instagram URLs.
 */

const YOUTUBE_PATTERNS = [
  /^https?:\/\/(www\.)?youtube\.com\/watch\?v=[\w-]{11}/,
  /^https?:\/\/youtu\.be\/[\w-]{11}/,
  /^https?:\/\/(www\.)?youtube\.com\/shorts\/[\w-]{11}/,
];

const INSTAGRAM_PATTERNS = [
  /^https?:\/\/(www\.)?instagram\.com\/(p|reel|reels)\/[\w-]+/,
  /^https?:\/\/(www\.)?instagram\.com\/[\w._]+\/(p|reel|reels)\/[\w-]+/,
  /^https?:\/\/(www\.)?instagram\.com\/stories\/[\w._]+\/\d+/,
];

const FACEBOOK_PATTERNS = [
  /^https?:\/\/(www\.|m\.|web\.)?facebook\.com\/.+\/videos\//,
  /^https?:\/\/(www\.|m\.|web\.)?facebook\.com\/watch\//,
  /^https?:\/\/(www\.|m\.|web\.)?facebook\.com\/video\.php/,
  /^https?:\/\/(www\.|m\.|web\.)?facebook\.com\/reel\//,
  /^https?:\/\/(www\.|m\.|web\.)?facebook\.com\/share\/(v|r)\//,
  /^https?:\/\/fb\.watch\//,
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

  if (trimmed.length > 300) {
    return { valid: false, error: "URL is too long." };
  }

  const platform = detectPlatform(trimmed);

  if (!platform) {
    return {
      valid: false,
      error: "Invalid URL. Please provide a valid YouTube, Instagram, or Facebook link.",
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
