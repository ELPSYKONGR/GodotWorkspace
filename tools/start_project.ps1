param([switch]$Editor, [switch]$Verify)
# Resolve the relocated project from this script, without old drive letters.
$ErrorActionPreference = 'Stop'
$researchRoot = Split-Path -Parent $PSScriptRoot
$deployment = @(Get-ChildItem -LiteralPath $researchRoot -Directory -Filter '06_*')
if ($deployment.Count -ne 1) { throw 'Expected one 06_* deployment directory.' }
$workbenchRoot = Join-Path $deployment[0].FullName 'godot-video-lab'
Set-Location -LiteralPath $workbenchRoot
. (Join-Path $workbenchRoot 'tools\common.ps1')
if ($Verify) {
    & $PythonExecutable -B (Join-Path $workbenchRoot 'tools\build_handoff.py') --verify $researchRoot
} elseif ($Editor) {
    & $Godot --path $workbenchRoot --editor
} else {
    $scene = if (Test-Path -LiteralPath (Join-Path $workbenchRoot 'config\handoff_current_scene.json')) { 'res://config/handoff_current_scene.json' } else { 'res://config/workbench_2d.json' }
    & $Godot --path $workbenchRoot res://workbench.tscn -- "--scene=$scene"
}
exit $LASTEXITCODE
