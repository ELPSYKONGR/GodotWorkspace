param(
    [int[]]$Seeds = @(42, 73, 103),
    [ValidateSet(360, 540, 720, 1080)][int]$Width = 720,
    [ValidateSet('multiply', 'escape', 'rain')][string]$Preset = 'multiply'
)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$env:PYTHONPYCACHEPREFIX = Join-Path $PSScriptRoot '.cache/pycache'
$env:TEMP = Join-Path $PSScriptRoot '.cache/tmp'
$env:TMP = $env:TEMP
foreach ($seed in $Seeds) {
    & '.venv/Scripts/python.exe' -B -m src.cli render --preset $Preset --seed $seed --width $Width --output "outputs/batch/${Preset}_seed_$seed"
    if ($LASTEXITCODE -ne 0) { throw "Seed $seed failed. Check its output log." }
}
Write-Host 'Batch complete. See outputs/batch.'
