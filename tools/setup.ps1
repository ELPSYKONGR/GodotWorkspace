param([string]$FFmpegSource = '')
# Recreate the portable runtime without a global installation.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $root '.runtime'
New-Item -ItemType Directory -Path "$runtime\godot", "$runtime\temp" -Force | Out-Null
$env:TEMP = "$runtime\temp"
$env:TMP = $env:TEMP
$archive = "$runtime\Godot_v4.7.2-stable_win64.exe.zip"
$url = 'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip'
if (-not (Test-Path -LiteralPath $archive)) {
    & curl.exe --ssl-no-revoke --location --fail --connect-timeout 15 --max-time 300 --output $archive $url
    if ($LASTEXITCODE -ne 0) { throw 'Godot download failed.' }
}
$expected = '731980F9608D61333E5BAF54A2EF17210ACC7A538446C0CB9969F002ACA1E953'
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expected) { throw 'Archive differs from the validated deployment.' }
Expand-Archive -LiteralPath $archive -DestinationPath "$runtime\godot" -Force
Set-Content -LiteralPath "$runtime\godot\_sc_" -Value '' -Encoding ascii
if ($FFmpegSource -eq '') {
    $FFmpegSource = Join-Path (Split-Path -Parent $root) 'relaxing-physics\.venv\Lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe'
}
if (Test-Path -LiteralPath $FFmpegSource) {
    Copy-Item -LiteralPath $FFmpegSource -Destination "$runtime\ffmpeg.exe" -Force
} elseif (-not (Test-Path -LiteralPath "$runtime\ffmpeg.exe")) {
    throw 'Supply -FFmpegSource pointing to a local FFmpeg executable.'
}
. "$PSScriptRoot\common.ps1"
& $Godot --version
& $Godot --headless --path $LabRoot --editor --import *> "$runtime\import.log"
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
Assert-GodotLog "$runtime\import.log"
Write-Output "Ready: $LabRoot"
