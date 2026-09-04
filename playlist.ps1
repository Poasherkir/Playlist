# Drives yt-dlp with defaults that suit whole playlists.
# On first run it puts the tools it needs in bin\, so nothing is installed
# system-wide and nothing has to be set up by hand.

$ErrorActionPreference = 'Stop'

$bin    = Join-Path $PSScriptRoot 'bin'
$ytdlp  = Join-Path $bin 'yt-dlp.exe'
$ffmpeg = Join-Path $bin 'ffmpeg.exe'
$deno   = Join-Path $bin 'deno.exe'

$ytdlpUrl = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'
$denoUrl  = 'https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip'
$ffmpegUrls = @(
    'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip',
    'https://github.com/BtbN/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip'
)

function Fetch($url, $dest) {
    & curl.exe -L --fail --progress-bar -o $dest $url
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $url" }
}

function Install-FromZip($urls, $wanted, $label) {
    $zip  = Join-Path $env:TEMP 'playlist-tool.zip'
    $work = Join-Path $env:TEMP 'playlist-tool'
    $got  = $false
    foreach ($u in $urls) {
        try { Fetch $u $zip; $got = $true; break } catch { }
    }
    if (-not $got) { throw "Could not download $label. Check the internet connection and try again." }

    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive -Path $zip -DestinationPath $work -Force
    Get-ChildItem $work -Recurse -Include $wanted | ForEach-Object { Copy-Item $_.FullName $bin -Force }
    Remove-Item $zip  -Force -ErrorAction SilentlyContinue
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

# yt-dlp needs a JavaScript engine to unscramble the download links YouTube
# hands out. Without one, downloads get throttled or fail outright.
function Get-JsRuntime {
    if (Test-Path $deno) { return @('--js-runtimes', "deno:$bin") }
    foreach ($runtime in 'deno', 'node', 'bun') {
        if (Get-Command $runtime -ErrorAction SilentlyContinue) { return @('--js-runtimes', $runtime) }
    }
    return @()
}

function Install-Tools {
    $needsJs = (Get-JsRuntime).Count -eq 0
    if ((Test-Path $ytdlp) -and (Test-Path $ffmpeg) -and -not $needsJs) { return }

    Write-Host '  First run, so it has to fetch its tools. This takes a few minutes.'
    Write-Host '  They go in the bin folder next to this script and stay there.'
    Write-Host ''
    New-Item -ItemType Directory -Force -Path $bin | Out-Null

    if (-not (Test-Path $ytdlp)) {
        Write-Host '  yt-dlp'
        Fetch $ytdlpUrl $ytdlp
    }
    if (-not (Test-Path $ffmpeg)) {
        Write-Host '  ffmpeg'
        Install-FromZip $ffmpegUrls @('ffmpeg.exe', 'ffprobe.exe') 'ffmpeg'
        if (-not (Test-Path $ffmpeg)) { throw 'ffmpeg did not unpack properly. Delete the bin folder and try again.' }
    }
    if ($needsJs) {
        Write-Host '  deno'
        Install-FromZip @($denoUrl) @('deno.exe') 'deno'
        if (-not (Test-Path $deno)) { throw 'deno did not unpack properly. Delete the bin folder and try again.' }
    }

    Write-Host ''
}

# YouTube changes things often, so keep yt-dlp reasonably fresh.
function Update-Ytdlp {
    if (((Get-Date) - (Get-Item $ytdlp).LastWriteTime).TotalDays -lt 7) { return }
    Write-Host '  Checking for a yt-dlp update'
    try { & $ytdlp -U | Out-Null } catch { }
    try { (Get-Item $ytdlp).LastWriteTime = Get-Date } catch { }
}

function Get-SafeName($name) {
    $bad = [Regex]::Escape(-join [IO.Path]::GetInvalidFileNameChars())
    $out = (($name -replace "[$bad]", ' ') -replace '\s+', ' ').Trim().TrimEnd('.')
    if ($out.Length -gt 80) { $out = $out.Substring(0, 80).Trim() }
    if ($out) { $out } else { 'Playlist' }
}

function Read-Link {
    $clip = ''
    try { $clip = (Get-Clipboard -Raw).Trim() } catch { }
    if ($clip -notmatch '^https?://\S*(youtube\.com|youtu\.be)') { $clip = '' }

    if ($clip) {
        Write-Host '  Link on your clipboard:'
        Write-Host "  $clip"
        Write-Host ''
        $answer = (Read-Host '  Press Enter to use it, or paste a different link').Trim()
        if (-not $answer) { return $clip }
        return $answer
    }

    while ($true) {
        $answer = (Read-Host '  Paste the YouTube link').Trim()
        if ($answer -match 'youtube\.com|youtu\.be' -or $answer -match '^https?://') { return $answer }
        if ($answer) { Write-Host '  That is not a link. Copy it from your browser address bar.' }
    }
}

try {
    Write-Host ''
    Write-Host '  YouTube Playlist Downloader'
    Write-Host ''

    Install-Tools
    Update-Ytdlp
    $js = Get-JsRuntime

    $url = (Read-Link).Trim('"')

    Write-Host ''
    Write-Host '  Reading the playlist...'
    $titles = @(& $ytdlp @js --flat-playlist --ignore-errors --no-warnings --print '%(playlist_title)s' -- $url)
    if ($titles.Count -eq 0) {
        throw 'That link did not work. Make sure it is a public YouTube video or playlist.'
    }

    $isPlaylist = $titles[0] -and $titles[0] -ne 'NA'
    if ($isPlaylist) {
        Write-Host "  $($titles[0])  -  $($titles.Count) videos"
        $suggested = Join-Path "$env:USERPROFILE\Downloads" (Get-SafeName $titles[0])
    } else {
        Write-Host '  Single video'
        $suggested = Join-Path "$env:USERPROFILE\Downloads" 'YouTube'
    }

    Write-Host ''
    Write-Host "  Save to: $suggested"
    $folder = (Read-Host '  Press Enter to accept, or type another folder').Trim().Trim('"')
    if (-not $folder) { $folder = $suggested }
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $folder = (Resolve-Path $folder).Path

    Write-Host ''
    Write-Host '    1   Video, best quality   (default)'
    Write-Host '    2   Video, up to 1080p    (smaller files)'
    Write-Host '    3   Music only, MP3'
    Write-Host ''
    $choice = (Read-Host '  Choose 1, 2 or 3').Trim()

    switch ($choice) {
        '3' {
            $format = @(
                '-f', 'bestaudio/best',
                '--extract-audio', '--audio-format', 'mp3', '--audio-quality', '0',
                '--embed-thumbnail', '--embed-metadata'
            )
        }
        '2' {
            $format = @(
                '-f', 'bv*[height<=1080][ext=mp4]+ba[ext=m4a]/bv*[height<=1080]+ba/b[height<=1080]/b',
                '--merge-output-format', 'mp4'
            )
        }
        default {
            $format = @(
                '-f', 'bv*[ext=mp4]+ba[ext=m4a]/bv*+ba/b',
                '--merge-output-format', 'mp4'
            )
        }
    }

    if ($isPlaylist) { $template = '%(playlist_index)03d - %(title)s.%(ext)s' }
    else             { $template = '%(title)s.%(ext)s' }

    $options = @(
        '--paths', $folder,
        '-o', $template,
        '--ffmpeg-location', $bin,
        '--download-archive', (Join-Path $folder 'already-downloaded.txt'),
        '--concurrent-fragments', '4',
        '--retries', '10',
        '--fragment-retries', '10',
        '--ignore-errors',
        '--no-mtime',
        '--windows-filenames',
        '--console-title'
    )
    # A link copied off a playlist page names a video as well as the playlist.
    # Without this, yt-dlp quietly takes that one video and stops.
    if ($url -match '[?&]list=') { $options += '--yes-playlist' }

    Write-Host ''
    & $ytdlp @js @options @format -- $url
    $skipped = $LASTEXITCODE -ne 0

    Write-Host ''
    if ($skipped) {
        Write-Host '  Finished, but some videos were skipped.'
        Write-Host '  Run this again and it will retry just those.'
    } else {
        Write-Host '  All done.'
    }
    Write-Host "  Saved in $folder"
    Write-Host ''
    Read-Host '  Press Enter to open the folder' | Out-Null
    Start-Process explorer.exe $folder
}
catch {
    Write-Host ''
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ''
    Read-Host '  Press Enter to close' | Out-Null
}
