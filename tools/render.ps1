param(
    [string]$Config = 'config/demo_2d.json',
    [string]$Name = 'demo_2d',
    [ValidateRange(1,36000)][int]$Frames = 240,
    [ValidateRange(15,120)][int]$Fps = 30,
    [string]$FFmpeg = ''
)
. "$PSScriptRoot\common.ps1"
if ($Name -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Name must contain letters, digits, _ or -.' }
if (-not [IO.Path]::IsPathRooted($Config)) { $Config = Join-Path $LabRoot $Config }
if ($FFmpeg -eq '') { $FFmpeg = Join-Path $LabRoot '.runtime\ffmpeg.exe' }
if (-not (Test-Path -LiteralPath $FFmpeg)) { throw 'FFmpeg missing; supply -FFmpeg or see README.' }
$destination = Join-Path $LabRoot "outputs\$Name"
if (Test-Path -LiteralPath $destination) { throw "Output exists; choose a new -Name: $destination" }
New-Item -ItemType Directory -Path "$destination\frames" -Force | Out-Null
$log = Join-Path $destination 'godot.log'
$movie = Join-Path $destination 'frames\frame.png'
$report = Join-Path $destination 'report.json'
# Real Windows rendering. The project controls duration and writes an event report.
& $Godot --path $LabRoot --rendering-method gl_compatibility --disable-vsync --resolution 720x1280 --fixed-fps $Fps --write-movie $movie -- --config=$Config --frames=$Frames --report=$report *> $log
if ($LASTEXITCODE -ne 0) { throw "Godot exited $LASTEXITCODE; see $log" }
Assert-GodotLog $log
$images = @(Get-ChildItem -LiteralPath "$destination\frames" -Filter '*.png' | Sort-Object Name)
if ($images.Count -lt $Frames) { throw "Expected at least $Frames frames; got $($images.Count)." }
# Use the actual first filename because Godot owns the sequence numbering convention.
$first = $images[0].Name
if ($first -notmatch '^(.*?)(\d+)\.png$') { throw "Unexpected sequence filename: $first" }
$pattern = Join-Path "$destination\frames" ($Matches[1] + '%0' + $Matches[2].Length + 'd.png')
$start = [int]$Matches[2]
$mp4 = Join-Path $destination 'final.mp4'
# This probe is silent. Do not imply that collision sound design has been implemented.
& $FFmpeg -y -v error -framerate $Fps -start_number $start -i $pattern -frames:v $Frames -c:v libx264 -crf 18 -preset fast -pix_fmt yuv420p -movflags +faststart $mp4 2> "$destination\encode.log"
if ($LASTEXITCODE -ne 0) { throw 'Video encode failed; see encode.log.' }
& $FFmpeg -v error -i $mp4 -f null - 2> "$destination\decode.log"
if ($LASTEXITCODE -ne 0) { throw 'Video decode validation failed.' }
$summary = [ordered]@{ config=$Config; fps=$Fps; requested_frames=$Frames; written_pngs=$images.Count; encoded_frames=$Frames; expected_seconds=($Frames / [double]$Fps); video=$mp4; audio='none (validation sample)' }
$summary | ConvertTo-Json | Set-Content -LiteralPath "$destination\export.json" -Encoding UTF8
Copy-Item -LiteralPath $images[[Math]::Min($Frames - 1, $images.Count - 1)].FullName -Destination "$destination\preview.png"
Write-Output $mp4
