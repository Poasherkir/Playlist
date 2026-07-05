# YouTube Playlist Downloader

Downloads an entire YouTube playlist as MP4 files using `yt-dlp`.

## Requirements

- Python 3.x
- [yt-dlp](https://github.com/yt-dlp/yt-dlp): `pip install yt-dlp`
- [ffmpeg](https://ffmpeg.org/) (for merging video + audio): `winget install ffmpeg`

## Usage

```bash
python download_playlist.py <playlist_url> [output_folder]
```

**Examples:**
```bash
# Download to default "downloads/" folder
python download_playlist.py https://youtube.com/playlist?list=PL...

# Download to a custom folder
python download_playlist.py https://youtube.com/playlist?list=PL... my_playlist
```

## Features

- Downloads best quality MP4
- Numbers files by playlist order (`01 - Title.mp4`, `02 - Title.mp4`, ...)
- Skips unavailable/private videos automatically
- Resumes interrupted downloads
