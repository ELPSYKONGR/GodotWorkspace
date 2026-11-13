# Keep this portable project and its runtime writes on the project drive.
. "$PSScriptRoot\runtime_environment.ps1"
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw 'Godot runtime missing; run tools/setup.ps1.' }

function Assert-GodotLog([string]$LogPath) {
    # Godot can exit 0 after a script error; inspect diagnostics as well as the exit code.
    if (Select-String -LiteralPath $LogPath -Pattern 'SCRIPT ERROR:|Parse Error:|^ERROR:' -Quiet) {
        throw "Godot reported an error. See $LogPath"
    }
}
