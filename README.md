# YouTube Playlist Downloader

Downloads a whole YouTube playlist as MP4 video or MP3 music, through a page in
your browser. Windows only.

About page: **https://playlist-downloader-eight.vercel.app**

## How to use it

Copy the playlist link, then double-click **Download Playlist.bat**.

A small black window opens and your browser opens a page. On that page:

1. If you copied the link first, it's already filled in — otherwise paste it
   anywhere on the page and it checks it straight away.
2. It shows the playlist name and how many videos, and suggests a folder in
   Downloads named after the playlist. Change it if you like.
3. Pick video, smaller video, or music, then **Start download**.

You get a progress bar, the current video's name, speed, and a list ticking off
as each one finishes. When it's done, **Open folder** takes you straight there.

**The black window is the downloader.** Closing it stops everything. The browser
page is just the controls, so you can close and reopen the tab freely, or come
back to it at the address printed in that window.

The first run takes a few minutes longer, because it fetches the tools it needs
(around 150 MB) into a `bin` folder next to the script. Nothing is installed on
your PC, nothing is added to your PATH, and deleting the folder removes every
trace. Later runs open the page straight away.

## Good to know

- **You can stop it any time.** Press Stop, or close the black window. Run it
  again later, pick the same folder, and it carries on where it left off.
  Finished videos are listed in `already-downloaded.txt` inside that folder,
  which is how it knows what to skip. Delete that file to force a fresh
  download of everything.
- Videos that fail (deleted, private, region-locked) are skipped instead of
  stopping the run. Running it again retries them.
- Files are numbered `001 - Title.mp4` so they stay in playlist order.
- MP3s get the video thumbnail as cover art and proper track titles, so they
  look right in a music player.
- A link like `watch?v=...&list=...` downloads the whole playlist, not just the
  one video you happened to be watching.
- The page is served only to your own machine, on localhost. Nobody else can
  reach it.

## If something goes wrong

**A download manager grabs the video instead.** IDM and similar tools hook into
your browser and snatch anything that looks like a media file. This downloader
runs outside the browser, so they cannot see its downloads — but they will grab
the video if a YouTube page is opened in the browser itself, which is what
happens if the link goes into the address bar instead of the page. Paste it
anywhere on the downloader's page instead. To stop IDM doing it at all, open
IDM, then Options, then General, and switch off integration for your browser.

**Downloads fail or stall.** Nearly always yt-dlp being out of date after a
change on YouTube's side. The script updates it by itself once a week; to force
it now, delete the `bin` folder and run again.

**"Confirm you're not a bot".** That video needs a signed-in account. No script
setting gets around it.

**The page doesn't open.** Look at the black window: it prints the address,
normally `http://localhost:8730/`. Open that by hand. If a port is busy the
script moves up until it finds a free one, so the number may differ.

## Why the website doesn't do the downloading

The page on Vercel describes the tool and hands out the link. It cannot do the
downloading, and nor could any hosted version:

- YouTube blocks datacenter IPs. Requests from Vercel, AWS and similar hosts get
  the bot check almost immediately, while the same request from a home
  connection is fine.
- Serverless functions time out after 10-60 seconds and have no disk. A playlist
  is minutes of work and gigabytes of files.
- It would be against YouTube's terms and most hosts' acceptable use policies.

Running the page on your own machine sidesteps all of it, and you still get a
real interface instead of a console.

## What's in here

| | |
|---|---|
| `Download Playlist.bat` | What you double-click. |
| `playlist.ps1` | Serves the page and drives yt-dlp. |
| `ui.html` | The page itself. |
| `site/` | The public page, deployed to Vercel. |
| `bin/` | Tools, fetched on first run. Safe to delete. |

Built on [yt-dlp](https://github.com/yt-dlp/yt-dlp) and
[ffmpeg](https://ffmpeg.org).
