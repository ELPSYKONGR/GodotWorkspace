# Reuse the portable preview entry and prevent simultaneous workbenches for this project.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$hash = [Security.Cryptography.SHA256]::Create()
try {
    $projectKey = [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($LabRoot.ToLowerInvariant()))).Replace('-', '')
} finally {
    $hash.Dispose()
}
$gate = [Threading.Mutex]::new($false, "Local\GodotVideoLab.Launch.$projectKey")
$held = $false
try {
    try { $held = $gate.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $held = $true }
    if (-not $held) {
        Write-Host '工作台已在运行或正在启动，请使用已打开的窗口。'
        exit 2
    }
    # Also recognize a workbench opened through preview.cmd or the editor.
    $projectArgument = '--path\s+"?' + [regex]::Escape($LabRoot) + '(?:"|\s|$)'
    $running = Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%.exe'" |
        Where-Object { ([string]$_.CommandLine).Replace('/', '\') -match $projectArgument -and $_.CommandLine -match 'res://workbench\.tscn' }
    if ($running) {
        Write-Host '工作台已在运行，请使用已打开的窗口。'
        exit 2
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\preview.ps1" -Workbench
    exit $LASTEXITCODE
} finally {
    if ($held) { $gate.ReleaseMutex() }
    $gate.Dispose()
}
