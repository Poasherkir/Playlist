# YouTube Playlist Downloader

Downloads a whole YouTube playlist as MP4 video or MP3 music, through a page in
your browser. Windows only.

## How to use it

Copy the playlist link, then double-click **Download Playlist.bat**.

A small black window opens and your browser opens a page. On that page:

1. The link is already filled in if you copied it. Press **Check**.
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

Nearly always it's yt-dlp being out of date after a change on YouTube's side.
The script updates it by itself once a week; to force it now, delete the `bin`
folder and run it again.

If YouTube demands that you "confirm you're not a bot", that video needs a
signed-in account. No script setting gets around it.

## Why it isn't a hosted website

Because it can't be. Downloading has to happen on your own machine:

- YouTube blocks datacenter IPs. Requests from Vercel, AWS and similar hosts get
  the bot check almost immediately, while the same request from a home
  connection is fine.
- Serverless functions time out after 10-60 seconds and have no disk. A playlist
  is minutes of work and gigabytes of files.
- It would be against YouTube's terms and most hosts' acceptable use policies.

Running the page locally sidesteps all of it, and you still get a real interface
instead of a console.
