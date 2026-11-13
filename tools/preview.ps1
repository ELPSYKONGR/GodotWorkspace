param([ValidateSet('2d','3d','perspective')][string]$Scene = '2d', [switch]$Editor)
. "$PSScriptRoot\common.ps1"
$sceneFile = "res://config/demo_$Scene.json"
if ($Editor) {
    & $Godot --path $LabRoot --editor
} else {
    & $Godot --path $LabRoot -- --config=$sceneFile
}
exit $LASTEXITCODE
