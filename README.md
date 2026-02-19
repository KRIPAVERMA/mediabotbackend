# Video-to-MP3 Converter Bot

A Node.js + Express REST API that accepts a public YouTube video link, downloads the video, extracts the audio, and returns it as a downloadable MP3 file.

---

## Prerequisites

Make sure the following are installed on your system:

| Tool | Purpose | Install |
|------|---------|---------|
| **Node.js** (≥ 18) | Runtime | [nodejs.org](https://nodejs.org) |
| **yt-dlp** | YouTube downloader | `pip install yt-dlp` or [GitHub releases](https://github.com/yt-dlp/yt-dlp) |
| **ffmpeg** | Audio conversion | [ffmpeg.org](https://ffmpeg.org/download.html) |

Verify installations:

```bash
node -v
yt-dlp --version
ffmpeg -version
```

---

## Setup

```bash
# 1. Clone / enter the project
cd link_converter

# 2. Install Node dependencies
npm install

# 3. Start the server
npm start          # production
# or
npm run dev        # with auto-reload (nodemon)
```

The server starts on **http://localhost:3000** by default.  
Set the `PORT` environment variable to change it.

---

## API

### `POST /api/download`

Convert a YouTube video to MP3.

**Request**

```json
{
  "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
}
```

**Success** — streams the `.mp3` file as a download.

**Error responses**

| Status | Body |
|--------|------|
| 400 | `{ "error": "Invalid YouTube URL. ..." }` |
| 500 | `{ "error": "Failed to download or convert the video. ..." }` |
| 429 | `{ "error": "Too many requests. Please try again later." }` |

### `GET /`

Health check — returns `{ "status": "ok" }`.

---

## Testing with cURL

```bash
curl -X POST http://localhost:3000/api/download \
  -H "Content-Type: application/json" \
  -d '{"url":"https://www.youtube.com/watch?v=dQw4w9WgXcQ"}' \
  --output song.mp3
```

---

## Project Structure

```
link_converter/
├── downloads/              # Temporary MP3 files (auto-cleaned)
├── controllers/
│   └── downloadController.js   # Core download + convert logic
├── routes/
│   └── download.js         # Express router
├── utils/
│   └── validator.js        # YouTube URL validation & sanitization
├── app.js                  # Entry point & server config
├── package.json
└── README.md
```

---

## Security

- Only YouTube URLs are accepted (validated via regex).
- Input is sanitized before being passed to shell commands.
- Request body limited to 1 MB.
- Rate limiting: 10 requests/minute per IP.
- Temporary files are deleted after the response is sent.

---

## Deployment

This project is suited for platforms that support long-running processes:

- **Render** (Web Service)
- **Railway**
- **Any VPS** (e.g. DigitalOcean, AWS EC2)

> **Note:** Serverless platforms like Vercel are **not** supported because yt-dlp requires persistent disk and long execution times.

---

## License

MIT
