@echo off
title YouTube Playlist Downloader
setlocal

rem Two ways this file gets used. Next to the rest of the project it just runs
rem it. On its own, downloaded from the site, it fetches the project first.

if exist "%~dp0playlist.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0playlist.ps1"
    exit /b
)

set "APP=%~dp0Playlist Downloader"
set "BASE=https://raw.githubusercontent.com/Poasherkir/Playlist/master"

if not exist "%APP%" mkdir "%APP%"

if not exist "%APP%\playlist.ps1" (
    echo.
    echo   Getting things ready, one moment.
    curl -L --fail -s -o "%APP%\playlist.ps1" "%BASE%/playlist.ps1"
    curl -L --fail -s -o "%APP%\ui.html" "%BASE%/ui.html"
)

if not exist "%APP%\playlist.ps1" (
    echo.
    echo   Could not reach the internet. Check your connection and try again.
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%APP%\playlist.ps1"
