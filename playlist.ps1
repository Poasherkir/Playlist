# Serves the page in ui.html on localhost and runs yt-dlp behind it.
# On first run it puts the tools it needs in bin\, so nothing is installed
# system-wide and nothing has to be set up by hand.

$ErrorActionPreference = 'Stop'

$bin     = Join-Path $PSScriptRoot 'bin'
$ytdlp   = Join-Path $bin 'yt-dlp.exe'
$ffmpeg  = Join-Path $bin 'ffmpeg.exe'
$ffprobe = Join-Path $bin 'ffprobe.exe'
$deno    = Join-Path $bin 'deno.exe'
$page    = Join-Path $PSScriptRoot 'ui.html'
$outLog  = Join-Path $bin 'run.out'
$errLog  = Join-Path $bin 'run.err'

$ytdlpUrl = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'
$denoUrl  = 'https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip'
$ffmpegUrls = @(
    'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip',
    'https://github.com/BtbN/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip'
)

# Into a side file first, so a download cut short never leaves a broken
# tool behind that the next run takes as installed.
function Fetch($url, $dest) {
    $part = "$dest.part"
    & curl.exe -L --fail --progress-bar -o $part $url
    if ($LASTEXITCODE -ne 0) {
        Remove-Item $part -Force -ErrorAction SilentlyContinue
        throw "Download failed: $url"
    }
    Move-Item $part $dest -Force
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

# YouTube sends picture and sound as two streams, and yt-dlp joins them
# with ffmpeg. If ffmpeg will not start, yt-dlp does not stop: it hands
# back the two halves as separate files and marks the video as done. So
# check that ffmpeg actually runs, not just that the file is there.
function Test-Ffmpeg {
    foreach ($exe in $ffmpeg, $ffprobe) {
        if (-not (Test-Path $exe)) { return $false }
        try { & $exe -version | Out-Null } catch { return $false }
        if ($LASTEXITCODE -ne 0) { return $false }
    }
    return $true
}

function Install-Tools {
    $needsJs  = (Get-JsRuntime).Count -eq 0
    $ffmpegOk = Test-Ffmpeg
    if ((Test-Path $ytdlp) -and $ffmpegOk -and -not $needsJs) { return }

    Write-Host '  First run, so it has to fetch its tools. This takes a few minutes.'
    Write-Host '  They go in the bin folder next to this script and stay there.'
    Write-Host ''
    New-Item -ItemType Directory -Force -Path $bin | Out-Null

    if (-not (Test-Path $ytdlp)) {
        Write-Host '  yt-dlp'
        Fetch $ytdlpUrl $ytdlp
    }
    if (-not $ffmpegOk) {
        Write-Host '  ffmpeg'
        Install-FromZip $ffmpegUrls @('ffmpeg.exe', 'ffprobe.exe') 'ffmpeg'
        if (-not (Test-Ffmpeg)) {
            throw ('ffmpeg will not run, and without it picture and sound would come out as two separate files. ' +
                   'Check your antivirus has not blocked bin\ffmpeg.exe, then delete the bin folder and try again.')
        }
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

# Start-Process takes one command line, not a list, so anything holding a
# space (the output template, most folder paths) has to be quoted by hand.
function Format-CommandLine($list) {
    ($list | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join ' '
}

# The log files are being written by yt-dlp while we read them.
function Read-Log($path) {
    if (-not (Test-Path $path)) { return @() }
    try {
        $stream = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        $reader = New-Object IO.StreamReader($stream)
        $text   = $reader.ReadToEnd()
        $reader.Close(); $stream.Close()
        return $text -split "`r?`n"
    } catch { return @() }
}

function Send-Reply($context, $body, $type) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($body)
    $context.Response.ContentType = $type
    $context.Response.ContentLength64 = $bytes.Length
    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $context.Response.Close()
}

function Send-Json($context, $object) {
    Send-Reply $context (ConvertTo-Json $object -Depth 5 -Compress) 'application/json; charset=utf-8'
}

function Send-Error($context, $message) {
    $context.Response.StatusCode = 400
    Send-Reply $context $message 'text/plain; charset=utf-8'
}

function Get-Body($context) {
    $reader = New-Object IO.StreamReader($context.Request.InputStream, $context.Request.ContentEncoding)
    $text = $reader.ReadToEnd()
    $reader.Close()
    if ($text) { return $text | ConvertFrom-Json }
    return $null
}

function Get-Clip {
    try {
        $text = (Get-Clipboard -Raw).Trim()
        if ($text -match 'youtube\.com|youtu\.be') { return $text }
    } catch { }
    return ''
}

try {
    Write-Host ''
    Write-Host '  Playlist Downloader'
    Write-Host ''

    Install-Tools
    Update-Ytdlp

    # yt-dlp writes in the local code page when its output goes to a pipe or
    # a file, and quietly drops whatever does not fit. An Arabic or Japanese
    # title came back blank, which could also make a playlist pass for a
    # single video.
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    $common = @(Get-JsRuntime) + @('--encoding', 'utf-8')

    $listener = New-Object System.Net.HttpListener
    $port = 0
    foreach ($try in 8730..8760) {
        try {
            $listener.Prefixes.Clear()
            $listener.Prefixes.Add("http://localhost:$try/")
            $listener.Start()
            $port = $try
            break
        } catch { }
    }
    if (-not $port) { throw 'Could not open a local port for the page.' }

    $address = "http://localhost:$port/"
    Write-Host "  Open in your browser:  $address"
    Write-Host '  Closing this window stops the downloader.'
    Write-Host ''
    Start-Process $address

    $job        = $null
    $total      = 0
    $unfinished = $null

    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $path    = $context.Request.Url.AbsolutePath

        try {
            switch ($path) {

                '/' {
                    # -Encoding matters: without it PowerShell 5.1 reads the
                    # file as ANSI and the page arrives with mangled symbols.
                    Send-Reply $context (Get-Content $page -Raw -Encoding UTF8) 'text/html; charset=utf-8'
                }

                '/api/defaults' {
                    Send-Json $context @{ clipboard = Get-Clip }
                }

                '/api/info' {
                    $url = (Get-Body $context).url
                    $titles = @(& $ytdlp @common --flat-playlist --ignore-errors --no-warnings --print '%(playlist_title)s' -- $url)
                    if ($titles.Count -eq 0) {
                        Send-Error $context 'That link did not work. Make sure it is a public YouTube video or playlist.'
                        break
                    }
                    $isPlaylist = $titles[0] -and $titles[0] -ne 'NA'
                    if ($isPlaylist) {
                        $name  = $titles[0]
                        $total = $titles.Count
                    } else {
                        $single = @(& $ytdlp @common --no-warnings --print '%(title)s' --skip-download -- $url)
                        $name   = if ($single.Count) { $single[0] } else { 'Video' }
                        $total  = 1
                    }
                    Send-Json $context @{
                        url        = $url
                        title      = $name
                        count      = $total
                        isPlaylist = [bool]$isPlaylist
                        suggested  = Join-Path "$env:USERPROFILE\Downloads" (Get-SafeName $name)
                    }
                }

                '/api/start' {
                    $body   = Get-Body $context
                    $folder = $body.folder
                    New-Item -ItemType Directory -Force -Path $folder | Out-Null
                    $folder = (Resolve-Path $folder).Path
                    Remove-Item $outLog, $errLog -Force -ErrorAction SilentlyContinue

                    # The two streams are fetched and joined in a hidden folder,
                    # and only the finished video is moved out into the user's.
                    # A video cut short waits in there to be resumed next time
                    # instead of lying around as a picture-only file.
                    $unfinished = Join-Path $folder '.incomplete'
                    $dir = New-Item -ItemType Directory -Force -Path $unfinished
                    try { $dir.Attributes = $dir.Attributes -bor [IO.FileAttributes]::Hidden } catch { }

                    switch ($body.format) {
                        'mp3' {
                            $format = @('-f', 'bestaudio/best',
                                        '--extract-audio', '--audio-format', 'mp3', '--audio-quality', '0',
                                        '--embed-thumbnail', '--embed-metadata')
                        }
                        '1080' {
                            $format = @('-f', 'bv*[height<=1080][ext=mp4]+ba[ext=m4a]/bv*[height<=1080]+ba/b[height<=1080]/b',
                                        '--merge-output-format', 'mp4')
                        }
                        default {
                            $format = @('-f', 'bv*[ext=mp4]+ba[ext=m4a]/bv*+ba/b',
                                        '--merge-output-format', 'mp4')
                        }
                    }

                    if ($total -gt 1) { $template = '%(playlist_index)03d - %(title)s.%(ext)s' }
                    else              { $template = '%(title)s.%(ext)s' }

                    $options = @(
                        '--paths', $folder,
                        '--paths', "temp:$unfinished",
                        '-o', $template,
                        '--ffmpeg-location', $bin,
                        '--download-archive', (Join-Path $folder 'already-downloaded.txt'),
                        '--concurrent-fragments', '4',
                        '--retries', '10',
                        '--fragment-retries', '10',
                        '--ignore-errors',
                        '--no-mtime',
                        '--windows-filenames',
                        '--newline',
                        '--progress',
                        '--progress-template', 'download:DL|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s',
                        # The title gets a line of its own because the progress
                        # line ignores --encoding, and any letter the Windows
                        # code page lacks would vanish from it.
                        '--print', 'before_dl:NOW|%(title)s',
                        '--print', 'after_move:DONE|%(title)s'
                    )
                    # A link copied off a playlist page names a video as well as
                    # the playlist. Without this, yt-dlp takes that one video.
                    if ($body.url -match '[?&]list=') { $options += '--yes-playlist' }

                    $job = Start-Process -FilePath $ytdlp `
                        -ArgumentList (Format-CommandLine ($common + $options + $format + @('--', $body.url))) `
                        -NoNewWindow -PassThru `
                        -RedirectStandardOutput $outLog -RedirectStandardError $errLog
                    # Touching Handle makes .NET hold on to it, otherwise
                    # ExitCode reads back as null once yt-dlp finishes.
                    $null = $job.Handle
                    Send-Json $context @{ ok = $true }
                }

                '/api/progress' {
                    $lines = Read-Log $outLog
                    $done  = @($lines | Where-Object { $_.StartsWith('DONE|') } | ForEach-Object { $_.Substring(5) })
                    $now   = $lines | Where-Object { $_.StartsWith('NOW|') } | Select-Object -Last 1
                    $last  = $lines | Where-Object { $_.StartsWith('DL|') } | Select-Object -Last 1
                    $percent = ''; $speed = ''; $eta = ''
                    $title = if ($now) { $now.Substring(4) } else { '' }
                    if ($last) {
                        $parts   = $last.Split('|')
                        $percent = $parts[1].Trim()
                        $speed   = $parts[2].Trim()
                        $eta     = $parts[3].Trim()
                    }
                    # yt-dlp explains itself on stderr. Worth passing on, rather
                    # than leaving the page to guess why something was skipped.
                    $problems = @(Read-Log $errLog | Where-Object { $_ -match '^ERROR:' })
                    $finished = ($null -eq $job -or $job.HasExited)
                    if ($finished -and $unfinished -and (Test-Path $unfinished) -and -not (Get-ChildItem $unfinished -Force)) {
                        Remove-Item $unfinished -Force -ErrorAction SilentlyContinue
                    }
                    Send-Json $context @{
                        done     = $done
                        percent  = $percent
                        speed    = $speed
                        eta      = $eta
                        title    = $title
                        finished = $finished
                        exitCode = if ($finished -and $job) { $job.ExitCode } else { -1 }
                        problem  = if ($problems.Count) { $problems[-1] } else { '' }
                    }
                }

                '/api/stop' {
                    # /T takes ffmpeg down too if it is halfway through joining
                    # a video, so nothing is left holding files open.
                    if ($job -and -not $job.HasExited) { & taskkill.exe /PID $job.Id /T /F | Out-Null }
                    Send-Json $context @{ ok = $true }
                }

                '/api/open' {
                    $target = (Get-Body $context).folder
                    if (Test-Path $target) { Start-Process explorer.exe $target }
                    Send-Json $context @{ ok = $true }
                }

                default {
                    $context.Response.StatusCode = 404
                    Send-Reply $context 'Not found' 'text/plain'
                }
            }
        } catch {
            try { Send-Error $context $_.Exception.Message } catch { }
        }
    }
}
catch {
    Write-Host ''
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ''
    Read-Host '  Press Enter to close' | Out-Null
}
