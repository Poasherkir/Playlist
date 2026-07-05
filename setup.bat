@echo off
echo.
echo  ============================================
echo     YouTube Playlist Downloader - Setup
echo  ============================================
echo.

echo  [1/3] Checking Python...
python --version >nul 2>&1
if errorlevel 1 (
    echo        Not found. Installing Python...
    winget install --id Python.Python.3 -e --source winget --accept-source-agreements --accept-package-agreements
    echo.
    echo        Python installed. Please run setup.bat again.
    pause
    exit
) else (
    for /f "tokens=*" %%i in ('python --version') do echo        Found: %%i
)

echo  [2/3] Installing yt-dlp...
pip install -q --upgrade yt-dlp
echo        Done.

echo  [3/3] Installing ffmpeg...
winget install --id Gyan.FFmpeg -e --source winget --accept-source-agreements --accept-package-agreements >nul 2>&1
echo        Done.

echo.
echo  ============================================
echo     Setup complete!
echo     You can now double-click start.bat
echo     to download playlists.
echo  ============================================
echo.
pause
