$ErrorActionPreference = "Stop"
& "$PSScriptRoot\build_windows.ps1"
& "$PSScriptRoot\build_android.ps1"
& "$PSScriptRoot\build_web.ps1"
