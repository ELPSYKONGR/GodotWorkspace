param([switch]$Legacy, [switch]$WavJob)
# Run the actual adapters, workbench and producer; stop at the first failed stage.
. "$PSScriptRoot\common.ps1"
$env:PYTHONUTF8 = '1'
$env:PYTHONDONTWRITEBYTECODE = '1'
$suitePath = Join-Path $LabRoot 'outputs\workbench_suite.json'
$suiteClock = [Diagnostics.Stopwatch]::StartNew()
$utf8 = New-Object System.Text.UTF8Encoding($false)
$suite = [ordered]@{
    suite_version = 1
    passed = $false
    status = 'running'
    started_utc = [DateTime]::UtcNow.ToString('o')
    elapsed_seconds = 0
    legacy = [bool]$Legacy
    wav_job = [bool]$WavJob
    python_path = ''
    stages = New-Object 'Collections.Generic.List[object]'
}

function Save-Suite {
    $suite.elapsed_seconds = [Math]::Round($suiteClock.Elapsed.TotalSeconds, 3)
    [IO.File]::WriteAllText($suitePath, ($suite | ConvertTo-Json -Depth 12), $utf8)
}

function Invoke-Check([string]$Name, [string]$Executable, [string[]]$ProcessArgs, [string[]]$Reports) {
    $stageClock = [Diagnostics.Stopwatch]::StartNew()
    $started = [DateTime]::UtcNow
    $log = Join-Path $LabRoot "outputs\suite_$Name.log"
    $paths = @($Reports | ForEach-Object { Join-Path $LabRoot $_ })
    $entry = [ordered]@{ name=$Name; passed=$false; started_utc=$started.ToString('o'); elapsed_seconds=0; report_paths=$paths; log_path=$log }
    $suite.stages.Add($entry)
    Write-Output "[$Name] running"
    try {
        # Windows PowerShell otherwise treats a native stderr warning as a terminating error.
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $Executable @ProcessArgs *> $log
            $nativeExit = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousPreference
        }
        $entry.exit_code = $nativeExit
        Assert-GodotLog $log
        if ($nativeExit -ne 0) { throw "Process exited with code $nativeExit; see $log" }
        foreach ($path in $paths) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing report: $path" }
            if ((Get-Item -LiteralPath $path).LastWriteTimeUtc -lt $started) { throw "Report was not produced by this run: $path" }
            $report = Get-Content -LiteralPath $path -Encoding UTF8 -Raw | ConvertFrom-Json
            # The legacy 3D report exposes contact/escape metrics rather than a passed field.
            if ($Name -eq 'Legacy' -and [IO.Path]::GetFileName($path) -eq '3d_physics.json') {
                if ($report.collision_events -le 0 -or $report.escaped -ne 0) { throw "Legacy 3D metrics failed: $path" }
            } elseif ($null -eq $report.PSObject.Properties['passed'] -or $report.passed -ne $true) {
                throw "Report failed or missing a passed result: $path"
            }
        }
        $entry.passed = $true
    } catch {
        $entry.error = $_.Exception.Message
        throw
    } finally {
        $entry.elapsed_seconds = [Math]::Round($stageClock.Elapsed.TotalSeconds, 3)
        $entry.completed_utc = [DateTime]::UtcNow.ToString('o')
        Save-Suite
    }
    Write-Output "[$Name] passed ($($entry.elapsed_seconds)s)"
}

function Invoke-GodotCheck([string]$Name, [string]$Script, [string]$Report, [int]$Fps, [int]$QuitAfter, [switch]$Realtime) {
    $arguments = @('--headless', '--path', $LabRoot, '--script', "res://tools/$Script", '--quit-after', [string]$QuitAfter)
    # Production polling uses real deadlines; keep its process alive for those deadlines.
    if ($Realtime) { $arguments += @('--max-fps', '60') }
    else { $arguments += @('--fixed-fps', [string]$Fps) }
    Invoke-Check $Name $Godot $arguments @($Report)
}

try {
    Save-Suite
    $Python = $PythonExecutable
    if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) { throw 'Python missing. Run tools/setup.ps1 or set VIDEO_LAB_PYTHON.' }
    $suite.python_path = $Python
    Invoke-GodotCheck 'World' 'validate_worlds.gd' 'outputs\worlds_validation.json' 120 2400
    Invoke-GodotCheck 'SplitInheritance' 'validate_split_inheritance.gd' 'outputs\split_inheritance_validation.json' 120 12000
    Invoke-GodotCheck 'Session' 'validate_session.gd' 'outputs\session_validation.json' 60 1600
    Invoke-GodotCheck 'Commands' 'validate_commands.gd' 'outputs\commands_validation.json' 60 100
    Invoke-GodotCheck 'Capacity' 'validate_capacity.gd' 'outputs\capacity_validation.json' 60 300
    Invoke-GodotCheck 'Glass' 'validate_glass.gd' 'outputs\glass_validation.json' 120 4000
    Invoke-GodotCheck 'Neon' 'validate_neon.gd' 'outputs\neon_validation.json' 120 1200
    Invoke-GodotCheck 'EffectSwitches' 'validate_effect_switches.gd' 'outputs\effect_switches_validation.json' 120 1200
    Invoke-GodotCheck 'SpeedApply' 'validate_speed_apply.gd' 'outputs\speed_apply_validation.json' 120 6000
    Invoke-GodotCheck 'Motion' 'validate_motion.gd' 'outputs\motion_validation.json' 120 1600
    Invoke-GodotCheck 'UI' 'validate_ui.gd' 'outputs\ui_validation.json' 60 100
    Invoke-GodotCheck 'EditorLayout' 'validate_editor_layout.gd' 'outputs\editor_layout_validation.json' 60 1200
    Invoke-GodotCheck 'SceneWorkspace' 'validate_scene_workspace.gd' 'outputs\scene_workspace_validation.json' 120 1200
    Invoke-GodotCheck 'SceneEditing' 'validate_scene_editing.gd' 'outputs\scene_editing_validation.json' 120 1200
    Invoke-GodotCheck 'CameraTrack' 'validate_camera_track.gd' 'outputs\camera_track_validation.json' 120 200
    Invoke-GodotCheck 'PolygonStyles' 'validate_polygon_styles.gd' 'outputs\polygon_styles_validation.json' 120 800
    Invoke-GodotCheck 'LongWorld' 'validate_long_world.gd' 'outputs\long_world_validation.json' 120 3000
    Invoke-GodotCheck 'PerformancePaths' 'validate_performance_paths.gd' 'outputs\performance_paths_validation.json' 120 1000
    Invoke-GodotCheck 'FastCCD' 'validate_fast_ccd.gd' 'outputs\fast_ccd_validation.json' 120 200
    Invoke-GodotCheck 'SplitControls' 'validate_split_controls.gd' 'outputs\split_controls_validation.json' 120 15000
    Invoke-GodotCheck 'Media' 'validate_media.gd' 'outputs\media_components_validation.json' 60 300 -Realtime
    Invoke-Check 'Mixer' $Python @('-B', (Join-Path $PSScriptRoot 'validate_mixer.py')) @('outputs\mixer_validation.json')
    Invoke-GodotCheck 'Host' 'validate_workbench.gd' 'outputs\workbench_validation.json' 60 15000 -Realtime
    if ($Legacy) {
        $shell = (Get-Process -Id $PID).Path
        Invoke-Check 'Legacy' $shell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'validate.ps1')) @('outputs\probe_2d_validation.json', 'outputs\host_validation.json', 'outputs\3d_physics.json')
    }
    if ($WavJob) {
        Invoke-GodotCheck 'WavJob' 'validate_wav_job.gd' 'outputs\wav_job_validation.json' 60 15000 -Realtime
    }
    $suite.passed = $true
    $suite.status = 'complete'
    Save-Suite
    Write-Output "Workbench suite passed in $($suite.elapsed_seconds)s. Report: $suitePath"
} catch {
    $suite.status = 'failed'
    $suite.error = $_.Exception.Message
    Save-Suite
    Write-Error "$($suite.error) Suite report: $suitePath" -ErrorAction Continue
    exit 1
}
