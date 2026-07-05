import yt_dlp
import sys
import os


def download_playlist(url: str, output_dir: str = "downloads"):
    os.makedirs(output_dir, exist_ok=True)

    ydl_opts = {
        "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
        "outtmpl": os.path.join(output_dir, "%(playlist_index)s - %(title)s.%(ext)s"),
        "ignoreerrors": True,       # skip unavailable videos instead of stopping
        "retries": 5,
        "fragment_retries": 5,
        "progress_hooks": [progress_hook],
    }

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        print(f"\nFetching playlist info: {url}\n")
        ydl.download([url])

    print(f"\nDone! Files saved to: {os.path.abspath(output_dir)}")


def progress_hook(d: dict):
    if d["status"] == "finished":
        print(f"  Downloaded: {os.path.basename(d['filename'])}")
    elif d["status"] == "error":
        print(f"  Error on: {d.get('filename', 'unknown')}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python download_playlist.py <playlist_url> [output_folder]")
        print("Example: python download_playlist.py https://youtube.com/playlist?list=PL... my_playlist")
        sys.exit(1)

    playlist_url = sys.argv[1]
    output_folder = sys.argv[2] if len(sys.argv) > 2 else "downloads"

    download_playlist(playlist_url, output_folder)
