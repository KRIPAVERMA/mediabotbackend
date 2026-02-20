# MediaBot - Multi-Platform Media Downloader

A Node.js + Express REST API with Flutter mobile app that downloads videos and extracts audio from YouTube, Instagram, and Facebook. Features user authentication, email verification, download history tracking, and more.

---

## Features

- 🎥 **Multi-platform support**: YouTube, Instagram, Facebook
- 🎵 **Dual mode**: Download video (MP4) or extract audio (MP3)
- 🔐 **User authentication**: JWT-based login/signup with email verification
- 📧 **Email verification**: Forgot password flow with verification codes via Brevo API
- 📊 **Download history**: Per-user download tracking with statistics
- 📱 **Flutter mobile app**: Android app with modern UI
- 🔒 **Security**: Rate limiting, input sanitization, SQL injection protection

---

## Prerequisites

### System Requirements

Make sure the following are installed on your server:

| Tool | Purpose | Install |
|------|---------|---------|
| **Node.js** (≥ 18) | Runtime | [nodejs.org](https://nodejs.org) |
| **yt-dlp** | Media downloader | `pip install yt-dlp` or [GitHub releases](https://github.com/yt-dlp/yt-dlp) |
| **ffmpeg** | Audio/video conversion | [ffmpeg.org](https://ffmpeg.org/download.html) |
| **Python 3** | Required for yt-dlp | [python.org](https://www.python.org/downloads/) |

**✅ Verify installations:**

```bash
node -v          # Should show v18 or higher
yt-dlp --version # Should show version number
ffmpeg -version  # Should show ffmpeg version
python --version # Should show Python 3.x
```

**🚨 CRITICAL:** Your production server MUST have `yt-dlp` and `ffmpeg` available in the system PATH.

### Environment Variables

Create a `.env` file in the project root:

```env
PORT=3000
JWT_SECRET=your-super-secret-jwt-key-change-this
BREVO_API_KEY=your-brevo-api-key-here
SENDER_EMAIL=your-email@gmail.com
SENDER_NAME=MediaBot
```

**Get your Brevo API key:**
1. Sign up at [brevo.com](https://www.brevo.com)
2. Go to SMTP & API → API Keys
3. Create a new API key
4. Copy it to your `.env` file

---

## Quick Start (Local Development)

```bash
# 1. Clone the repository
git clone https://github.com/KRIPAVERMA/mediabotbackend.git
cd mediabotbackend

# 2. Install dependencies
npm install

# 3. Create .env file (see Environment Variables above)
cp .env.example .env
# Edit .env and add your keys

# 4. Start the server
npm start          # production
# or
npm run dev        # with auto-reload (nodemon)
```

The server starts on **http://localhost:3000** by default.

---

## 🚀 Production Deployment

### Step 1: Install System Dependencies on Server

**For Ubuntu/Debian:**
```bash
# Install Python and pip
sudo apt update
sudo apt install python3 python3-pip -y

# Install yt-dlp
sudo pip3 install yt-dlp

# Install ffmpeg
sudo apt install ffmpeg -y

# Verify
yt-dlp --version
ffmpeg -version
```

**For other systems:** Follow the links in Prerequisites section.

### Step 2: Deploy Your Code

```bash
# Clone your repository
git clone https://github.com/KRIPAVERMA/mediabotbackend.git
cd mediabotbackend

# Install Node.js dependencies
npm install --production

# Create .env file
nano .env
# Add all required environment variables (see above)
```

### Step 3: Create Required Directories

```bash
# Create downloads directory
mkdir -p downloads

# Create database directory
mkdir -p db
```

### Step 4: Start the Server

```bash
# Using node directly
node app.js

# Or using PM2 (recommended for production)
npm install -g pm2
pm2 start app.js --name mediabot
pm2 save
pm2 startup
```

### Step 5: Check Dependencies

After deployment, visit: `https://your-domain.com/check-dependencies`

This endpoint will show if yt-dlp and ffmpeg are properly installed.

**Expected response:**
```json
{
  "ytdlp": { "installed": true, "version": "2024.xx.xx" },
  "ffmpeg": { "installed": true, "version": "x.x.x" },
  "node": { "version": "v20.x.x" },
  "platform": "linux",
  "downloadsDir": { "path": "/path/to/downloads", "exists": true, "writable": true }
}
```

**❌ If yt-dlp or ffmpeg show `"installed": false`:**
- Install them on your server (see Step 1)
- Make sure they're in the system PATH
- Restart your Node.js server
- Check `/check-dependencies` again

---

## API Endpoints

### Authentication

#### `POST /api/auth/signup`
Create a new account

```json
{
  "name": "John Doe",
  "email": "john@example.com",
  "password": "securepassword123"
}
```

#### `POST /api/auth/login`
Login to existing account

```json
{
  "email": "john@example.com",
  "password": "securepassword123"
}
```

Returns JWT token for authenticated requests.

#### `POST /api/auth/forgot-password`
Request password reset code

```json
{
  "email": "john@example.com"
}
```

#### `POST /api/auth/reset-password`
Reset password with verification code

```json
{
  "email": "john@example.com",
  "code": "123456",
  "newPassword": "newsecurepassword"
}
```

### Downloads

#### `POST /api/download`
Download media from YouTube, Instagram, or Facebook

**Headers:**
```
Authorization: Bearer <your-jwt-token>
Content-Type: application/json
```

**Body:**
```json
{
  "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
  "mode": "youtube-mp3"
}
```

**Valid modes:**
- `youtube-video` - Download YouTube video as MP4
- `youtube-mp3` - Extract YouTube audio as MP3
- `instagram-video` - Download Instagram video
- `instagram-mp3` - Extract Instagram audio as MP3
- `facebook-video` - Download Facebook video
- `facebook-mp3` - Extract Facebook audio as MP3

**Response:** Streams the file as a download.

### History

#### `GET /api/history?page=1&limit=10`
Get download history for logged-in user

**Headers:**
```
Authorization: Bearer <your-jwt-token>
```

**Response:**
```json
{
  "history": [...],
  "stats": { "totalDownloads": 42, "totalMp3": 30, "totalMp4": 12 },
  "pagination": { "currentPage": 1, "totalPages": 3, "totalItems": 42, "itemsPerPage": 10 }
}
```

### Health Checks

#### `GET /health`
Check server status

```json
{
  "status": "ok",
  "message": "Video-to-MP3 Bot is running.",
  "db": "ok (X users)"
}
```

#### `GET /check-dependencies`
Check if yt-dlp and ffmpeg are installed

---

## Testing with cURL

```bash
# 1. Sign up
curl -X POST http://localhost:3000/api/auth/signup \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","email":"test@example.com","password":"test123"}'

# 2. Login
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"test123"}'
# Save the token from response

# 3. Download
curl -X POST http://localhost:3000/api/download \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -d '{"url":"https://www.youtube.com/watch?v=dQw4w9WgXcQ","mode":"youtube-mp3"}' \
  --output song.mp3
```

---

## Project Structure

```
mediabotbackend/
├── db/
│   ├── database.js           # SQLite database setup
│   ├── mediabot.db           # Database file (auto-created)
│   └── schema.sql            # Database schema
├── downloads/                # Temporary media files (auto-cleaned)
├── controllers/
│   └── downloadController.js # Download logic for all platforms
├── routes/
│   ├── download.js           # Download endpoints
│   ├── auth.js               # Authentication endpoints
│   └── history.js            # History endpoints
├── middleware/
│   └── auth.js               # JWT authentication middleware
├── utils/
│   └── validator.js          # URL validation & sanitization
├── mediabot_app/             # Flutter mobile app
│   ├── lib/
│   │   ├── screens/          # UI screens
│   │   └── services/         # API services
│   └── android/              # Android build config
├── app.js                    # Entry point & server config
├── package.json              # Node.js dependencies
├── .env                      # Environment variables (create this)
├── .gitignore                # Git ignore rules
└── README.md                 # This file
```

---

## Flutter Mobile App

The Android app is located in `mediabot_app/` folder.

### Build the app:

```bash
cd mediabot_app
flutter pub get
flutter build apk --release
```

APK will be at: `build/app/outputs/flutter-apk/app-release.apk`

### Update server URL:

Edit `mediabot_app/lib/services/api_service.dart`:

```dart
static String baseUrl = 'https://your-production-server.com';
```

---

## Security Features

- ✅ JWT-based authentication
- ✅ Password hashing with bcryptjs
- ✅ SQL injection protection (prepared statements)
- ✅ Input validation and sanitization
- ✅ Request body size limiting (1 MB)
- ✅ Rate limiting: 10 requests/minute per IP
- ✅ CORS enabled for mobile app access
- ✅ Temporary files deleted after download
- ✅ Email verification for password reset

---

## Troubleshooting

### "Route not found" or downloads failing

1. **Check dependencies:**
   - Visit `https://your-domain.com/check-dependencies`
   - Make sure `ytdlp.installed` and `ffmpeg.installed` are both `true`

2. **Install missing dependencies on server:**
   ```bash
   # SSH into your server
   sudo pip3 install yt-dlp
   sudo apt install ffmpeg
   
   # Restart your Node.js app
   pm2 restart mediabot
   ```

3. **Check server logs:**
   ```bash
   pm2 logs mediabot
   ```

### Email verification not working

- Check `.env` file has valid `BREVO_API_KEY`
- Verify sender email in Brevo dashboard
- Check server logs for email sending errors

### App can't connect to server

- Update `baseUrl` in `mediabot_app/lib/services/api_service.dart`
- Rebuild the Flutter app
- Make sure server CORS is enabled (already configured)

### Database errors

- Make sure `db/` directory exists and is writable
- Delete `db/mediabot.db` to recreate database
- Server will auto-create tables on startup

---

## Deployment Platforms

This project works on any platform with:
- ✅ Long-running Node.js processes
- ✅ Ability to install system packages (yt-dlp, ffmpeg)
- ✅ Persistent file storage

**Recommended platforms:**
- **Railway** (supports buildpacks for ffmpeg)
- **Render** (Web Service with custom build commands)
- **DigitalOcean App Platform** (with Dockerfile)
- **AWS EC2, Google Cloud Compute, Azure VM** (full control)
- **Any VPS** (Ubuntu, CentOS, etc.)

**❌ NOT compatible with:**
- Vercel, Netlify Functions (serverless, no system packages)
- AWS Lambda (limited execution time, no ffmpeg by default)

---

## Common Deployment Issues & Solutions

### Issue: yt-dlp not found

**Error:** `Command failed: yt-dlp`

**Solution:**
```bash
# SSH into server
pip3 install yt-dlp
# or
sudo pip3 install yt-dlp

# Add to PATH if needed
export PATH="$HOME/.local/bin:$PATH"
```

### Issue: ffmpeg not found

**Error:** `Command failed: ffmpeg`

**Solution:**
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install ffmpeg

# CentOS/RHEL
sudo yum install ffmpeg
```

### Issue: Permission denied on downloads folder

**Error:** `EACCES: permission denied, mkdir '/app/downloads'`

**Solution:**
```bash
# Create directory with correct permissions
mkdir downloads
chmod 755 downloads
```

### Issue: Database locked

**Error:** `SQLITE_BUSY: database is locked`

**Solution:**
```bash
# Stop all running instances
pm2 stop all
pm2 delete all

# Start fresh
pm2 start app.js --name mediabot
```

---

## Environment Variables Reference

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `PORT` | No | Server port | `3000` |
| `JWT_SECRET` | Yes | Secret for JWT tokens | `super-secret-key-change-this` |
| `BREVO_API_KEY` | Yes | Brevo API key for emails | `xkeysib-xxxxx...` |
| `SENDER_EMAIL` | Yes | Email sender address | `noreply@yourdomain.com` |
| `SENDER_NAME` | No | Email sender name | `MediaBot` |

---

## License

MIT

---

## Support

For issues or questions:
- GitHub: [KRIPAVERMA/mediabotbackend](https://github.com/KRIPAVERMA/mediabotbackend)
- Email: Check `.env` SENDER_EMAIL
