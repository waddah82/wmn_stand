$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $ProjectRoot
try {
    $cmakeCache = Join-Path $ProjectRoot "build\windows\x64\CMakeCache.txt"
    if (Test-Path $cmakeCache) {
        $cacheText = Get-Content $cmakeCache -Raw
        $normalizedRoot = $ProjectRoot.Replace('\', '/')
        if ($cacheText -notmatch [regex]::Escape($normalizedRoot)) {
            Write-Host "Removing stale Windows CMake cache from a previous project path..."
            Remove-Item (Join-Path $ProjectRoot "build\windows") -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "WMN Application Platform - creating Windows, Android and Web hosts"
    Write-Host "(iOS host creation/build should be performed on macOS.)"

    flutter create --project-name wmn_standalone --platforms=windows,android,web .

    $wasmPath = Join-Path $ProjectRoot "web\sqlite3.wasm"
    if (-not (Test-Path $wasmPath)) {
        Write-Host "Downloading sqlite3.wasm 3.5.2 for Web database support..."
        Invoke-WebRequest `
            -Uri "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.5.2/sqlite3.wasm" `
            -OutFile $wasmPath
    }

    flutter pub get
    dart run tool\verify_clean_platform.dart
    flutter analyze
    flutter test
    flutter doctor

    Write-Host "WMN platform bootstrap complete."
    Write-Host "Windows: flutter run -d windows"
    Write-Host "Web:     flutter run -d chrome"
    Write-Host "Android: flutter run -d <device-id>"
}
finally {
    Pop-Location
}
