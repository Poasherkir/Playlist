# YouTube Playlist Downloader

Grab a whole YouTube playlist as MP4 videos, or as MP3s with cover art. It's a
single .bat file you double-click. No install, no account, no admin rights.

**[Download it here](https://playlist-downloader-eight.vercel.app/Download%20Playlist.bat)**
(Windows 10 version 1803 or newer, or Windows 11)

![The downloader running: playlist name, current video, progress bar and speed, with finished videos ticked off](docs/preview.svg)

Website: **https://playlist-downloader-eight.vercel.app**

## Quick start

1. **Download the file.** Use the link above, the button on
   [the site](https://playlist-downloader-eight.vercel.app), or
   [the latest release](https://github.com/Poasherkir/Playlist/releases/latest).
   Put it wherever you want, the Desktop is fine.
2. **Copy the playlist link** from your browser's address bar.
3. **Double-click `Download Playlist.bat`.** A black window opens, then the
   downloader opens in your browser, counts down 5 seconds and starts on the
   link you copied.

The first run takes a few minutes because it has to download its tools. After
that it opens straight away. Videos go into your Downloads folder, in a folder
named after the playlist.

**Browser or Windows warnings:** the .bat isn't signed, so you'll probably get
one or two. In the browser pick **Keep**. If Windows says "Windows protected
your PC", click **More info** and then **Run anyway**. If it asks "Do you want
to run this file?", click **Run**. It's a plain text file, so you can open it
in Notepad and read it first if you want.

The .bat works on its own. The first time, it downloads the rest of the files
next to itself, and on every start it checks for newer versions, so you get
fixes without downloading it again. If it's sitting in a cloned copy of this
repo, it just runs what's there and never overwrites anything.

## Using it

If you copied a link before starting it, it gets picked up automatically.
There's a Cancel button during the countdown in case that link is an old one.

You can also just paste a link anywhere on the page and it starts. No need to
click in the box first or confirm anything. Paste several links at once, or
more while one is running, and they get queued, each into its own folder.

Format and folder are on the same screen and both get remembered. The formats:

- **Video** (default): H.264 MP4 with AAC audio, up to 1080p. Plays on any
  Windows 10 or 11 PC as is, in Films & TV, Media Player, VLC or on a TV.
- **Video, best quality**: up to 4K. Above 1080p YouTube only has VP9 and AV1,
  and Windows 10 needs Microsoft's free AV1 Video Extension from the Store to
  play AV1.
- **Music**: MP3, with the thumbnail as cover art and proper track titles.

Leave the folder empty and each playlist gets its own folder in Downloads.

While it runs you see "Video 7 of 42", how far through the playlist it is,
roughly how long is left, and every video marked as waiting, downloading,
joining, done, failed or already there. When it finishes you get a Windows
notification and the tab title changes. **Open folder** takes you to the files.

**Don't close the black window**, that's the actual downloader. The browser
page is only the controls, so you can close and reopen the tab whenever you
like (the address is printed in the black window). If you double-click the
.bat again while it's running, the link goes to the window that's already
open instead of starting a second one.

**Bookmarklet:** at the bottom of the page there's a **Download playlist**
link. Drag it to your bookmarks bar. Then on any YouTube page, with the black
window open, click it and that playlist starts downloading.

## Good to know

- **You can stop it any time.** Press Stop or close the black window. Next time
  pick the same folder and it carries on where it left off, even halfway
  through a video.
- **Videos are checked before they count as done.** Each file is opened with
  ffprobe, and only files with both picture and sound (just sound for MP3s)
  get written to `already-downloaded.mp4.txt` or `already-downloaded.mp3.txt`
  in that folder. That's how it knows what to skip. Video and music have
  separate lists, so you can download a playlist as both into one folder.
  Delete a list to download everything again. The old `already-downloaded.txt`
  from 1.0 is still read for video.
- **Failed videos come with a reason.** Private, removed, region-locked or
  age-restricted videos get skipped, the rest of the playlist keeps going, and
  they're listed at the end with why. Things that might work a second time (a
  dropped connection, YouTube refusing a request) get one more try after a
  short pause, and **Retry failed videos** tries again whenever you want.
- Every video ends up as one MP4 with picture and sound. YouTube sends them
  separately, so they're downloaded and joined in a hidden `.incomplete`
  folder and only the finished file gets moved into yours. Anything that got
  interrupted waits in there and resumes next time.
- Files are numbered `001 - Title.mp4` so they stay in playlist order.
- A `watch?v=...&list=...` link gets the whole playlist, not just the video
  you were watching.
- Nothing gets installed. The tools live in a `bin` folder next to the script
  (about 150 MB), your PATH and registry aren't touched, and deleting that
  folder removes everything. yt-dlp, the part that does the downloading,
  updates itself on every start.
- The page only runs on localhost, so nobody else can reach it, and other
  websites can't start or stop anything through it.

## Troubleshooting

**IDM or another download manager grabs the video.** These hook into your
browser and grab anything that looks like a video file. The downloader runs
outside the browser, so they can't see its downloads. They'll still jump in if
a YouTube page opens in the browser itself, which is what happens when you put
the link in the address bar, so paste it on the downloader's page instead. To
stop IDM doing it at all, go to Options > General in IDM and turn off
integration for your browser.

You don't need IDM to get picture and sound in one file. YouTube sends them as
two streams to everyone, IDM included. IDM joins them in the background, and
so does this.

**Old downloads came out as two files, picture in one and sound in the
other.** Version 1.0 did that when ffmpeg failed to start, leaving files like
`001 - Title.f137.mp4` and `001 - Title.f140.m4a`. Run the same playlist into
that folder again and the page offers **Repair split videos**. It joins each
pair into one MP4, checks it, and only then deletes the halves. If a half
can't be joined it's taken off the done list, so **Retry** downloads it whole.

**"ffmpeg will not run".** It's checked on every start, since picture and
sound can't be joined without it. Usually it's antivirus holding back
`bin\ffmpeg.exe`. Allow it, delete the `bin` folder and run it again.

**"YouTube blocked the request" or "confirm you're not a bot".** Almost always
this is yt-dlp being behind after YouTube changed something. It updates on
every start, but if several videos in a playlist still get blocked, the page
shows **Fix: update the downloader engine**. That switches yt-dlp to its
nightly build, which usually has the fix days before a normal release, and
tries the blocked videos again. It only does that when you click it.

**Age-restricted videos** need a signed-in account. If you want them, export
your YouTube cookies to a file called `cookies.txt` (an extension like "Get
cookies.txt LOCALLY" can do it) and put it next to `playlist.ps1`. It's used if
it's there and ignored if not. Treat that file like a password and delete it
when you're done.

**The page doesn't open.** The black window shows the address, usually
`http://localhost:8730/`. Open it yourself. If that port is taken it tries the
next ones up, so the number might be different.

## Updating from 1.0

If you got the .bat from the site before 1.1, download `Download Playlist.bat`
one more time and replace the old one. The new one keeps itself up to date
after that. If you cloned the repo, just `git pull`.

## Why isn't it just a website?

The site on Vercel only describes the tool and links to it. It can't download
anything, and a hosted version wouldn't work anyway:

- YouTube blocks datacenter IPs. Requests from Vercel, AWS and so on hit the
  bot check almost straight away, while the same request from a home
  connection is fine.
- Serverless functions time out after 10 to 60 seconds and have no disk. A
  playlist takes minutes and can be gigabytes.
- It would break YouTube's terms and most hosts' acceptable use policies.

Running it on your own PC gets around all three, and you still get a proper
interface instead of a console.

## What's in here

| | |
|---|---|
| `Download Playlist.bat` | What you double-click. On its own, it downloads the rest and keeps it up to date. |
| `playlist.ps1` | Serves the page and runs yt-dlp. |
| `ui.html` | The page. |
| `site/` | The website (deployed to Vercel), plus a copy of the launcher it hands out. |
| `bin/` | Tools, downloaded on first run. Safe to delete. |

Built on [yt-dlp](https://github.com/yt-dlp/yt-dlp) and
[ffmpeg](https://ffmpeg.org), under the [MIT licence](LICENSE).
Only download stuff you have the right to download.
