param([ValidateSet('2d','3d','perspective','glass','neon')][string]$Scene = '2d', [switch]$Editor, [switch]$Workbench, [switch]$Legacy)
. "$PSScriptRoot\common.ps1"
if ($Legacy -and $Scene -in @('glass','neon')) { throw 'Glass and neon are available in the workbench, not the legacy prototype.' }
if ($Workbench -and $Legacy) { throw 'Use either -Workbench or -Legacy, not both.' }
$sceneFile = "res://config/demo_$Scene.json"
if ($Editor) {
    & $Godot --path $LabRoot --editor
} elseif ($Legacy) {
    & $Godot --path $LabRoot res://main.tscn -- --config=$sceneFile
} else {
    # The explicit -Workbench switch remains compatible; workbench is now the default.
    & $Godot --path $LabRoot res://workbench.tscn -- --scene="res://config/workbench_$Scene.json"
}
exit $LASTEXITCODE
