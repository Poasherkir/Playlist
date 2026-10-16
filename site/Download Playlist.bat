@echo off
title YouTube Playlist Downloader
setlocal

rem next to playlist.ps1: just run it. standalone: download the latest
rem playlist.ps1 + ui.html on every start, then run

rem pass the link on in an env var, cmd breaks urls at &
set "PD_URL=%~1"

if exist "%~dp0playlist.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0playlist.ps1"
    exit /b
)

set "APP=%~dp0Playlist Downloader"
set "BASE=https://raw.githubusercontent.com/Poasherkir/Playlist/master"

if not exist "%APP%" mkdir "%APP%"
if exist "%APP%\.git" goto run

if not exist "%APP%\playlist.ps1" (
    echo.
    echo   Getting things ready, one moment.
)
curl -L --fail -s --connect-timeout 5 --max-time 30 -o "%APP%\playlist.ps1.new" "%BASE%/playlist.ps1" -o "%APP%\ui.html.new" "%BASE%/ui.html"

rem only swap in the new files if both end with their marker and the ps1
rem parses. otherwise (offline etc) keep last time's copy
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$d = $env:APP; $ps = Join-Path $d 'playlist.ps1.new'; $ui = Join-Path $d 'ui.html.new'; $bad = $null;" ^
  "$ok = (Test-Path $ps) -and (Test-Path $ui) -and (Select-String -LiteralPath $ps -SimpleMatch '# PLAYLIST-DOWNLOADER-ENGINE' -Quiet) -and (Select-String -LiteralPath $ui -SimpleMatch '<!-- PLAYLIST-DOWNLOADER-UI -->' -Quiet);" ^
  "if ($ok) { [void][Management.Automation.Language.Parser]::ParseFile($ps, [ref]$null, [ref]$bad); $ok = -not $bad };" ^
  "if ($ok) { Move-Item $ps (Join-Path $d 'playlist.ps1') -Force; Move-Item $ui (Join-Path $d 'ui.html') -Force };" ^
  "Remove-Item $ps, $ui -Force -ErrorAction SilentlyContinue"

:run
if not exist "%APP%\playlist.ps1" (
    echo.
    echo   Could not download the downloader. Check your connection and try again.
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%APP%\playlist.ps1"
