@echo off
setlocal
echo.
echo  ============================================
echo     YouTube Playlist Downloader - Setup
echo  ============================================
echo.

if not exist "%~dp0bin" mkdir "%~dp0bin"

echo  [1/2] Downloading yt-dlp...
curl -L "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" -o "%~dp0bin\yt-dlp.exe" --progress-bar
if errorlevel 1 (
    echo.
    echo  [!] Download failed. Check your internet connection and try again.
    pause
    exit /b 1
)
echo        Done.
echo.

echo  [2/2] Installing ffmpeg...
winget install --id Gyan.FFmpeg -e --source winget --accept-source-agreements --accept-package-agreements
echo        Done.
echo.

echo  ============================================
echo     All done! Double-click start.bat
echo     whenever you want to download a playlist.
echo  ============================================
echo.
pause
