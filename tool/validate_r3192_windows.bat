@echo off
setlocal
cd /d "%~dp0\.."
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set STAMP=%%i
set LOG=R3192_VALIDATION_%STAMP%.log

echo WMN R3.19.2 Structured Report Printing Validation > "%LOG%"
echo ============================================ >> "%LOG%"
echo. >> "%LOG%"

call flutter pub get >> "%LOG%" 2>&1
if errorlevel 1 goto :fail
call dart run tool\verify_clean_platform.dart >> "%LOG%" 2>&1
if errorlevel 1 goto :fail
call flutter analyze >> "%LOG%" 2>&1
if errorlevel 1 goto :fail
call flutter test >> "%LOG%" 2>&1
if errorlevel 1 goto :fail

echo. >> "%LOG%"
echo R3192_VALIDATION_PASS >> "%LOG%"
echo R3192_VALIDATION_PASS
echo Log: %CD%\%LOG%
exit /b 0

:fail
echo. >> "%LOG%"
echo R3192_VALIDATION_FAIL >> "%LOG%"
echo R3192_VALIDATION_FAIL
echo Log: %CD%\%LOG%
exit /b 1

