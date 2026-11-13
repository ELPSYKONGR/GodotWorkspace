param([string]$FFmpegSource = '', [switch]$SkipImport, [switch]$DevTools)
# Restore only pinned Windows x64 artifacts; cached archives permit offline reinstall.
. "$PSScriptRoot\runtime_environment.ps1"
$runtime = Join-Path $LabRoot '.runtime'
$cache = Join-Path $runtime 'downloads'
$licenses = Join-Path $runtime 'licenses'
$lock = Get-Content -LiteralPath (Join-Path $LabRoot 'config\runtime-lock.json') -Encoding UTF8 -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Path $cache, $licenses -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Assert-ArtifactHash([string]$Path, [string]$Expected) {
    # Integrity checks apply to cached downloads too, rather than trusting file presence.
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Expected) { throw "Artifact SHA256 mismatch: $Path" }
}

function Get-LockedArtifact($Artifact) {
    # Keep the first deployment's archives usable after moving to the common cache.
    $path = Join-Path $cache $Artifact.filename
    $legacy = Join-Path $runtime $Artifact.filename
    if (-not (Test-Path -LiteralPath $path) -and (Test-Path -LiteralPath $legacy)) { Move-Item -LiteralPath $legacy -Destination $path }
    if (-not (Test-Path -LiteralPath $path)) {
        $temporary = $path + '.partial'
        & curl.exe --silent --show-error --location --fail --connect-timeout 15 --max-time 300 --output $temporary $Artifact.url
        if ($LASTEXITCODE -ne 0) { throw "Artifact download failed: $($Artifact.filename)" }
        Assert-ArtifactHash $temporary $Artifact.sha256
        Move-Item -LiteralPath $temporary -Destination $path
    }
    Assert-ArtifactHash $path $Artifact.sha256
    return $path
}

function Expand-LockedArtifact([string]$Archive, [string]$Destination) {
    # Wheel files are ZIP containers; use the native reader without needing pip.
    $destinationRoot = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $zip.Entries) {
            $target = [IO.Path]::GetFullPath((Join-Path $destinationRoot $entry.FullName))
            if (-not $target.StartsWith($destinationRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe path in runtime archive' }
            if ($entry.Name -eq '') { New-Item -ItemType Directory -Path $target -Force | Out-Null; continue }
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
        }
    } finally { $zip.Dispose() }
}

$godotArchive = Get-LockedArtifact $lock.godot
$godotDirectory = Join-Path $runtime 'godot'
$guiDefault = Join-Path $godotDirectory 'Godot_v4.7.2-stable_win64.exe'
$consoleDefault = Join-Path $godotDirectory 'Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $guiDefault) -or -not (Test-Path -LiteralPath $consoleDefault)) { Expand-LockedArtifact $godotArchive $godotDirectory }
Assert-ArtifactHash $guiDefault $lock.godot.gui_sha256
Assert-ArtifactHash $consoleDefault $lock.godot.console_sha256
[IO.File]::WriteAllText((Join-Path $godotDirectory '_sc_'), '')

$pythonDirectory = Join-Path $runtime 'python'
$pythonArchive = Get-LockedArtifact $lock.python
if (-not (Test-Path -LiteralPath (Join-Path $pythonDirectory 'python.exe'))) { Expand-LockedArtifact $pythonArchive $pythonDirectory }
# Explicit relative search paths make the embeddable interpreter independent of Python installations.
$pythonPaths = "python312.zip`n.`nLib\site-packages`n..\..\tools`nimport site`n"
[IO.File]::WriteAllText((Join-Path $pythonDirectory 'python312._pth'), $pythonPaths, [Text.Encoding]::ASCII)
$sitePackages = Join-Path $pythonDirectory 'Lib\site-packages'
$pillowArchive = Get-LockedArtifact $lock.pillow
if (-not (Test-Path -LiteralPath (Join-Path $sitePackages 'pillow-11.3.0.dist-info\METADATA'))) { Expand-LockedArtifact $pillowArchive $sitePackages }
Copy-Item -LiteralPath (Join-Path $pythonDirectory 'LICENSE.txt') -Destination (Join-Path $licenses 'PYTHON-LICENSE.txt') -Force
New-Item -ItemType Directory -Path (Join-Path $licenses 'pillow') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $sitePackages 'pillow-11.3.0.dist-info\licenses\LICENSE') -Destination (Join-Path $licenses 'pillow\LICENSE') -Force

$ffmpegArchive = Get-LockedArtifact $lock.ffmpeg
$ffmpegPackage = Join-Path $runtime 'temp\imageio-ffmpeg-package'
Expand-LockedArtifact $ffmpegArchive $ffmpegPackage
$ffmpegDefault = Join-Path $runtime 'ffmpeg.exe'
$ffmpegBinary = Join-Path $ffmpegPackage $lock.ffmpeg.member
Assert-ArtifactHash $ffmpegBinary $lock.ffmpeg.binary_sha256
if ($FFmpegSource -ne '') {
    # Explicit custom builds are permitted, with their separate hash recorded below.
    Copy-Item -LiteralPath $FFmpegSource -Destination $ffmpegDefault -Force
} elseif (-not (Test-Path -LiteralPath $ffmpegDefault)) {
    Copy-Item -LiteralPath $ffmpegBinary -Destination $ffmpegDefault
} else { Assert-ArtifactHash $ffmpegDefault $lock.ffmpeg.binary_sha256 }
Copy-Item -LiteralPath (Join-Path $ffmpegPackage 'imageio_ffmpeg-0.6.0.dist-info\LICENSE') -Destination (Join-Path $licenses 'IMAGEIO-FFMPEG-LICENSE.txt') -Force

if ($DevTools) {
    $gitArchive = Get-LockedArtifact $lock.mingit
    $gitDirectory = Join-Path $runtime 'git'
    $gitExecutable = Join-Path $gitDirectory 'cmd\git.exe'
    if (-not (Test-Path -LiteralPath $gitExecutable)) { Expand-LockedArtifact $gitArchive $gitDirectory }
    & $gitExecutable --version
    if ($LASTEXITCODE -ne 0) { throw 'Portable Git version check failed.' }
}

. "$PSScriptRoot\common.ps1"
$portablePython = Join-Path $pythonDirectory 'python.exe'
& $portablePython -B -c "import sys,PIL; assert sys.version_info[:3] == (3,12,10); assert PIL.__version__ == '11.3.0'; from PIL import Image; Image.new('RGB',(2,2)).tobytes(); print(sys.version); print('Pillow '+PIL.__version__)"
if ($LASTEXITCODE -ne 0) { throw 'Portable Python/Pillow validation failed.' }
& $Godot --version
if ($LASTEXITCODE -ne 0) { throw 'Godot version check failed.' }
& $FFmpegExecutable -version *> (Join-Path $runtime 'ffmpeg-version.log')
if ($LASTEXITCODE -ne 0) { throw 'FFmpeg version check failed.' }
$manifest = [ordered]@{ lock_version=$lock.lock_version; platform=$lock.platform; python=$lock.python.version; pillow=$lock.pillow.version; ffmpeg_sha256=(Get-FileHash -LiteralPath $ffmpegDefault -Algorithm SHA256).Hash; installed_utc=[DateTime]::UtcNow.ToString('o') }
[IO.File]::WriteAllText((Join-Path $runtime 'installed.json'), ($manifest | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
if (-not $SkipImport) {
    & $Godot --headless --path $LabRoot --editor --import *> (Join-Path $runtime 'import.log')
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
    Assert-GodotLog (Join-Path $runtime 'import.log')
}
Write-Output "Portable runtime ready: $LabRoot"
