$ytdlp = Join-Path $PSScriptRoot "bin\yt-dlp.exe"

if (-not (Test-Path $ytdlp)) {
    Write-Host ""
    Write-Host "  [!] Please run setup.bat first." -ForegroundColor Red
    Write-Host ""
    Read-Host "  Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "  ============================================"
Write-Host "     YouTube Playlist Downloader"
Write-Host "  ============================================"
Write-Host ""

$url = ""
while (-not $url) {
    $url = (Read-Host "  Paste the YouTube playlist URL").Trim()
}

$folder = (Read-Host "  Save folder (press Enter for 'downloads')").Trim()
if (-not $folder) { $folder = "downloads" }

Write-Host ""
Write-Host "  Format:"
Write-Host "    1  -  MP4  (video + audio)  [default]"
Write-Host "    2  -  MP3  (audio only)"
Write-Host ""
$choice = (Read-Host "  Your choice [1/2]").Trim()
Write-Host ""

New-Item -ItemType Directory -Force -Path $folder | Out-Null

if ($choice -eq "2") {
    & $ytdlp `
        --extract-audio --audio-format mp3 --audio-quality 192K `
        -o "$folder\%(playlist_index)s - %(title)s.%(ext)s" `
        --ignore-errors --retries 5 `
        $url
} else {
    & $ytdlp `
        -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" `
        --merge-output-format mp4 `
        -o "$folder\%(playlist_index)s - %(title)s.%(ext)s" `
        --ignore-errors --retries 5 `
        $url
}

Write-Host ""
Write-Host "  Done! Files saved to: $((Resolve-Path $folder).Path)"
Write-Host ""
Read-Host "  Press Enter to close"
