/**
 * YouTube Innertube downloader — Node.js native, no yt-dlp needed.
 *
 * Uses YouTube's internal "Innertube" API (same as the iOS YouTube app)
 * to fetch video metadata + stream URLs. These URLs are direct CDN links
 * and don't require signature decryption.
 *
 * Key advantage: avoids yt-dlp's cloud-IP bot detection issues because
 * the request mimics the real iOS YouTube app rather than a scraper.
 */

const https = require("https");
const http  = require("http");
const fs    = require("fs");
const { URL } = require("url");

/* ── Innertube client configs ──────────────────────────────── */
const CLIENTS = {
  ios: {
    clientName: "IOS",
    clientVersion: "19.29.1",
    clientId: 5,
    deviceMake: "Apple",
    deviceModel: "iPhone16,2",
    osName: "iOS",
    osVersion: "17.5.1",
    userAgent: "com.google.ios.youtube/19.29.1 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X;)",
    apiKey: "AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc",
  },
  android: {
    clientName: "ANDROID",
    clientVersion: "19.29.37",
    clientId: 3,
    androidSdkVersion: 30,
    osName: "Android",
    osVersion: "11",
    userAgent: "com.google.android.youtube/19.29.37 (Linux; U; Android 11) gzip",
    apiKey: "AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w",
  },
  tv_embedded: {
    clientName: "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
    clientVersion: "2.0",
    clientId: 85,
    userAgent: "Mozilla/5.0 (SMART-TV; Linux; Tizen 6.5) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/5.0 Chrome/85.0.4183.93 TV Safari/537.36",
    apiKey: "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8",
  },
};

/**
 * Extract video ID from a YouTube URL.
 * Handles: youtu.be/xxx, youtube.com/watch?v=xxx, youtube.com/shorts/xxx, etc.
 */
function extractVideoId(url) {
  const patterns = [
    /(?:youtu\.be\/|youtube\.com\/(?:watch\?.*v=|embed\/|v\/|shorts\/))([a-zA-Z0-9_-]{11})/,
    /^([a-zA-Z0-9_-]{11})$/,
  ];
  for (const p of patterns) {
    const m = url.match(p);
    if (m) return m[1];
  }
  return null;
}

/**
 * Call Innertube player API to get video metadata + stream URLs.
 * Tries multiple client configs (ios → android → tv_embedded).
 *
 * @param {string} videoId - 11-char YouTube video ID
 * @returns {Promise<{title, duration, audioStreams, videoStreams, muxedStreams}>}
 */
async function getVideoInfo(videoId) {
  const clientOrder = ["ios", "android", "tv_embedded"];
  let lastError = null;

  for (const clientKey of clientOrder) {
    try {
      const result = await _callPlayer(videoId, clientKey);
      if (result) return result;
    } catch (err) {
      lastError = err;
      console.log(`[INNERTUBE] ${clientKey} failed: ${err.message}`);
    }
  }

  throw lastError || new Error("All Innertube clients failed");
}

async function _callPlayer(videoId, clientKey) {
  const client = CLIENTS[clientKey];
  const payload = {
    videoId,
    context: {
      client: {
        clientName: client.clientName,
        clientVersion: client.clientVersion,
        hl: "en",
        gl: "US",
        utcOffsetMinutes: 0,
      },
    },
  };

  // Add platform-specific fields
  if (client.deviceMake) payload.context.client.deviceMake = client.deviceMake;
  if (client.deviceModel) payload.context.client.deviceModel = client.deviceModel;
  if (client.osName) payload.context.client.osName = client.osName;
  if (client.osVersion) payload.context.client.osVersion = client.osVersion;
  if (client.androidSdkVersion) payload.context.client.androidSdkVersion = client.androidSdkVersion;

  const body = JSON.stringify(payload);

  // Use youtubei.googleapis.com (pure API server, no web bot detection)
  // Fall back to www.youtube.com if googleapis fails
  const hosts = ["youtubei.googleapis.com", "www.youtube.com"];
  let lastErr = null;

  for (const hostname of hosts) {
    try {
      const result = await new Promise((resolve, reject) => {
        const opts = {
          hostname,
          path: `/youtubei/v1/player?key=${client.apiKey}&prettyPrint=false`,
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "User-Agent": client.userAgent,
            "Content-Length": Buffer.byteLength(body),
            "X-Goog-Api-Key": client.apiKey,
            "X-Youtube-Client-Name": String(client.clientId || 5),
            "X-Youtube-Client-Version": client.clientVersion,
          },
        };

        const req = https.request(opts, (res) => {
          let data = "";
          res.on("data", (chunk) => (data += chunk));
          res.on("end", () => {
            try {
              const json = JSON.parse(data);
              const ps = json.playabilityStatus;

              if (!ps || ps.status !== "OK") {
                const reason = ps?.reason || ps?.status || "Unknown error";
                reject(new Error(`YouTube: ${reason}`));
                return;
              }

              const vd = json.videoDetails || {};
              const sd = json.streamingData || {};
              const formats = sd.formats || [];
              const adaptive = sd.adaptiveFormats || [];

              const audioStreams = adaptive
                .filter((f) => f.mimeType && f.mimeType.startsWith("audio/") && f.url)
                .sort((a, b) => (b.bitrate || 0) - (a.bitrate || 0));

              const videoStreams = adaptive
                .filter((f) => f.mimeType && f.mimeType.startsWith("video/") && f.url)
                .sort((a, b) => (b.bitrate || 0) - (a.bitrate || 0));

              const muxedStreams = formats
                .filter((f) => f.url)
                .sort((a, b) => (b.bitrate || 0) - (a.bitrate || 0));

              if (audioStreams.length === 0 && muxedStreams.length === 0) {
                reject(new Error(`No downloadable streams found (client: ${clientKey}, host: ${hostname})`));
                return;
              }

              resolve({
                title: vd.title || "video",
                duration: parseInt(vd.lengthSeconds || "0", 10),
                channelName: vd.author || "",
                audioStreams,
                videoStreams,
                muxedStreams,
                client: clientKey,
              });
            } catch (err) {
              // Log first 200 chars to understand what was returned
              console.log(`[INNERTUBE] ${hostname}/${clientKey}: parse error, first 200 chars: ${data.substring(0, 200)}`);
              reject(new Error(`Failed to parse response from ${hostname}: ${err.message}`));
            }
          });
        });

        req.on("error", reject);
        req.setTimeout(30000, () => {
          req.destroy();
          reject(new Error(`Request to ${hostname} timed out`));
        });
        req.write(body);
        req.end();
      });
      return result; // success
    } catch (err) {
      console.log(`[INNERTUBE] ${hostname}/${clientKey}: ${err.message}`);
      lastErr = err;
    }
  }

  throw lastErr;
}

/**
 * Download a stream URL to a local file.
 * Follows redirects (YouTube CDN often 302s).
 *
 * @param {string} url - Direct CDN URL
 * @param {string} outputPath - Local file path
 * @returns {Promise<number>} - bytes written
 */
function downloadStream(url, outputPath) {
  return new Promise((resolve, reject) => {
    const parsedUrl = new URL(url);
    const mod = parsedUrl.protocol === "https:" ? https : http;

    const doRequest = (requestUrl, redirectCount = 0) => {
      if (redirectCount > 5) {
        reject(new Error("Too many redirects"));
        return;
      }

      const parsed = new URL(requestUrl);
      mod.get(requestUrl, {
        headers: {
          "User-Agent": CLIENTS.ios.userAgent,
          "Accept": "*/*",
        },
      }, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          doRequest(res.headers.location, redirectCount + 1);
          return;
        }

        if (res.statusCode !== 200) {
          reject(new Error(`Download failed: HTTP ${res.statusCode}`));
          return;
        }

        const ws = fs.createWriteStream(outputPath);
        res.pipe(ws);

        ws.on("finish", () => {
          const stat = fs.statSync(outputPath);
          resolve(stat.size);
        });
        ws.on("error", reject);
        res.on("error", reject);
      }).on("error", reject);
    };

    doRequest(url);
  });
}

module.exports = { extractVideoId, getVideoInfo, downloadStream };
