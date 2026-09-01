$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $ProjectRoot
try {
    if (-not (Get-Command dart -ErrorAction SilentlyContinue)) {
        throw "Dart was not found in PATH. Run this from a Flutter terminal after installing/configuring Flutter."
    }
    dart run tool/verify_clean_platform.dart
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}
