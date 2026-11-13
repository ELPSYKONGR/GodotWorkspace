# Keep this portable project and its runtime writes on the project drive.
$ErrorActionPreference = 'Stop'
$LabRoot = Split-Path -Parent $PSScriptRoot
$Godot = Join-Path $LabRoot '.runtime\godot\Godot_v4.7.2-stable_win64_console.exe'
$env:TEMP = Join-Path $LabRoot '.runtime\temp'
$env:TMP = $env:TEMP
$env:APPDATA = Join-Path $LabRoot '.runtime\appdata\roaming'
$env:LOCALAPPDATA = Join-Path $LabRoot '.runtime\appdata\local'
New-Item -ItemType Directory -Path $env:TEMP, $env:APPDATA, $env:LOCALAPPDATA, "$LabRoot\scratch" -Force | Out-Null
# Temporary fixture projects must not be imported as nested production projects.
New-Item -ItemType File -Path "$LabRoot\scratch\.gdignore" -Force | Out-Null
# Rendered PNG sequences are data, not editor assets; avoid importing thousands of frames.
New-Item -ItemType Directory -Path "$LabRoot\outputs" -Force | Out-Null
New-Item -ItemType File -Path "$LabRoot\outputs\.gdignore" -Force | Out-Null
if (-not (Test-Path -LiteralPath $Godot)) { throw 'Godot runtime missing; see README.' }

function Assert-GodotLog([string]$LogPath) {
    # Godot can exit 0 after a script error; inspect diagnostics as well as the exit code.
    if (Select-String -LiteralPath $LogPath -Pattern 'SCRIPT ERROR:|Parse Error:|^ERROR:' -Quiet) {
        throw "Godot reported an error. See $LogPath"
    }
}
