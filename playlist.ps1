# playlist downloader engine: serves ui.html on localhost and drives yt-dlp.
# tools (yt-dlp, ffmpeg, deno) get downloaded into bin\ on first run.

# link from the launcher comes in via PD_URL (cmd chokes on & in urls)
param([string]$Url = $env:PD_URL)

$ErrorActionPreference = 'Stop'

$appVersion = '1.1.0'

$bin     = Join-Path $PSScriptRoot 'bin'
$ytdlp   = Join-Path $bin 'yt-dlp.exe'
$ffmpeg  = Join-Path $bin 'ffmpeg.exe'
$ffprobe = Join-Path $bin 'ffprobe.exe'
$deno    = Join-Path $bin 'deno.exe'
$page    = Join-Path $PSScriptRoot 'ui.html'
$cookies = Join-Path $PSScriptRoot 'cookies.txt'
$outLog  = Join-Path $bin 'run.out'
$errLog  = Join-Path $bin 'run.err'
$archive = Join-Path $bin 'run.archive'

$ytdlpUrl = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'
$denoUrl  = 'https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip'
$ffmpegUrls = @(
    'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip',
    'https://github.com/BtbN/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip'
)

# min deno version yt-dlp accepts for the youtube challenges
$denoMinimum = [version]'2.3.0'

$utf8 = New-Object Text.UTF8Encoding $false

# download to .part first so a cut-off download never looks installed
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

# Start-Process wants one command line string, so quote args by hand
# (backslashes only get doubled when a quote follows them)
function Format-CommandLine($list) {
    ($list | ForEach-Object {
        if ($_ -eq '' -or $_ -match '[\s"]') {
            '"' + (($_ -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
        } else { $_ }
    }) -join ' '
}

# run a tool and return its output. use instead of & when stderr matters:
# PS 5.1 throws on the first stderr line when EAP is Stop
function Invoke-Tool($exe, $list, $seconds) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName  = $exe
    $info.Arguments = Format-CommandLine $list
    $info.UseShellExecute = $false
    $info.CreateNoWindow  = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError  = $true
    $info.StandardOutputEncoding = [Text.Encoding]::UTF8
    $info.StandardErrorEncoding  = [Text.Encoding]::UTF8
    $proc = [Diagnostics.Process]::Start($info)
    # read both streams async, otherwise a full pipe can deadlock
    $out = $proc.StandardOutput.ReadToEndAsync()
    $err = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit($seconds * 1000)) {
        & taskkill.exe /PID $proc.Id /T /F | Out-Null
        return @{ Code = -1; Out = ''; Err = 'It took too long and was stopped.' }
    }
    $proc.WaitForExit()
    @{ Code = $proc.ExitCode; Out = $out.Result; Err = $err.Result }
}

# yt-dlp needs a js runtime for youtube's signature stuff,
# without one downloads get throttled or just fail
function Get-JsRuntime {
    if (Test-Path $deno) { return @('--js-runtimes', "deno:$bin") }
    foreach ($runtime in 'deno', 'node', 'bun') {
        if (Get-Command $runtime -ErrorAction SilentlyContinue) { return @('--js-runtimes', $runtime) }
    }
    return @()
}

# yt-dlp doesn't fail when ffmpeg won't start - it leaves video and audio
# as separate files and marks them done. so actually run ffmpeg to check
function Test-Ffmpeg {
    foreach ($exe in $ffmpeg, $ffprobe) {
        if (-not (Test-Path $exe)) { return $false }
        try { & $exe -version | Out-Null } catch { return $false }
        if ($LASTEXITCODE -ne 0) { return $false }
    }
    return $true
}

function Test-Deno {
    if (-not (Test-Path $deno)) { return $false }
    try { $said = (Invoke-Tool $deno @('--version') 30).Out } catch { return $false }
    if ($said -notmatch 'deno (\d+\.\d+\.\d+)') { return $false }
    return ([version]$Matches[1]) -ge $denoMinimum
}

function Install-Tools {
    $haveYtdlp = Test-Path $ytdlp
    $ffmpegOk  = Test-Ffmpeg
    # replace an outdated deno in bin\, otherwise any js runtime on PATH works
    $needsJs   = -not (Test-Deno) -and ((Test-Path $deno) -or (Get-JsRuntime).Count -eq 0)
    if ($haveYtdlp -and $ffmpegOk -and -not $needsJs) { return }

    if ($haveYtdlp) {
        Write-Host '  Fetching a fresh copy of a tool that is missing or out of date.'
    } else {
        Write-Host '  First run, so it has to fetch its tools. This takes a few minutes.'
        Write-Host '  They go in the bin folder next to this script and stay there.'
    }
    Write-Host ''
    New-Item -ItemType Directory -Force -Path $bin | Out-Null

    if (-not $haveYtdlp) {
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
        if (-not (Test-Deno)) { throw 'deno did not unpack properly. Delete the bin folder and try again.' }
    }

    Write-Host ''
}

# old yt-dlp = broken downloads, so update on every start.
# offline it fails fast and we keep the current one
function Update-Ytdlp {
    Write-Host '  Checking for a yt-dlp update'
    $said = ''
    try { $said = (Invoke-Tool $ytdlp @('-U') 30).Out } catch { }
    # an interrupted update can leave the old exe renamed
    if (-not (Test-Path $ytdlp) -and (Test-Path "$ytdlp.old")) { Move-Item "$ytdlp.old" $ytdlp -Force }
    if ($said -match 'Updated yt-dlp to \D*(\d[\d.]+)') { Write-Host "  Updated yt-dlp to $($Matches[1])" }
    Get-YtdlpVersion
}

function Get-YtdlpVersion {
    try {
        $r = Invoke-Tool $ytdlp @('--version') 30
        if ($r.Code -eq 0) { return $r.Out.Trim() }
    } catch { }
    return ''
}

function Get-SafeName($name) {
    $bad = [Regex]::Escape(-join [IO.Path]::GetInvalidFileNameChars())
    $out = (($name -replace "[$bad]", ' ') -replace '\s+', ' ').Trim().TrimEnd('.')
    if ($out.Length -gt 80) { $out = $out.Substring(0, 80).Trim() }
    if ($out) { $out } else { 'Playlist' }
}

# real Downloads path (can be moved, or on OneDrive)
function Get-Downloads {
    try {
        $found = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
        if ($found -and (Test-Path $found)) { return $found }
    } catch { }
    Join-Path $env:USERPROFILE 'Downloads'
}

# yt-dlp is still writing these, so open shared and keep an offset.
# only complete lines are returned
function Read-NewLines($log, $all) {
    if (-not (Test-Path $log.Path)) { return @() }
    try {
        $stream = [IO.File]::Open($log.Path, 'Open', 'Read', 'ReadWrite')
        try {
            if ($stream.Length -le $log.Offset) { return @() }
            $null  = $stream.Seek($log.Offset, 'Begin')
            $bytes = New-Object byte[] ($stream.Length - $log.Offset)
            $count = $stream.Read($bytes, 0, $bytes.Length)
        } finally { $stream.Close() }
        if ($count -le 0) { return @() }
        $end = if ($all) { $count - 1 } else { [Array]::LastIndexOf($bytes, [byte]10, $count - 1) }
        if ($end -lt 0) { return @() }
        $log.Offset += $end + 1
        return @($utf8.GetString($bytes, 0, $end + 1) -split "`r?`n" | Where-Object { $_ })
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
    Send-Reply $context (ConvertTo-Json $object -Depth 6 -Compress) 'application/json; charset=utf-8'
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

function Test-YouTubeLink($text) {
    $text -match '^https?://([\w-]+\.)?(youtube\.com|youtu\.be)/\S+$'
}

# youtube link already on the clipboard at startup gets used (read once).
# page shows a countdown with cancel in case it's an old link
function Get-StartLink {
    if ($Url) {
        if (Test-YouTubeLink $Url.Trim()) { return @{ Url = $Url.Trim(); FromClipboard = $false } }
        Write-Host '  That link is not a YouTube one, so it was left out.' -ForegroundColor Yellow
    }
    $text = ''
    try { $text = [string](Get-Clipboard -Raw) } catch { }
    $text = $text.Trim()
    if (Test-YouTubeLink $text) { return @{ Url = $text; FromClipboard = $true } }
    return @{ Url = ''; FromClipboard = $false }
}

function Open-Page($port, $link) {
    $address = "http://localhost:$port/"
    if ($link.Url) {
        $address += '?url=' + [Uri]::EscapeDataString($link.Url)
        if ($link.FromClipboard) { $address += '&from=clipboard' }
    }
    Start-Process $address
}

# find an instance that's already running. only try ports that are listening,
# a closed localhost port on windows takes seconds to refuse
function Find-RunningCopy {
    $open = @([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() |
        ForEach-Object { $_.Port })
    foreach ($port in 8730..8760) {
        if ($open -notcontains $port) { continue }
        try {
            $request = [Net.WebRequest]::Create("http://localhost:$port/api/ping")
            $request.Timeout = 10000
            $request.Proxy = $null
            $response = $request.GetResponse()
            $reader = New-Object IO.StreamReader($response.GetResponseStream())
            $said = $reader.ReadToEnd()
            $response.Close()
            if (($said | ConvertFrom-Json).app -eq 'playlist-downloader') { return $port }
        } catch {
            # slow to answer = probably us, busy reading a playlist
            if ($_.Exception.InnerException.Status -eq 'Timeout') { return $port }
        }
    }
    return 0
}

function Get-CommonArgs {
    # force utf-8, otherwise yt-dlp writes in the ANSI code page and drops chars
    # (arabic titles came back empty)
    $list = @(Get-JsRuntime) + @('--encoding', 'utf-8')
    # optional cookies.txt exported from a browser, for age-restricted videos
    if (Test-Path $cookies) { $list += @('--cookies', $cookies) }
    $list
}

# map yt-dlp errors to readable reasons. 'gone' = never retry,
# 'blocked' counts toward showing the Fix button.
# order matters: geo-blocks also say 'unavailable', and 'Sign in to confirm'
# is used for both the bot check and the age check
function Get-Reason($raw) {
    $text = $raw -replace '^ERROR:\s*', '' -replace '^\[[^\]]+\]\s*', '' -replace '^[\w-]{11}:\s*', ''
    if ($text -match 'not a bot|HTTP Error 403|HTTP Error 429') {
        return @{ Kind = 'blocked'; Text = 'YouTube blocked the request.' }
    }
    if ($text -match 'private video') { return @{ Kind = 'gone'; Text = 'This video is private.' } }
    if ($text -match 'members-only|join this channel') {
        return @{ Kind = 'gone'; Text = 'This video is for channel members only.' }
    }
    if ($text -match 'not available in your country|geo.?restrict|geo.?block') {
        return @{ Kind = 'gone'; Text = 'This video is blocked in your country.' }
    }
    if ($text -match 'age.?restrict|confirm your age|inappropriate for some users') {
        return @{ Kind = 'gone'; Text = 'This video is age-restricted. See the README for the optional cookies.txt.' }
    }
    if ($text -match 'ffmpeg') {
        return @{ Kind = 'join'; Text = 'ffmpeg did not run, so picture and sound could not be joined.' }
    }
    if ($text -match 'requested format is not available|no video formats') {
        return @{ Kind = 'blocked'; Text = 'No downloadable format. Updating the downloader engine may help.' }
    }
    if ($text -match 'unavailable|removed|has been deleted|terminated') {
        return @{ Kind = 'gone'; Text = 'This video was removed or is blocked in your country.' }
    }
    if ($text -match 'unable to download|timed out|connection|network is unreachable|getaddrinfo') {
        return @{ Kind = 'network'; Text = 'The connection dropped.' }
    }
    @{ Kind = 'other'; Text = "YouTube said: $text" }
}

function Get-LinkProblem($said) {
    if ($said -match 'playlist does not exist|playlist is private') {
        return 'That playlist is private or does not exist. Only public and unlisted playlists can be downloaded.'
    }
    if ($said -match 'private video') { return 'That video is private.' }
    if ($said -match 'unsupported url|not a valid url') {
        return 'That link is not one yt-dlp can read. Copy it from the address bar of the YouTube page.'
    }
    if ($said -match 'not a bot|HTTP Error 403|HTTP Error 429') { return 'YouTube blocked the request. Wait a minute and try again.' }
    if ($said -match 'getaddrinfo|unable to connect|timed out|connection') {
        return 'Could not reach YouTube. Check the internet connection.'
    }
    'That link did not work. Make sure it is a public YouTube video or playlist.'
}

# quick flat pass: playlist name + index/id/title of each entry.
# json is ascii-escaped so non-latin titles survive
function Get-LinkInfo($link) {
    if ($pd.Infos.ContainsKey($link)) { return $pd.Infos[$link] }
    $list = @(Get-CommonArgs) + @('--flat-playlist', '--ignore-errors', '--no-warnings',
        '--print', '%(.{playlist_index,playlist_title,id,title,ie_key,extractor_key})j')
    if ($link -match '[?&]list=') { $list += '--yes-playlist' }
    $r = Invoke-Tool $ytdlp ($list + @('--', $link)) 180
    $found = @($r.Out -split "`r?`n" | Where-Object { $_.StartsWith('{') } | ForEach-Object { $_ | ConvertFrom-Json })
    if ($found.Count -eq 0) {
        $said = @($r.Err -split "`r?`n" | Where-Object { $_ -match '^ERROR:' }) | Select-Object -Last 1
        throw (Get-LinkProblem "$said")
    }

    $isPlaylist = [bool]$found[0].playlist_title
    $entries = New-Object Collections.ArrayList
    $n = 0
    foreach ($e in $found) {
        $n += 1
        $site = if ($e.ie_key) { $e.ie_key } elseif ($e.extractor_key) { $e.extractor_key } else { 'Youtube' }
        [void]$entries.Add(@{
            Index = if ($e.playlist_index) { [int]$e.playlist_index } else { $n }
            Id    = $e.id
            Title = $e.title
            # same 'site id' format as yt-dlp's archive file
            Key   = "$($site.ToLower()) $($e.id)"
        })
    }
    $info = @{
        Url        = $link
        Title      = if ($isPlaylist) { $found[0].playlist_title } elseif ($found[0].title) { $found[0].title } else { 'Video' }
        IsPlaylist = $isPlaylist
        Entries    = $entries
    }
    $pd.Infos[$link] = $info
    $info
}

# a run = one playlist. items go waiting -> downloading -> joining ->
# done / failed / had (already downloaded earlier)
function New-Run($info, $folder, $format) {
    $pd.Seq += 1
    $run = @{
        Seq = $pd.Seq; Url = $info.Url; Title = $info.Title; IsPlaylist = $info.IsPlaylist
        Folder = $folder; Format = $format; Status = 'queued'; Rev = 0
        Items = New-Object Collections.ArrayList; ById = @{}; ByIndex = @{}; Target = @()
        Current = $null; ItemMax = 0.0; Percent = ''; Speed = ''; Eta = ''
        Orphan = $null; Started = $null; RetryAt = $null; Again = @(); Notice = ''; Split = 0
    }
    foreach ($e in $info.Entries) { Add-Item $run $e.Index $e.Id $e.Title $e.Key | Out-Null }
    $run
}

function Add-Item($run, $index, $id, $title, $key) {
    $item = @{ Index = $index; Id = $id; Title = $title; Key = $key; State = 'waiting'; Kind = ''; Reason = ''; Tries = 0 }
    [void]$run.Items.Add($item)
    if (-not $run.ById.ContainsKey($id)) { $run.ById[$id] = $item }
    $run.ByIndex[$index] = $item
    $item
}

function Find-Item($run, $index, $id, $site) {
    if ($index -match '^\d+$' -and $run.ByIndex.ContainsKey([int]$index)) { return $run.ByIndex[[int]$index] }
    if ($run.ById.ContainsKey($id)) { return $run.ById[$id] }
    # new entry, added after we first read the playlist
    $next = if ($index -match '^\d+$') { [int]$index } else { $run.Items.Count + 1 }
    Add-Item $run $next $id $null "$("$site".ToLower()) $id"
}

function Set-State($run, $item, $state) {
    $item.State = $state
    $run.Rev += 1
}

function Test-Busy($item) {
    $item -and ($item.State -eq 'downloading' -or $item.State -eq 'joining' -or $item.State -eq 'converting')
}

function Set-Failed($run, $item, $reason) {
    $item.State  = 'failed'
    $item.Kind   = $reason.Kind
    $item.Reason = $reason.Text
    if ([object]::ReferenceEquals($run.Current, $item)) { $run.Current = $null }
    $run.Rev += 1
}

# current video stopped without finishing, use the last unclaimed error
function Close-Current($run) {
    $item = $run.Current
    if (Test-Busy $item) {
        $why = $run.Orphan
        if (-not $why) { $why = @{ Kind = 'other'; Text = 'It stopped partway. Retrying usually fixes this.' } }
        Set-Failed $run $item $why
        $run.Orphan = $null
    }
    $run.Current = $null
}

# yt-dlp says done even when the merge failed, so ffprobe every file.
# returns what's wrong, or nothing if it's fine
function Test-MediaFile($file, $format) {
    if (-not (Test-Path -LiteralPath $file)) { return 'The finished file went missing.' }
    $broken = if ($format -eq 'mp3') { 'The MP3 came out damaged.' } else { 'Joining picture and sound failed.' }
    try {
        $r = Invoke-Tool $ffprobe @('-v', 'error', '-show_entries', 'stream=codec_type:format=duration', '-of', 'json', $file) 60
        if ($r.Code -ne 0) { return $broken }
        $probe = $r.Out | ConvertFrom-Json
    } catch { return $broken }
    $kinds = @($probe.streams | ForEach-Object { $_.codec_type })
    if ($kinds -notcontains 'audio') { return $broken }
    if ($format -ne 'mp3') {
        if ($kinds -notcontains 'video') { return $broken }
        $seconds = 0.0
        [void][double]::TryParse([string]$probe.format.duration, [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$seconds)
        if ($seconds -le 0) { return $broken }
    }
}

# separate done list per format so mp3 and mp4 runs don't block each other
function Get-DoneFile($folder, $format) {
    $kind = if ($format -eq 'mp3') { 'mp3' } else { 'mp4' }
    Join-Path $folder "already-downloaded.$kind.txt"
}

function Get-DoneKeys($folder, $format) {
    $keys  = New-Object 'Collections.Generic.HashSet[string]'
    $files = @(Get-DoneFile $folder $format)
    # 1.0 had a single list - still read for video, never written
    if ($format -ne 'mp3') { $files += Join-Path $folder 'already-downloaded.txt' }
    foreach ($file in $files) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        foreach ($line in [IO.File]::ReadAllLines($file)) {
            if ($line.Trim()) { [void]$keys.Add($line.Trim()) }
        }
    }
    , $keys
}

function Remove-DoneKey($folder, $key) {
    foreach ($file in (Get-DoneFile $folder 'mp4'), (Join-Path $folder 'already-downloaded.txt')) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $kept = @([IO.File]::ReadAllLines($file) | Where-Object { $_.Trim() -ne $key })
        [IO.File]::WriteAllLines($file, [string[]]$kept, $utf8)
    }
}

# without ffmpeg yt-dlp also moves the unmerged .f137/.f140 parts here
function Remove-Pieces($file) {
    $base = [IO.Path]::GetFileNameWithoutExtension($file)
    $dir  = Split-Path -Parent $file
    if (-not (Test-Path -LiteralPath $dir)) { return 0 }
    $pieces = @(Get-ChildItem -LiteralPath $dir -File | Where-Object {
        $_.Name.StartsWith("$base.") -and $_.Name.Substring($base.Length) -match "^$splitPattern" })
    $pieces | Remove-Item -Force -ErrorAction SilentlyContinue
    $pieces.Count
}

function Confirm-Item($run, $item, $file) {
    $problem = Test-MediaFile $file $run.Format
    if ($problem) {
        # delete it so it can't pass as finished, the retry downloads it again
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        if (Remove-Pieces $file) { $problem = 'Joining picture and sound failed.' }
        Set-Failed $run $item @{ Kind = 'join'; Text = $problem }
        return
    }
    # that error was actually for the next video
    if ($item.State -eq 'failed') { $run.Orphan = @{ Kind = $item.Kind; Text = $item.Reason } }
    $item.Kind = ''; $item.Reason = ''
    # leftover halves from an old version, not needed anymore
    Remove-Pieces $file | Out-Null
    Set-State $run $item 'done'
    if ([object]::ReferenceEquals($run.Current, $item)) { $run.Current = $null }
    [IO.File]::AppendAllText((Get-DoneFile $run.Folder $run.Format), "$($item.Key)`r`n", $utf8)
}

function Step-Out($run, $line) {
    if ($line.StartsWith('DL|')) {
        $p = $line.Split('|')
        if ($p.Count -lt 4) { return }
        $run.Percent = $p[1].Trim(); $run.Speed = $p[2].Trim(); $run.Eta = $p[3].Trim()
        $value = 0.0
        if ([double]::TryParse(($run.Percent -replace '%', ''), [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$value) -and $value -gt $run.ItemMax) {
            $run.ItemMax = $value
        }
        return
    }
    # max 5 parts, titles can contain |
    $p = $line.Split([string[]]@('|'), 5, [StringSplitOptions]::None)
    if ($p.Count -lt 5) { return }
    $item = Find-Item $run $p[1] $p[2] $p[3]
    if ($p[0] -eq 'NOW') {
        if (-not [object]::ReferenceEquals($run.Current, $item)) { Close-Current $run }
        if ($p[4] -and $p[4] -ne 'NA') { $item.Title = $p[4] }
        Set-State $run $item 'downloading'
        $run.Current = $item
        $run.ItemMax = 0.0; $run.Percent = ''; $run.Speed = ''; $run.Eta = ''
    } elseif ($p[0] -eq 'DONE') {
        Confirm-Item $run $item $p[4]
    }
}

function Step-Err($run, $line) {
    if ($line.StartsWith('PP|')) {
        $p = $line.Split('|')
        if ($p.Count -lt 4 -or $p[2] -ne 'started') { return }
        $state = switch ($p[1]) { 'Merger' { 'joining' } 'ExtractAudio' { 'converting' } default { '' } }
        $item = $run.ById[$p[3]]
        if ($state -and (Test-Busy $item)) { Set-State $run $item $state }
        return
    }
    if ($line -notmatch '^ERROR:') { return }
    $reason = Get-Reason $line
    if ($line -match '^ERROR: \[[^\]]+\] ([\w-]+):' -and $run.ById.ContainsKey($Matches[1])) {
        $item = $run.ById[$Matches[1]]
        if ($item.State -ne 'done') { Set-Failed $run $item $reason }
    } elseif (Test-Busy $run.Current) {
        Set-Failed $run $run.Current $reason
    } else {
        # probably a video that just started and whose line we haven't seen yet,
        # it gets claimed when it stops
        $run.Orphan = $reason
    }
}

# read stderr first: an error with no video id belongs to the current one,
# and reading stdout first could move past it
function Read-Progress($run, $all) {
    foreach ($line in @(Read-NewLines $pd.Err $all)) { Step-Err $run $line }
    foreach ($line in @(Read-NewLines $pd.Out $all)) { Step-Out $run $line }
}

function Remove-EmptyFiles($folders) {
    foreach ($folder in $folders) {
        if (-not (Test-Path -LiteralPath $folder)) { continue }
        Get-ChildItem -LiteralPath $folder -File -Force |
            Where-Object { $_.Length -eq 0 -and $_.Extension -match '^\.(mp4|m4a|webm|mkv|mp3|part)$' } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Get-SpaceNotice($folder) {
    try {
        $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($folder))
        if ($drive.AvailableFreeSpace -lt 2GB) {
            return ('Only {0:N1} GB is free on {1}. Downloads will fail once it fills up.' -f
                ($drive.AvailableFreeSpace / 1GB), $drive.Name)
        }
    } catch { }
    ''
}

# pre-1.1 could leave split files when ffmpeg failed:
#   001 - Title.f137.mp4 + 001 - Title.f140.m4a (also f140-1, f251-drc)
# needs .f + 2 digits so names like my.favourite.mp4 don't match
$splitPattern = '\.f\d{2,}(-\w+)?\.(mp4|m4a|webm)$'

function Get-SplitGroups($folder) {
    if (-not (Test-Path -LiteralPath $folder)) { return @() }
    @(Get-ChildItem -LiteralPath $folder -File | Where-Object { $_.Name -match $splitPattern } |
        Group-Object { $_.Name -replace $splitPattern, '' })
}

# merge split pairs into one mp4, verify, then delete the parts.
# if the merge fails drop it from the done list so it gets downloaded again
function Repair-Folder($run) {
    $joined = 0; $failed = 0
    $work = Join-Path $run.Folder '.incomplete'
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    foreach ($group in Get-SplitGroups $run.Folder) {
        $pieces = @($group.Group)
        $target = Join-Path $run.Folder ($group.Name + '.mp4')
        $whole  = (Test-Path -LiteralPath $target) -and -not (Test-MediaFile $target 'mp4')
        if (-not $whole -and $pieces.Count -eq 2) {
            $temp = Join-Path $work ($group.Name + '.joined.mp4')
            $r = Invoke-Tool $ffmpeg @('-v', 'error', '-y', '-i', $pieces[0].FullName, '-i', $pieces[1].FullName,
                '-map', '0', '-map', '1', '-c', 'copy', $temp) 600
            if ($r.Code -eq 0 -and -not (Test-MediaFile $temp 'mp4')) {
                if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
                [IO.File]::Move($temp, $target)
                $whole = $true
            } else {
                Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
            }
        }
        if ($whole) {
            $pieces | Remove-Item -Force
            $joined += 1
            continue
        }
        $failed += 1
        if ($group.Name -match '^(\d+) - ' -and $run.ByIndex.ContainsKey([int]$Matches[1])) {
            $item = $run.ByIndex[[int]$Matches[1]]
            Remove-DoneKey $run.Folder $item.Key
            Set-Failed $run $item @{ Kind = 'join'; Text = 'An older version saved this in two halves. Retry downloads it whole.' }
        }
    }
    if (-not (Get-ChildItem -LiteralPath $work -Force)) { Remove-Item -LiteralPath $work -Force -ErrorAction SilentlyContinue }
    $run.Split = @(Get-SplitGroups $run.Folder).Count
    $run.Rev += 1
    @{ joined = $joined; failed = $failed }
}

# start yt-dlp for a run (whole playlist, or just the given items on retry)
function Start-Pass($run, $only) {
    $pd.Active = $run
    $folder = $run.Folder
    $unfinished = Join-Path $folder '.incomplete'
    try {
        New-Item -ItemType Directory -Force -Path $folder | Out-Null
        # download + merge in a hidden temp folder, only the final file gets moved
        # out. partial downloads stay in there and resume next time
        $dir = New-Item -ItemType Directory -Force -Path $unfinished
        try { $dir.Attributes = $dir.Attributes -bor [IO.FileAttributes]::Hidden } catch { }
    } catch {
        $run.Notice = "Could not use that folder: $($_.Exception.Message)"
        Complete-Run $run 'stopped'
        return
    }
    Remove-EmptyFiles @($folder, $unfinished)
    $run.Notice = Get-SpaceNotice $folder
    $run.Split  = @(Get-SplitGroups $folder).Count

    # yt-dlp gets a throwaway copy of the done list. we only add to the
    # real one after checking the file
    $keys = Get-DoneKeys $folder $run.Format
    [IO.File]::WriteAllLines($archive, [string[]]@($keys), $utf8)
    if ($only) {
        $targets = @($only)
    } else {
        foreach ($item in $run.Items) {
            if ($item.State -eq 'waiting' -and $keys.Contains($item.Key)) { $item.State = 'had' }
        }
        $targets = @($run.Items | Where-Object { $_.State -eq 'waiting' })
    }
    $run.Rev += 1
    if ($targets.Count -eq 0) { Complete-Run $run 'finished'; return }
    foreach ($item in $targets) {
        $item.Tries += 1
        $item.State = 'waiting'; $item.Kind = ''; $item.Reason = ''
    }
    $run.Target = $targets

    switch ($run.Format) {
        'mp3' {
            $format = @('-f', 'bestaudio/best',
                        '--extract-audio', '--audio-format', 'mp3', '--audio-quality', '0',
                        '--embed-thumbnail', '--embed-metadata')
        }
        # -S (sort) instead of -f so there's always a fallback.
        # prefer h264+aac, plays everywhere. av1 (yt-dlp's default pick) needs a
        # store extension on win10. youtube only has h264 up to 1080p
        'max' {
            $format = @('-S', 'res,vcodec:h264,acodec:m4a', '--merge-output-format', 'mp4',
                        '--embed-metadata', '--embed-chapters')
        }
        default {
            $format = @('-S', 'vcodec:h264,res:1080,acodec:m4a', '--merge-output-format', 'mp4',
                        '--embed-metadata', '--embed-chapters')
        }
    }

    if ($run.Items.Count -gt 1) { $template = '%(playlist_index)03d - %(title)s.%(ext)s' }
    else                        { $template = '%(title)s.%(ext)s' }

    $options = @(
        '--paths', $folder,
        '--paths', "temp:$unfinished",
        '-o', $template,
        '--ffmpeg-location', $bin,
        '--download-archive', $archive,
        '--concurrent-fragments', '4',
        '--retries', '10',
        '--fragment-retries', '10',
        # exponential backoff, max 20s
        '--retry-sleep', 'exp=1:20',
        '--retry-sleep', 'fragment:exp=1:20',
        '--ignore-errors',
        '--no-mtime',
        '--windows-filenames',
        '--newline',
        '--progress',
        '--progress-delta', '1',
        '--progress-template', 'download:DL|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s',
        '--progress-template', 'postprocess:PP|%(progress.postprocessor)s|%(progress.status)s|%(info.id)s',
        # title on its own line: the progress template ignores --encoding
        '--print', 'before_dl:NOW|%(playlist_index)s|%(id)s|%(extractor_key)s|%(title)s',
        '--print', 'after_move:DONE|%(playlist_index)s|%(id)s|%(extractor_key)s|%(filepath)s'
    )
    # watch?v=..&list=.. links: get the whole playlist, not just that video
    if ($run.Url -match '[?&]list=') { $options += '--yes-playlist' }
    if ($only -and $run.IsPlaylist) {
        $options += @('--playlist-items', (($targets | ForEach-Object { $_.Index }) -join ','))
    }

    Remove-Item $outLog, $errLog -Force -ErrorAction SilentlyContinue
    $pd.Out.Offset = 0
    $pd.Err.Offset = 0
    $run.Current = $null
    $run.Orphan  = $null
    $pd.Job = Start-Process -FilePath $ytdlp `
        -ArgumentList (Format-CommandLine (@(Get-CommonArgs) + $options + $format + @('--', $run.Url))) `
        -NoNewWindow -PassThru `
        -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    # touch Handle or ExitCode comes back null after exit (.NET quirk)
    $null = $pd.Job.Handle
    if (-not $run.Started) { $run.Started = Get-Date }
    $run.Status = 'running'
    $what = if ($only) { 'Retrying' } else { 'Downloading' }
    Write-Host "  $what $($targets.Count) from: $($run.Title)"
}

function Complete-Pass($run) {
    if ($run.Status -eq 'stopping') {
        # partial files stay for next time
        if ($run.Current) { Set-State $run $run.Current 'waiting' }
        Complete-Run $run 'stopped'
        return
    }
    Close-Current $run
    foreach ($item in $run.Target) {
        if ($item.State -ne 'waiting') { continue }
        $why = $run.Orphan
        if (-not $why) { $why = @{ Kind = 'other'; Text = 'yt-dlp passed over this one without saying why.' } }
        Set-Failed $run $item $why
    }
    $run.Orphan = $null

    # one more retry after a pause (skip private/removed)
    $again = @($run.Target | Where-Object { $_.State -eq 'failed' -and $_.Kind -ne 'gone' -and $_.Tries -lt 2 })
    if ($again.Count) {
        $run.Status  = 'waiting'
        $run.Again   = $again
        $run.RetryAt = (Get-Date).AddSeconds(15)
        $run.Rev += 1
        Write-Host "  $($again.Count) did not come through. Trying those again in 15 seconds."
        return
    }
    Complete-Run $run 'finished'
}

function Complete-Run($run, $status) {
    $run.Status  = $status
    $run.Current = $null
    $run.Rev += 1
    $pd.Active = $null
    Remove-Item $archive -Force -ErrorAction SilentlyContinue
    $unfinished = Join-Path $run.Folder '.incomplete'
    if ((Test-Path -LiteralPath $unfinished) -and -not (Get-ChildItem -LiteralPath $unfinished -Force)) {
        Remove-Item -LiteralPath $unfinished -Force -ErrorAction SilentlyContinue
    }

    $done   = @($run.Items | Where-Object { $_.State -eq 'done' }).Count
    $failed = @($run.Items | Where-Object { $_.State -eq 'failed' }).Count
    if ($status -eq 'stopped') { $summary = 'Stopped.' }
    elseif ($failed)           { $summary = "$done saved, $failed could not be downloaded." }
    elseif ($done)             { $summary = "All $done saved." }
    else                       { $summary = 'Nothing new to download.' }
    Write-Host "  $summary $($run.Folder)"
    if ($status -eq 'finished') { Show-Finished $run.Title $summary }
}

# windows notification when a playlist is done (the tray balloon shows as a toast on 10/11)
function Show-Finished($title, $text) {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        if (-not $pd.Tray) {
            $pd.Tray = New-Object Windows.Forms.NotifyIcon
            $pd.Tray.Icon = [Drawing.SystemIcons]::Information
            $pd.Tray.Text = 'Playlist Downloader'
        }
        if ($title.Length -gt 60) { $title = $title.Substring(0, 60) }
        $pd.Tray.Visible = $true
        $pd.Tray.ShowBalloonTip(10000, $title, $text, [Windows.Forms.ToolTipIcon]::Info)
        $pd.TrayUntil = (Get-Date).AddSeconds(30)
    } catch { }
}

# runs every 500ms even with the page closed: read logs, check files, start next
function Update-Engine {
    $run = $pd.Active
    if ($run) {
        if ($pd.Job) {
            $ended = $pd.Job.HasExited
            Read-Progress $run $ended
            if ($ended) {
                $pd.Job = $null
                Complete-Pass $run
            }
        } elseif ($run.Status -eq 'waiting' -and (Get-Date) -ge $run.RetryAt) {
            Start-Pass $run $run.Again
        }
    }
    while (-not $pd.Active -and $pd.Queue.Count) {
        $next = $pd.Queue[0]
        $pd.Queue.RemoveAt(0)
        Start-Pass $next.Run $next.Only
    }
    if ($pd.Tray -and $pd.Tray.Visible -and (Get-Date) -gt $pd.TrayUntil) { $pd.Tray.Visible = $false }
}

# retry failed videos (and unstarted ones after a Stop)
function Request-Retry($run) {
    $only = @($run.Items | Where-Object { $_.State -eq 'failed' -or $_.State -eq 'waiting' })
    if ($only.Count -eq 0) { return }
    foreach ($item in $only) { $item.Tries = 0 }
    $run.Status = 'queued'
    $run.Rev += 1
    [void]$pd.Queue.Add(@{ Run = $run; Only = $only })
}

function Stop-All {
    foreach ($pass in $pd.Queue) { $pass.Run.Status = 'stopped'; $pass.Run.Rev += 1 }
    $pd.Queue.Clear()
    $run = $pd.Active
    if (-not $run) { return }
    if ($pd.Job -and -not $pd.Job.HasExited) {
        $run.Status = 'stopping'
        # /T kills ffmpeg too if it's mid-merge
        & taskkill.exe /PID $pd.Job.Id /T /F | Out-Null
    } elseif (-not $pd.Job) {
        Complete-Run $run 'stopped'
    }
}

function Get-RunView($run, $withItems) {
    # plain loop on purpose, pipelines are slow in 5.1 and this runs every poll
    $done = 0; $failed = 0; $had = 0; $blocked = 0
    $failures = New-Object Collections.ArrayList
    foreach ($item in $run.Items) {
        switch ($item.State) {
            'done'   { $done += 1 }
            'had'    { $had += 1 }
            'failed' {
                $failed += 1
                if ($item.Kind -eq 'blocked') { $blocked += 1 }
                [void]$failures.Add(@{ index = $item.Index; title = $item.Title; reason = $item.Reason })
            }
        }
    }
    $total = $run.Items.Count
    $fraction = 0.0
    $current = $null
    if ($run.Current) {
        $fraction = [Math]::Min(1.0, $run.ItemMax / 100)
        $current = @{
            index = $run.Current.Index; title = $run.Current.Title; state = $run.Current.State
            percent = $run.Percent; speed = $run.Speed; eta = $run.Eta
        }
    }
    $finished = $done + $failed + $had
    # eta from the average time per video (skip already-downloaded ones)
    $eta = $null
    if ($run.Status -eq 'running' -and $run.Started -and ($done + $failed) -gt 0) {
        $each = ((Get-Date) - $run.Started).TotalSeconds / ($done + $failed + $fraction)
        $eta  = [int]($each * [Math]::Max(0, $total - $finished - $fraction))
    }
    $view = @{
        seq = $run.Seq; title = $run.Title; folder = $run.Folder; format = $run.Format
        status = $run.Status; rev = $run.Rev; count = $total
        done = $done; failed = $failed; had = $had
        position = [Math]::Min($total, $finished + 1)
        percent = if ($total) { [Math]::Round(100 * ($finished + $fraction) / $total, 1) } else { 0 }
        eta = $eta; current = $current; notice = $run.Notice; split = $run.Split
        retryIn = if ($run.Status -eq 'waiting') { [Math]::Max(0, [int]($run.RetryAt - (Get-Date)).TotalSeconds) } else { 0 }
        # lots of blocked videos usually means yt-dlp needs the nightly fix
        suggestFix = ($run.Status -eq 'finished' -or $run.Status -eq 'stopped') -and
                     $blocked -gt 0 -and $blocked -ge [Math]::Min(3, $total - $had)
        failures = $failures.ToArray()
    }
    if ($withItems) {
        $view.items = @($run.Items | ForEach-Object { @{ i = $_.Index; t = $_.Title; s = $_.State } })
    }
    $view
}

function Find-Run($seq) {
    foreach ($run in $pd.Runs) { if ($run.Seq -eq [int]$seq) { return $run } }
    throw 'That download is no longer listed. Reload the page.'
}

$pd = @{
    Runs   = New-Object Collections.ArrayList
    Queue  = New-Object Collections.ArrayList
    Active = $null
    Job    = $null
    Out    = @{ Path = $outLog; Offset = 0 }
    Err    = @{ Path = $errLog; Offset = 0 }
    Infos  = @{}
    Seq    = 0
    Version   = ''
    Tray      = $null
    TrayUntil = [DateTime]::MinValue
}

try {
    Write-Host ''
    Write-Host '  Playlist Downloader'
    Write-Host ''

    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

    $pdLink = Get-StartLink

    # already running? hand the link to that instance instead
    $pdRunning = Find-RunningCopy
    if ($pdRunning) {
        Open-Page $pdRunning $pdLink
        Write-Host '  It is already running, so this went to that window instead.'
        Start-Sleep -Seconds 3
        return
    }

    Install-Tools
    $pd.Version = Update-Ytdlp

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
    if ($port -ne 8730) { Write-Host '  Another program is using port 8730, so the page is on a different one.' -ForegroundColor Yellow }

    $address = "http://localhost:$port/"
    if ($pd.Version) { Write-Host "  yt-dlp $($pd.Version)" }
    Write-Host "  Open in your browser:  $address"
    Write-Host '  Closing this window stops the downloader.'
    Write-Host ''
    Open-Page $port $pdLink

    $pdNext = $listener.BeginGetContext($null, $null)
    while ($listener.IsListening) {
        # wake up every 500ms even without requests so downloads keep going
        if (-not $pdNext.AsyncWaitHandle.WaitOne(500)) {
            try { Update-Engine } catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Yellow }
            continue
        }
        $context = $listener.EndGetContext($pdNext)
        $pdNext  = $listener.BeginGetContext($null, $null)
        $path    = $context.Request.Url.AbsolutePath

        # require our custom header on POSTs. other sites can't set it (csrf)
        if ($context.Request.HttpMethod -eq 'POST' -and -not $context.Request.Headers['X-Playlist-Downloader']) {
            $context.Response.StatusCode = 403
            Send-Reply $context 'Forbidden' 'text/plain'
            continue
        }

        try {
            switch ($path) {

                '/' {
                    # needs -Encoding UTF8 or 5.1 reads it as ANSI
                    Send-Reply $context (Get-Content $page -Raw -Encoding UTF8) 'text/html; charset=utf-8'
                }

                '/api/ping' {
                    Send-Json $context @{ app = 'playlist-downloader'; version = $appVersion; ytdlp = $pd.Version }
                }

                '/api/info' {
                    $pdUrl = ([string](Get-Body $context).url).Trim()
                    if ($pdUrl -notmatch '^https?://\S+$') { Send-Error $context 'That is not a link. Copy it from the address bar and paste it here.'; break }
                    $pdInfo = Get-LinkInfo $pdUrl
                    Send-Json $context @{ title = $pdInfo.Title; count = $pdInfo.Entries.Count; isPlaylist = $pdInfo.IsPlaylist }
                }

                '/api/start' {
                    $pdBody = Get-Body $context
                    $pdUrl  = ([string]$pdBody.url).Trim()
                    if ($pdUrl -notmatch '^https?://\S+$') { Send-Error $context 'That is not a link. Copy it from the address bar and paste it here.'; break }
                    $pdInfo = Get-LinkInfo $pdUrl
                    # old 1.0 format names -> new default
                    $pdFormat = switch ([string]$pdBody.format) { 'mp3' { 'mp3' } 'max' { 'max' } default { 'mp4' } }
                    $pdFolder = [string]$pdBody.folder
                    if (-not $pdFolder.Trim()) { $pdFolder = Join-Path (Get-Downloads) (Get-SafeName $pdInfo.Title) }
                    New-Item -ItemType Directory -Force -Path $pdFolder | Out-Null
                    $pdFolder = (Resolve-Path -LiteralPath $pdFolder).Path
                    $pdRun = New-Run $pdInfo $pdFolder $pdFormat
                    [void]$pd.Runs.Add($pdRun)
                    [void]$pd.Queue.Add(@{ Run = $pdRun; Only = $null })
                    $pdQueued = [bool]$pd.Active
                    Update-Engine
                    Send-Json $context @{ seq = $pdRun.Seq; title = $pdRun.Title; count = $pdRun.Items.Count; folder = $pdFolder; queued = $pdQueued }
                }

                '/api/progress' {
                    Update-Engine
                    $pdSeq = [int]$context.Request.QueryString['seq']
                    $pdRev = [int]$context.Request.QueryString['rev']
                    $pdFocus = if ($pd.Active) { $pd.Active } elseif ($pd.Runs.Count) { $pd.Runs[$pd.Runs.Count - 1] } else { $null }
                    $pdViews = @()
                    # newest first, only the last few
                    for ($pdI = $pd.Runs.Count - 1; $pdI -ge [Math]::Max(0, $pd.Runs.Count - 10); $pdI--) {
                        $pdR = $pd.Runs[$pdI]
                        # only send the full list when it changed
                        $pdWith = [object]::ReferenceEquals($pdR, $pdFocus) -and ($pdR.Seq -ne $pdSeq -or $pdR.Rev -ne $pdRev)
                        $pdViews += , (Get-RunView $pdR $pdWith)
                    }
                    Send-Json $context @{
                        app    = $appVersion
                        ytdlp  = $pd.Version
                        active = if ($pd.Active) { $pd.Active.Seq } else { 0 }
                        focus  = if ($pdFocus) { $pdFocus.Seq } else { 0 }
                        queue  = @($pd.Queue | ForEach-Object { $_.Run.Title })
                        runs   = $pdViews
                    }
                }

                '/api/stop' {
                    Stop-All
                    Update-Engine
                    Send-Json $context @{ ok = $true }
                }

                '/api/retry' {
                    $pdRun = Find-Run (Get-Body $context).seq
                    if ($pdRun.Status -ne 'finished' -and $pdRun.Status -ne 'stopped') { Send-Error $context 'That one is still going.'; break }
                    Request-Retry $pdRun
                    Update-Engine
                    Send-Json $context @{ ok = $true }
                }

                '/api/fix' {
                    $pdRun = Find-Run (Get-Body $context).seq
                    if ($pd.Active) { Send-Error $context 'Wait for the current download to finish, then try this.'; break }
                    # only when asked. nightly gets youtube fixes before stable
                    Write-Host '  Switching yt-dlp to its nightly build'
                    $pdSaid = Invoke-Tool $ytdlp @('--update-to', 'nightly') 180
                    if (-not (Test-Path $ytdlp) -and (Test-Path "$ytdlp.old")) { Move-Item "$ytdlp.old" $ytdlp -Force }
                    $pd.Version = Get-YtdlpVersion
                    Write-Host "  yt-dlp $($pd.Version)"
                    if ($pdSaid.Code -ne 0 -and -not $pd.Version) { Send-Error $context 'The update did not work. Check the internet connection.'; break }
                    Request-Retry $pdRun
                    Update-Engine
                    Send-Json $context @{ ok = $true; ytdlp = $pd.Version }
                }

                '/api/repair' {
                    $pdRun = Find-Run (Get-Body $context).seq
                    if ([object]::ReferenceEquals($pd.Active, $pdRun)) { Send-Error $context 'Wait for this playlist to finish, then repair it.'; break }
                    Send-Json $context (Repair-Folder $pdRun)
                }

                '/api/open' {
                    $pdTarget = (Get-Body $context).folder
                    if (Test-Path -LiteralPath $pdTarget) { Start-Process explorer.exe $pdTarget }
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
finally {
    if ($pd.Tray) { $pd.Tray.Dispose() }
}

# launcher only accepts a downloaded copy ending with this line, keep it last
# PLAYLIST-DOWNLOADER-ENGINE
