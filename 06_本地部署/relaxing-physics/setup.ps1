# Recreate the isolated runtime without writing dependencies to the system disk.
param([switch]$Dev)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$env:UV_CACHE_DIR = Join-Path $projectRoot '.cache/uv'
$env:UV_PYTHON_INSTALL_DIR = Join-Path $projectRoot '.runtime/python'
$env:PYTHONPYCACHEPREFIX = Join-Path $projectRoot '.cache/pycache'
$env:TEMP = Join-Path $projectRoot '.cache/tmp'
$env:TMP = $env:TEMP
New-Item -ItemType Directory -Force -Path $env:UV_CACHE_DIR,$env:UV_PYTHON_INSTALL_DIR,$env:PYTHONPYCACHEPREFIX,$env:TEMP | Out-Null
uv --no-config python install 3.12.13 --no-bin --no-registry
if ($LASTEXITCODE -ne 0) { throw 'Python installation failed.' }
$pythonRuntime = Get-ChildItem -LiteralPath $env:UV_PYTHON_INSTALL_DIR -Directory | Where-Object Name -Like 'cpython-3.12*' | Select-Object -First 1
$pythonExe = Join-Path $pythonRuntime.FullName 'python.exe'
if (-not (Test-Path -LiteralPath '.venv/Scripts/python.exe')) {
    uv --no-config venv --python $pythonExe --no-python-downloads '.venv'
    if ($LASTEXITCODE -ne 0) { throw 'Virtual environment creation failed.' }
}
$requirementsFile = if (Test-Path -LiteralPath 'requirements.lock') { 'requirements.lock' } else { 'requirements.txt' }
uv --no-config pip install --python '.venv/Scripts/python.exe' -r $requirementsFile
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
if ($Dev) {
    uv --no-config pip install --python '.venv/Scripts/python.exe' -r requirements-dev.txt
    if ($LASTEXITCODE -ne 0) { throw 'Development tools installation failed.' }
}
Write-Host 'Installed. Runtime, environment and cache are inside this project.'
