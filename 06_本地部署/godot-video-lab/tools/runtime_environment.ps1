# Resolve portable paths with process environment > .env > project defaults; never execute .env text.
$ErrorActionPreference = 'Stop'
$LabRoot = Split-Path -Parent $PSScriptRoot
$toolDefaults = @{
    VIDEO_LAB_GODOT = '.runtime\godot\Godot_v4.7.2-stable_win64_console.exe'
    VIDEO_LAB_RENDER_GODOT = '.runtime\godot\Godot_v4.7.2-stable_win64.exe'
    VIDEO_LAB_PYTHON = '.runtime\python\python.exe'
    VIDEO_LAB_FFMPEG = '.runtime\ffmpeg.exe'
}
$dotenvValues = @{}
$dotenvPath = Join-Path $LabRoot '.env'
if (Test-Path -LiteralPath $dotenvPath) {
    $lineNumber = 0
    foreach ($line in [IO.File]::ReadAllLines($dotenvPath, [Text.Encoding]::UTF8)) {
        $lineNumber += 1
        $text = $line.Trim()
        if ($text -eq '' -or $text.StartsWith('#')) { continue }
        if ($text -notmatch '^([A-Z][A-Z0-9_]*)\s*=(.*)$') { throw "Invalid .env syntax at line $lineNumber" }
        $key = $Matches[1]
        $value = $Matches[2].Trim()
        if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        if ($toolDefaults.ContainsKey($key)) { $dotenvValues[$key] = $value }
    }
}
foreach ($key in $toolDefaults.Keys) {
    $value = [Environment]::GetEnvironmentVariable($key, 'Process')
    if ([string]::IsNullOrWhiteSpace($value)) { $value = $dotenvValues[$key] }
    if ([string]::IsNullOrWhiteSpace($value)) { $value = $toolDefaults[$key] }
    if (-not [IO.Path]::IsPathRooted($value)) { $value = Join-Path $LabRoot $value }
    [Environment]::SetEnvironmentVariable($key, [IO.Path]::GetFullPath($value), 'Process')
}
$Godot = $env:VIDEO_LAB_GODOT
$RenderGodot = $env:VIDEO_LAB_RENDER_GODOT
$PythonExecutable = $env:VIDEO_LAB_PYTHON
$FFmpegExecutable = $env:VIDEO_LAB_FFMPEG
# All application-owned caches and temporary files follow the project to its destination drive.
$env:TEMP = Join-Path $LabRoot '.runtime\temp'
$env:TMP = $env:TEMP
$env:APPDATA = Join-Path $LabRoot '.runtime\appdata\roaming'
$env:LOCALAPPDATA = Join-Path $LabRoot '.runtime\appdata\local'
$env:PYTHONUTF8 = '1'
$env:PYTHONDONTWRITEBYTECODE = '1'
New-Item -ItemType Directory -Path $env:TEMP, $env:APPDATA, $env:LOCALAPPDATA, "$LabRoot\scratch", "$LabRoot\outputs" -Force | Out-Null
foreach ($folder in @('scratch', 'outputs')) {
    New-Item -ItemType File -Path (Join-Path $LabRoot "$folder\.gdignore") -Force | Out-Null
}
