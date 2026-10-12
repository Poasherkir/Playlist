@echo off
title YouTube Playlist Downloader
setlocal

rem Two ways this file gets used. Next to the rest of the project it just runs
rem it. On its own, downloaded from the site, it fetches the project first,
rem and fetches it again at every start so fixes arrive by themselves.

rem A link given to this file goes on in PD_URL. Passed along on a command
rem line, cmd would cut a YouTube link short at its first ampersand.
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

rem The new pair only replaces the old one if both arrived whole: each must
rem end with its marker line, and the script must parse. Offline, or with a
rem download cut short, the copy from last time carries on.
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
