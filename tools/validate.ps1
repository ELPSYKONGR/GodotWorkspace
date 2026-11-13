# Run the independent collision fixtures, preview-host checks, and a 3D physical run.
. "$PSScriptRoot\common.ps1"
New-Item -ItemType Directory -Path "$LabRoot\outputs" -Force | Out-Null
& $Godot --headless --path $LabRoot --script res://tools/validate_2d.gd --fixed-fps 240 *> "$LabRoot\outputs\probe_2d_validation.log"
if ($LASTEXITCODE -ne 0) { throw '2D fixtures failed.' }
Assert-GodotLog "$LabRoot\outputs\probe_2d_validation.log"
& $Godot --headless --path $LabRoot --script res://tools/validate_host.gd --quit-after 500 *> "$LabRoot\outputs\host_validation.log"
if ($LASTEXITCODE -ne 0) { throw 'Preview host checks failed.' }
Assert-GodotLog "$LabRoot\outputs\host_validation.log"
& $Godot --headless --path $LabRoot --fixed-fps 30 -- --config=res://config/demo_3d.json --frames=180 "--report=$LabRoot/outputs/3d_physics.json" *> "$LabRoot\outputs\3d_validation.log"
if ($LASTEXITCODE -ne 0) { throw '3D probe failed.' }
Assert-GodotLog "$LabRoot\outputs\3d_validation.log"
$report = Get-Content -LiteralPath "$LabRoot\outputs\3d_physics.json" -Encoding UTF8 -Raw | ConvertFrom-Json
if ($report.collision_events -le 0 -or $report.escaped -ne 0) { throw '3D contact or containment check failed.' }
Write-Output 'Physical probes and preview host checks passed.'
