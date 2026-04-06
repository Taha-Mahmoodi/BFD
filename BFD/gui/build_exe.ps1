[CmdletBinding()]
param(
    [string]$PythonExe = "python"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$venvDir = Join-Path $scriptDir ".venv"
$venvPython = Join-Path $venvDir "Scripts\python.exe"

if (-not (Test-Path -LiteralPath $venvPython)) {
    & $PythonExe -m venv $venvDir
}

& $venvPython -m pip install --upgrade pip
& $venvPython -m pip install -r (Join-Path $scriptDir "requirements.txt")

Push-Location $scriptDir
try {
    if (Test-Path -LiteralPath ".\build") { Remove-Item -LiteralPath ".\build" -Recurse -Force }
    if (Test-Path -LiteralPath ".\dist") { Remove-Item -LiteralPath ".\dist" -Recurse -Force }

    & $venvPython -m PyInstaller --noconfirm --clean BFD.spec
}
finally {
    Pop-Location
}

Write-Host ("Build completed: {0}" -f (Join-Path $scriptDir "dist\BFD.exe"))
