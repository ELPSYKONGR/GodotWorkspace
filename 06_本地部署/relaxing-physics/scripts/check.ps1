# Run project checks using the project-local environment and cache.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$env:PYTHONPYCACHEPREFIX = Join-Path $projectRoot '.cache/pycache'
$env:TEMP = Join-Path $projectRoot '.cache/tmp'
$env:TMP = $env:TEMP
& '.venv/Scripts/python.exe' -B -m unittest discover -s tests -v
if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
& '.venv/Scripts/ruff.exe' check src tests
if ($LASTEXITCODE -ne 0) { throw 'Lint failed.' }
& '.venv/Scripts/pip-audit.exe' --cache-dir .cache/pip-audit --disable-pip --no-deps -r requirements.lock
if ($LASTEXITCODE -ne 0) { throw 'Dependency audit failed; inspect its report.' }
