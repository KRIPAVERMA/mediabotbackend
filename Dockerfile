# ── Stage 1: Base with system deps ───────────────────────────────
FROM node:20-slim

# Install ffmpeg + python3 + pip + build tools (for better-sqlite3 native module)
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    ffmpeg \
    curl \
    build-essential \
    && pip3 install --break-system-packages yt-dlp \
    && rm -rf /var/lib/apt/lists/*

# Verify yt-dlp & ffmpeg installed
RUN yt-dlp --version && ffmpeg -version | head -1

WORKDIR /app

# Install Node deps (separate layer for caching)
COPY package*.json ./
RUN npm ci --only=production

# Copy source
COPY . .

# Ensure writable directories exist
RUN mkdir -p downloads db

# Railway injects PORT env var automatically
EXPOSE 3000

CMD ["node", "app.js"]
