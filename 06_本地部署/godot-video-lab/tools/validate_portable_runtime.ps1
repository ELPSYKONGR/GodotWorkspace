# Verify bundled tools and .env precedence without editing the user's scene or control bridge.
. "$PSScriptRoot\common.ps1"
$validationRoot = $LabRoot
$checks = [ordered]@{}
$details = [ordered]@{}
$lock = Get-Content -LiteralPath (Join-Path $validationRoot 'config\runtime-lock.json') -Encoding UTF8 -Raw | ConvertFrom-Json
$pythonCode = "import json,sys,PIL; from PIL import Image; print(json.dumps({'executable':sys.executable,'prefix':sys.base_prefix,'paths':sys.path,'python':sys.version.split()[0],'pillow':PIL.__version__,'image_bytes':len(Image.new('RGB',(2,2)).tobytes())}))"
$pythonInfo = (& $PythonExecutable -B -c $pythonCode) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Portable interpreter inspection failed.' }
$portableRoot = [IO.Path]::GetFullPath((Join-Path $validationRoot '.runtime\python'))
$checks.python_has_project_base = $pythonInfo.prefix -eq $portableRoot
$checks.python_has_no_sibling_paths = @($pythonInfo.paths | Where-Object { -not ([IO.Path]::GetFullPath($_)).StartsWith(($validationRoot + '\'), [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0
$checks.python_version_locked = $pythonInfo.python -eq $lock.python.version
$checks.pillow_works = $pythonInfo.pillow -eq $lock.pillow.version -and $pythonInfo.image_bytes -eq 12
$details.python = $pythonInfo
foreach ($name in @('godot', 'python', 'pillow', 'ffmpeg', 'mingit')) {
    $artifact = $lock.$name
    $archive = Join-Path $validationRoot ('.runtime\downloads\' + $artifact.filename)
    if ($name -eq 'mingit' -and -not (Test-Path -LiteralPath $archive)) { $details.mingit = 'Optional development tool not installed'; continue }
    $checks["cached_${name}_hash"] = (Test-Path -LiteralPath $archive) -and (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -eq $artifact.sha256
}
$checks.ffmpeg_binary_locked = (Get-FileHash -LiteralPath $FFmpegExecutable -Algorithm SHA256).Hash -eq $lock.ffmpeg.binary_sha256
$checks.godot_binary_locked = (Get-FileHash -LiteralPath $Godot -Algorithm SHA256).Hash -eq $lock.godot.console_sha256
$checks.godot_gui_present = Test-Path -LiteralPath $RenderGodot
$checks.godot_self_contained_marker = Test-Path -LiteralPath (Join-Path $validationRoot '.runtime\godot\_sc_')

function Test-EnvironmentPrecedence {
    # Use a path containing spaces so relative defaults cannot accidentally depend on cwd.
    $fixtureRoot = Join-Path $validationRoot 'scratch\runtime precedence fixture'
    $fixtureTools = Join-Path $fixtureRoot 'tools'
    New-Item -ItemType Directory -Path $fixtureTools -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $validationRoot 'tools\runtime_environment.ps1') -Destination $fixtureTools -Force
    $fixtureEnv = Join-Path $fixtureRoot '.env'
    $keys = @('VIDEO_LAB_GODOT', 'VIDEO_LAB_RENDER_GODOT', 'VIDEO_LAB_PYTHON', 'VIDEO_LAB_FFMPEG')
    $saved = @{}
    foreach ($key in ($keys + @('TEMP', 'TMP', 'APPDATA', 'LOCALAPPDATA', 'PYTHONUTF8', 'PYTHONDONTWRITEBYTECODE'))) {
        $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
    }
    try {
        [IO.File]::WriteAllText($fixtureEnv, '')
        foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key, $null, 'Process') }
        . (Join-Path $fixtureTools 'runtime_environment.ps1')
        $checks.default_paths_follow_project = $PythonExecutable -eq (Join-Path $fixtureRoot '.runtime\python\python.exe')
        [IO.File]::WriteAllText($fixtureEnv, "VIDEO_LAB_PYTHON='tools/custom python.exe'`nVIDEO_LAB_FFMPEG=tools/custom ffmpeg.exe`n")
        foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key, $null, 'Process') }
        . (Join-Path $fixtureTools 'runtime_environment.ps1')
        $checks.dotenv_overrides_defaults = $PythonExecutable -eq (Join-Path $fixtureRoot 'tools\custom python.exe') -and $FFmpegExecutable -eq (Join-Path $fixtureRoot 'tools\custom ffmpeg.exe')
        [Environment]::SetEnvironmentVariable('VIDEO_LAB_PYTHON', 'tools/env python.exe', 'Process')
        . (Join-Path $fixtureTools 'runtime_environment.ps1')
        $checks.process_environment_overrides_dotenv = $PythonExecutable -eq (Join-Path $fixtureRoot 'tools\env python.exe')
        $checks.runtime_writes_follow_project = $env:TEMP -eq (Join-Path $fixtureRoot '.runtime\temp') -and $env:APPDATA -eq (Join-Path $fixtureRoot '.runtime\appdata\roaming')
    } finally {
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
    }
}

Test-EnvironmentPrecedence
$report = [ordered]@{ passed= -not (@($checks.Values) -contains $false); checks=$checks; details=$details; checked_utc=[DateTime]::UtcNow.ToString('o') }
$reportPath = Join-Path $validationRoot 'outputs\portable_runtime_validation.json'
[IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
$report | ConvertTo-Json -Depth 10
if (-not $report.passed) { throw "Portable runtime validation failed; see $reportPath" }
