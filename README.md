# YouTube Playlist Downloader

Downloads a whole YouTube playlist as MP4 video or MP3 music. Windows only.

## How to use it

Copy the playlist link, then double-click **Download Playlist.bat**.

It asks three things:

1. The link. If it's already on your clipboard, just press Enter.
2. Where to save it. Press Enter for a new folder in Downloads named after the
   playlist.
3. Video, smaller video, or music.

Then it downloads.

The first run takes a few minutes longer, because it fetches the tools it needs
(around 150 MB) into a `bin` folder next to the script. Nothing is installed on
your PC, nothing is added to your PATH, and deleting the folder removes every
trace. Later runs skip straight to the questions.

## Good to know

- **You can stop it any time.** Close the window, run it again later, pick the
  same folder, and it carries on where it left off. Finished videos are listed
  in `already-downloaded.txt` inside that folder, which is how it knows what to
  skip. Delete that file to force a fresh download of everything.
- Videos that fail (deleted, private, region-locked) are skipped instead of
  stopping the run. Running it again retries them.
- Files are numbered `001 - Title.mp4` so they stay in playlist order.
- MP3s get the video thumbnail as cover art and proper track titles, so they
  look right in a music player.
- A link like `watch?v=...&list=...` downloads the whole playlist, not just the
  one video you happened to be watching.

## If something goes wrong

Nearly always it's yt-dlp being out of date after a change on YouTube's side.
The script updates it by itself once a week; to force it now, delete the `bin`
folder and run it again.

If YouTube demands that you "confirm you're not a bot", that video needs a
signed-in account. No script setting gets around it.
