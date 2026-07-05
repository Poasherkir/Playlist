import yt_dlp
import sys
import os
import shutil


def check_ffmpeg():
    return shutil.which("ffmpeg") is not None


def ask(prompt, default=None):
    suffix = f" (press Enter for '{default}')" if default else ""
    while True:
        answer = input(f"{prompt}{suffix}: ").strip()
        if answer:
            return answer
        if default is not None:
            return default
        print("  Required — please enter a value.")


def download_playlist(url, output_dir, mode):
    os.makedirs(output_dir, exist_ok=True)
    has_ffmpeg = check_ffmpeg()

    if not has_ffmpeg:
        print("\n  [!] ffmpeg not found — video and audio won't be merged.")
        print("      Fix: open a new terminal and run:  winget install ffmpeg\n")

    if mode == "audio":
        ydl_opts = {
            "format": "bestaudio/best",
            "outtmpl": os.path.join(output_dir, "%(playlist_index)s - %(title)s.%(ext)s"),
            "ignoreerrors": True,
            "quiet": True,
            "no_warnings": True,
            "retries": 5,
            "fragment_retries": 5,
        }
        if has_ffmpeg:
            ydl_opts["postprocessors"] = [{
                "key": "FFmpegExtractAudio",
                "preferredcodec": "mp3",
                "preferredquality": "192",
            }]
    else:
        ydl_opts = {
            "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
            "merge_output_format": "mp4",
            "outtmpl": os.path.join(output_dir, "%(playlist_index)s - %(title)s.%(ext)s"),
            "ignoreerrors": True,
            "quiet": True,
            "no_warnings": True,
            "retries": 5,
            "fragment_retries": 5,
        }

    counts = {"done": 0, "failed": 0}

    def progress_hook(d):
        if d["status"] == "downloading":
            pct   = d.get("_percent_str", "  ?%").strip().rjust(5)
            speed = d.get("_speed_str",  "?/s").strip()
            eta   = d.get("_eta_str",    "?s").strip()
            print(f"\r    {pct}  |  {speed}  |  ETA {eta}    ", end="", flush=True)
        elif d["status"] == "finished":
            print()
            counts["done"] += 1
        elif d["status"] == "error":
            print()
            counts["failed"] += 1

    ydl_opts["progress_hooks"] = [progress_hook]

    print("\n  Fetching playlist info...", end="", flush=True)
    with yt_dlp.YoutubeDL({**ydl_opts, "quiet": True, "extract_flat": True}) as ydl:
        info = ydl.extract_info(url, download=False)

    playlist_title = info.get("title", "Unknown Playlist") if info else "Unknown"
    total = len(info.get("entries", [])) if info else "?"
    print(f"\r  Playlist : {playlist_title}")
    print(f"  Videos   : {total}")
    print(f"  Format   : {'MP3 — audio only' if mode == 'audio' else 'MP4 — video + audio'}")
    print(f"  Save to  : {os.path.abspath(output_dir)}")
    print()

    current = [0]
    original_hook = ydl_opts["progress_hooks"][0]

    def counting_hook(d):
        if d["status"] == "downloading":
            # Print current video number on the line above progress
            pass
        original_hook(d)

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        entries = info.get("entries", []) if info else []
        for i, entry in enumerate(entries, 1):
            if not entry:
                continue
            title = entry.get("title", "Unknown")[:60]
            print(f"  [{i}/{total}] {title}")
            ydl.download([entry.get("url") or entry.get("webpage_url")])

    print()
    print("  " + "=" * 46)
    print(f"  Download finished!")
    print(f"  Success : {counts['done']}  |  Failed : {counts['failed']}")
    print(f"  Folder  : {os.path.abspath(output_dir)}")
    print("  " + "=" * 46)
    print()


def main():
    print()
    print("  " + "=" * 46)
    print("        YouTube Playlist Downloader")
    print("  " + "=" * 46)
    print()

    # URL
    if len(sys.argv) >= 2:
        url = sys.argv[1]
        print(f"  URL     : {url}")
    else:
        url = ask("  Paste the YouTube playlist URL")

    # Output folder
    if len(sys.argv) >= 3:
        output_dir = sys.argv[2]
    else:
        output_dir = ask("  Save folder", default="downloads")

    # Format
    print()
    print("  Format:")
    print("    1 — MP4  (video + audio)  [default]")
    print("    2 — MP3  (audio only)")
    print()
    choice = input("  Your choice [1/2]: ").strip()
    mode = "audio" if choice == "2" else "video"
    print()

    try:
        download_playlist(url, output_dir, mode)
    except KeyboardInterrupt:
        print("\n\n  Cancelled by user.")
        sys.exit(0)


if __name__ == "__main__":
    main()
