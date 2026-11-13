param([Parameter(Mandatory=$true)][string]$JobDir)
# Produce one frozen take in a separate renderer, with sample-aligned audio and validation.
. "$PSScriptRoot\common.ps1"
$env:PYTHONUTF8 = '1'
$JobDir = [IO.Path]::GetFullPath($JobDir)
if (-not (Test-Path -LiteralPath "$JobDir\job.json")) { throw 'Missing job.json' }
# Allow a standalone portable Python or an explicit installation when moving this project.
$Python = $env:VIDEO_LAB_PYTHON
if ([string]::IsNullOrWhiteSpace($Python)) {
    $portablePython = Join-Path $LabRoot '.runtime\python\python.exe'
    $Python = if (Test-Path -LiteralPath $portablePython) { $portablePython } else { Join-Path (Split-Path -Parent $LabRoot) 'relaxing-physics\.venv\Scripts\python.exe' }
}
$FFmpeg = Join-Path $LabRoot '.runtime\ffmpeg.exe'
$RenderGodot = Join-Path $LabRoot '.runtime\godot\Godot_v4.7.2-stable_win64.exe'
$currentProcess = $null
$stage = 'starting'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$productionClock = [Diagnostics.Stopwatch]::StartNew()
$stageSeconds = [ordered]@{}

function Write-JobStatus([string]$State, [string]$Message = '') {
    # Replace a complete JSON file so the panel never reads a half-written status.
    $status = [ordered]@{ state=$State; message=$Message; updated_utc=[DateTime]::UtcNow.ToString('o'); elapsed_seconds=[Math]::Round($productionClock.Elapsed.TotalSeconds, 3); stage_seconds=$stageSeconds }
    $temporary = Join-Path $JobDir "status.ps-$PID.tmp"
    $destination = Join-Path $JobDir 'status.json'
    [IO.File]::WriteAllText($temporary, ($status | ConvertTo-Json), $utf8)
    if (Test-Path -LiteralPath $destination) {
        # PowerShell 5 can coerce $null into an invalid empty backup filename.
        [IO.File]::Replace($temporary, $destination, [NullString]::Value)
    } else {
        [IO.File]::Move($temporary, $destination)
    }
}

function Assert-NotCancelled {
    # The request belongs only to this job; no process-name-wide termination is used.
    if (Test-Path -LiteralPath "$JobDir\cancel.request") { throw [OperationCanceledException]::new('Cancelled by user') }
}

function Quote-ProcessArgument([string]$Value) {
    # Follow Windows CommandLineToArgvW quoting, including trailing backslashes.
    $quoted = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $quoted = [regex]::Replace($quoted, '(\\+)$', '$1$1')
    return '"' + $quoted + '"'
}

function Invoke-JobProcess([string]$Executable, [string[]]$Arguments, [string]$Name) {
    # Redirect stderr without PowerShell treating native warnings as terminating errors.
    Assert-NotCancelled
    $argumentLine = ($Arguments | ForEach-Object { Quote-ProcessArgument $_ }) -join ' '
    $stdout = Join-Path $JobDir "$Name.stdout.log"
    $stderr = Join-Path $JobDir "$Name.stderr.log"
    $script:currentProcess = Start-Process -FilePath $Executable -ArgumentList $argumentLine -WorkingDirectory $LabRoot -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    # Retain the native handle before waiting; PS5 otherwise may return a null ExitCode.
    $nativeHandle = $script:currentProcess.Handle
    $pidFile = Join-Path $JobDir "$Name.pid"
    [IO.File]::WriteAllText($pidFile, [string]$script:currentProcess.Id, $utf8)
    $stageClock = [Diagnostics.Stopwatch]::StartNew()
    try {
        while (-not $script:currentProcess.WaitForExit(200)) {
            if (Test-Path -LiteralPath "$JobDir\cancel.request") {
                if (-not $script:currentProcess.HasExited) { $script:currentProcess.Kill() }
                $script:currentProcess.WaitForExit()
                throw [OperationCanceledException]::new('Cancelled by user')
            }
            if ($Name -eq 'godot') {
                foreach ($log in @($stdout, $stderr, (Join-Path $JobDir 'render_engine.log'))) {
                    if ((Test-Path -LiteralPath $log) -and (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR:|Parse Error:|^ERROR:' -Quiet)) {
                        if (-not $script:currentProcess.HasExited) { $script:currentProcess.Kill() }
                        $script:currentProcess.WaitForExit()
                        throw "Godot script/render error; see $log"
                    }
                }
            }
        }
        $script:currentProcess.WaitForExit()
        $exitCode = $script:currentProcess.ExitCode
        if ($null -eq $exitCode) { throw "$Name exit code unavailable (handle $nativeHandle)" }
        if ($exitCode -eq 5 -and $Name -eq 'godot') { throw [OperationCanceledException]::new('Renderer cancelled') }
        if ($exitCode -ne 0) { throw "$Name exited with code $exitCode; see $stderr" }
        if ($Name -eq 'godot') {
            foreach ($log in @($stdout, $stderr, (Join-Path $JobDir 'render_engine.log'))) {
                if ((Test-Path -LiteralPath $log) -and (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR:|Parse Error:|^ERROR:' -Quiet)) {
                    throw "Godot reported an error; see $log"
                }
            }
        }
    } finally {
        $stageSeconds[$Name] = [Math]::Round($stageClock.Elapsed.TotalSeconds, 3)
        if (Test-Path -LiteralPath $pidFile) { Remove-Item -LiteralPath $pidFile }
    }
    $script:currentProcess = $null
}

try {
    foreach ($dependency in @($Python, $FFmpeg, $RenderGodot, "$JobDir\scene.snapshot.json", "$JobDir\take.json")) {
        if (-not (Test-Path -LiteralPath $dependency)) { throw "Missing dependency or job input: $dependency" }
    }
    $job = Get-Content -LiteralPath "$JobDir\job.json" -Encoding UTF8 -Raw | ConvertFrom-Json
    $fps = [int]$job.fps
    $frames = [int]$job.frames
    $width = [int]$job.width
    $height = [int]$job.height
    if ($fps -lt 15 -or $fps -gt 120 -or $frames -lt 1 -or $frames / [double]$fps -gt 60 -or $width -lt 16 -or $height -lt 16 -or $width % 2 -ne 0 -or $height % 2 -ne 0) { throw 'Invalid FPS/frame count/geometry in job.json' }
    if ($job.backend -notin @('gl_compatibility', 'forward_plus')) { throw 'Unsupported rendering backend in job.json' }
    $duration = $frames / [double]$fps
    New-Item -ItemType Directory -Path "$JobDir\frames" -Force | Out-Null
    $arguments = @('--path', $LabRoot, '--disable-vsync', '--log-file', "$JobDir\render_engine.log")
    if ($job.backend -eq 'forward_plus') {
        $arguments += @('--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan')
    } else {
        $arguments += @('--rendering-method', 'gl_compatibility')
    }
    $arguments += @('res://production.tscn', '--', "--job=$JobDir")
    $stage = 'rendering'
    Write-JobStatus $stage
    Invoke-JobProcess $RenderGodot $arguments 'godot'
    Assert-NotCancelled
    if (-not (Test-Path -LiteralPath "$JobDir\frames\frame_0000000.png")) { throw 'Renderer did not create the first frame' }
    $stage = 'mixing'
    Write-JobStatus $stage
    $durationText = $duration.ToString('0.########', [Globalization.CultureInfo]::InvariantCulture)
    Invoke-JobProcess $Python @('-B', "$PSScriptRoot\mix_take.py", '--take', "$JobDir\take.json", '--scene', "$JobDir\scene.snapshot.json", '--output', "$JobDir\mix.wav", '--duration', $durationText) 'mix'
    $stage = 'encoding'
    Write-JobStatus $stage
    Invoke-JobProcess $FFmpeg @('-y', '-hide_banner', '-loglevel', 'warning', '-framerate', [string]$fps, '-start_number', '0', '-i', "$JobDir\frames\frame_%07d.png", '-i', "$JobDir\mix.wav", '-frames:v', [string]$frames, '-c:v', 'libx264', '-preset', 'fast', '-crf', '18', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-t', $durationText, '-movflags', '+faststart', "$JobDir\final.mp4") 'encode'
    $stage = 'validating'
    Write-JobStatus $stage
    Invoke-JobProcess $Python @('-B', "$PSScriptRoot\inspect_job.py", '--job', $JobDir) 'inspect'
    $validation = Get-Content -LiteralPath "$JobDir\validation.json" -Encoding UTF8 -Raw | ConvertFrom-Json
    if (-not $validation.passed) { throw 'Media validation failed; see validation.json' }
    Assert-NotCancelled
    Write-JobStatus 'complete' 'Video, audio and media validation complete'
    Write-Output "$JobDir\final.mp4"
} catch [OperationCanceledException] {
    Write-JobStatus 'cancelled' $_.Exception.Message
    exit 5
} catch {
    if ($null -ne $currentProcess -and -not $currentProcess.HasExited) { $currentProcess.Kill(); $currentProcess.WaitForExit() }
    Write-JobStatus 'failed' ("$stage : " + $_.Exception.Message)
    Write-Error $_.Exception.Message -ErrorAction Continue
    exit 1
} finally {
    $workerPidFile = Join-Path $JobDir 'job.pid'
    if ((Test-Path -LiteralPath $workerPidFile) -and ([IO.File]::ReadAllText($workerPidFile).Trim() -eq [string]$PID)) {
        Remove-Item -LiteralPath $workerPidFile
    }
}
