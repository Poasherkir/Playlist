# YouTube Playlist Downloader

A simple Python script that downloads an entire YouTube playlist — just paste the link and go.

---

## Requirements

You need to install two things before using this script:

### 1. Python
Download from [python.org](https://www.python.org/downloads/) and make sure to check **"Add Python to PATH"** during installation.

### 2. yt-dlp
Open a terminal (CMD or PowerShell) and run:
```
pip install yt-dlp
```

### 3. ffmpeg (recommended)
Without ffmpeg, videos will download without audio. Install it with:
```
winget install ffmpeg
```
Then **close and reopen your terminal** so it takes effect.

---

## How to Use

### Step 1 — Open a terminal
Press `Win + R`, type `cmd`, and hit Enter.

### Step 2 — Run the script
```
python path\to\download_playlist.py
```
For example:
```
python C:\Users\YourName\Desktop\Playlist\download_playlist.py
```

### Step 3 — Follow the prompts
The script will ask you:
1. **Playlist URL** — paste your YouTube playlist link
2. **Save folder** — where to save the files (default: `downloads`)
3. **Format** — choose MP4 (video) or MP3 (audio only)

That's it. It will download every video and show you the progress.

---

## You can also pass arguments directly

```
python download_playlist.py <playlist_url> [folder]
```

Example:
```
python download_playlist.py https://youtube.com/playlist?list=PL... my_videos
```

---

## Output

Files are saved and numbered in playlist order:
```
downloads/
  01 - Video Title.mp4
  02 - Another Video.mp4
  ...
```

---

## Notes

- Unavailable or private videos are automatically skipped
- Interrupted downloads resume from where they stopped
- MP3 mode requires ffmpeg to convert audio
