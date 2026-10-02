<#
    TalkHammer Companion

    Passes messages between the TalkHammer mod and the Player2 app.

    The game's Lua can't make web requests, but it can read and write files.
    The mod writes each request into <game>\talkhammer_data\ and this script
    sends it on to Player2 and writes the answer back:

        <id>.req.json    request body (written by the game)
        <id>.job         "POST <url>" - written last, so it's never half-done
        <id>.resp.json   the answer (written via <id>.tmp, then renamed)

    It only talks to Player2 on this computer (127.0.0.1).

    Usage:  TalkHammerCompanion.bat
            TalkHammerCompanion.bat -GameRoot "D:\...\Total War WARHAMMER III"
            -Once    handle whatever is queued, then exit (for testing)
#>
param(
    [string]$GameRoot = "",
    [string]$Player2 = "http://127.0.0.1:4315",
    [string]$GameKey = "talkhammer",
    [int]$TimeoutSeconds = 180,
    [switch]$Once
)

$ErrorActionPreference = "Stop"
$Version = "1"      # protocol version, reported in companion.beat

# Keep console output plain ASCII so it looks right on any code page.
try { $Host.UI.RawUI.WindowTitle = "TalkHammer Companion - keep open while playing, close to stop" } catch {}

function Say($text, $colour = "Gray") { Write-Host $text -ForegroundColor $colour }
function Stamp { Get-Date -Format "HH:mm" }
function Ok($text) { Say ("  [ OK ] " + $text) Green }
function Warn($text) { Say ("  [ !! ] " + $text) Yellow }
function Wait($text) { Say ("  [ .. ] " + $text) Gray }

# Look for the game in every Steam library.
function Find-GameRoot {
    $candidates = @()
    foreach ($reg in @("HKCU:\Software\Valve\Steam", "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam")) {
        try {
            $p = (Get-ItemProperty -Path $reg -ErrorAction Stop)
            if ($p.SteamPath) { $candidates += $p.SteamPath }
            if ($p.InstallPath) { $candidates += $p.InstallPath }
        }
        catch {}
    }
    $libraries = @()
    foreach ($steam in $candidates) {
        $libraries += $steam
        $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $libraries += ($m.Groups[1].Value -replace '\\\\', '\')
            }
        }
    }
    foreach ($lib in ($libraries | Select-Object -Unique)) {
        $game = Join-Path $lib "steamapps\common\Total War WARHAMMER III"
        if (Test-Path (Join-Path $game "Warhammer3.exe")) { return $game }
    }
    return $null
}

if (-not $GameRoot) { $GameRoot = Find-GameRoot }
if (-not $GameRoot -or -not (Test-Path $GameRoot)) {
    Say ""
    Say "  Could not find Total War: WARHAMMER III on this computer." Red
    Say ""
    Say "  The companion looks for it through Steam. If your game is somewhere"
    Say "  unusual, start the companion with the folder added, for example:"
    Say ""
    Say '    TalkHammerCompanion.bat -GameRoot "D:\Games\Total War WARHAMMER III"'
    Say ""
    Say "  (The right folder is the one that contains Warhammer3.exe.)"
    if (-not $Once) { Say ""; Read-Host "  Press Enter to close" }
    exit 1
}
$Data = Join-Path $GameRoot "talkhammer_data"
if (-not (Test-Path $Data)) { New-Item -ItemType Directory -Path $Data | Out-Null }

Add-Type -AssemblyName System.Net.Http
$http = New-Object System.Net.Http.HttpClient
$http.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
$http.DefaultRequestHeaders.Add("player2-game-key", $GameKey)


$healthHttp = New-Object System.Net.Http.HttpClient
$healthHttp.Timeout = [TimeSpan]::FromSeconds(5)

$inflight = @{}      # id -> @{ task; started; tmp; out; kind }
$beat = 0
$player2Ok = $false
$lastHealth = [DateTime]::MinValue
$served = 0


function Move-Safe($from, $to) {
    for ($i = 0; $i -lt 20; $i++) {
        try { Move-Item -Force $from $to; return $true } catch { Start-Sleep -Milliseconds 25 }
    }
    return $false
}


function Write-Beat {
    $script:beat++
    $state = if ($script:player2Ok) { "ok" } else { "player2-down" }
    $text = "companion $Version beat $($script:beat) $state"
    $tmp = Join-Path $Data "companion.beat.tmp"
    try { [IO.File]::WriteAllText($tmp, $text) } catch { return }
    if (-not (Move-Safe $tmp (Join-Path $Data "companion.beat"))) { $script:beat-- }
}

function Test-Player2 {
    try {
        $r = $healthHttp.GetAsync("$Player2/v1/health").Result
        $script:player2Ok = $r.IsSuccessStatusCode
    }
    catch { $script:player2Ok = $false }
    $script:lastHealth = Get-Date
}

function Describe($url) {
    if ($url -match "/chat/completions") { return "Ruler" }
    if ($url -match "/tts/") { return "Voice" }
    if ($url -match "/health") { return "" }
    return "Request"
}

# Remove message files older than a day (failed or abandoned requests).
function Clear-Old {
    $cutoff = (Get-Date).AddHours(-24)
    $n = 0
    foreach ($f in Get-ChildItem -Path $Data -File -ErrorAction SilentlyContinue) {
        $isMessage = $f.Name -match '\.(req\.json|resp\.json|tmp|job)$' -or $f.Name -match '^\d+_r\d+\.bat$'
        if ($isMessage -and $f.LastWriteTime -lt $cutoff) {
            try { Remove-Item -Force $f.FullName; $n++ } catch {}
        }
    }
    if ($n -gt 0) { Say ("  " + (Stamp) + "  Tidied up $n old message file(s).") DarkGray }
}

$gameSeen = $false
$gameRunning = $false

function Start-Job-File($jobPath) {
    $id = [IO.Path]::GetFileNameWithoutExtension($jobPath)
    $spec = ""
    try { $spec = ([IO.File]::ReadAllText($jobPath)).Trim() } catch { return }
    if ($spec -notmatch '^(GET|POST)\s') { return }
    try { Remove-Item -Force $jobPath } catch { return }
    $parts = $spec -split "\s+", 2
    $method = $parts[0].ToUpper()
    $url = if ($parts.Count -gt 1) { $parts[1] } else { "" }
    if (-not $url.StartsWith("http")) { $url = "$Player2/v1$url" }
    $req = Join-Path $Data "$id.req.json"
    $tmp = Join-Path $Data "$id.tmp"
    $out = Join-Path $Data "$id.resp.json"
    try {
        if ($method -eq "POST") {
            $body = [IO.File]::ReadAllText($req, [Text.Encoding]::UTF8)
            $content = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, "application/json")
            $task = $http.PostAsync($url, $content)
        }
        else {
            $task = $http.GetAsync($url)
        }
        $kind = Describe $url
        $script:inflight[$id] = @{ task = $task; started = Get-Date; tmp = $tmp; out = $out; kind = $kind }
        if (-not $script:gameSeen) {
            $script:gameSeen = $true
            Ok "The game is connected. Rulers can speak."
            Say ""
        }
        if ($kind -eq "Ruler") { Say ("  " + (Stamp) + "  A ruler is thinking...") DarkGray }
    }
    catch {
        [IO.File]::WriteAllText($tmp, "")
        [void](Move-Safe $tmp $out)
        Say ("  " + (Stamp) + "  A message could not be sent: " + $_.Exception.Message) Yellow
    }
}

function Finish-Jobs {
    foreach ($id in @($script:inflight.Keys)) {
        $j = $script:inflight[$id]
        if (-not $j.task.IsCompleted) { continue }
        $text = ""
        $note = ""
        try {
            $resp = $j.task.Result
            $text = $resp.Content.ReadAsStringAsync().Result
            $note = "$([int]$resp.StatusCode)"
        }
        catch {
            $note = "failed: " + $_.Exception.InnerException.Message
            $script:player2Ok = $false
        }
        # UTF-8 without a BOM - the mod doesn't expect one.
        [IO.File]::WriteAllText($j.tmp, $text, (New-Object System.Text.UTF8Encoding $false))
        # If the file is still locked, try again on the next pass.
        if (-not (Move-Safe $j.tmp $j.out)) { continue }
        $secs = ((Get-Date) - $j.started).TotalSeconds
        $script:served++
        $ok = $note -match "^2"
        if (-not $ok) {
            Say ("  " + (Stamp) + "  Player2 did not answer (" + $note + "). Is the Player2 app open and signed in?") Yellow
        }
        elseif ($j.kind -eq "Ruler") {
            Say ("  " + (Stamp) + ("  A ruler replied ({0:N1} s)" -f $secs)) Green
        }
        elseif ($j.kind -eq "Voice") {
            Say ("  " + (Stamp) + "  Voice line spoken") DarkGray
        }
        elseif ($j.kind -ne "") {
            Say ("  " + (Stamp) + "  Request done") DarkGray
        }
        $script:inflight.Remove($id)
    }
}

Say ""
Say "  ==========================================================" Cyan
Say "    TalkHammer Companion" Cyan
Say "  ==========================================================" Cyan
Say "    This window lets the rulers in your game speak, through"
Say "    the Player2 app on this computer. Nothing leaves your PC"
Say "    except to Player2."
Say ""
Say "    Keep it open while you play. Close it any time to stop." White
Say "  ==========================================================" Cyan
Say ""
Ok ("Found the game: " + $GameRoot)
Test-Player2
if ($player2Ok) { Ok "Player2 is running." }
else { Warn "Player2 is not running. Open the Player2 app and sign in - TalkHammer connects as soon as it is up." }
Wait "Waiting for the game - start Total War: WARHAMMER III and load a campaign."
Say ""

Clear-Old
$lastTidy = Get-Date
$lastBeat = [DateTime]::MinValue
while ($true) {
    if (((Get-Date) - $lastTidy).TotalHours -ge 1) { Clear-Old; $lastTidy = Get-Date }
    foreach ($job in Get-ChildItem -Path $Data -Filter "*.job" -File -ErrorAction SilentlyContinue) {
        Start-Job-File $job.FullName
    }
    Finish-Jobs
    $now = Get-Date
    if (($now - $lastBeat).TotalSeconds -ge 1) { Write-Beat; $lastBeat = $now }
    if (($now - $lastHealth).TotalSeconds -ge 30) {
        $was = $player2Ok
        Test-Player2
        if ($was -ne $player2Ok) {
            if ($player2Ok) { Ok "Player2 is running again." }
            else { Warn "Player2 stopped answering. Is the Player2 app still open?" }
        }
        $running = [bool](Get-Process -Name "Warhammer3" -ErrorAction SilentlyContinue)
        if ($gameRunning -and -not $running) {
            Say ""
            Wait "The game was closed. You can close this window now (or leave it open for next time)."
            $gameSeen = $false
        }
        $gameRunning = $running
    }
    if ($Once -and $inflight.Count -eq 0 -and -not (Get-ChildItem -Path $Data -Filter "*.job" -File -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 100
}
Say "served $served request(s)"
