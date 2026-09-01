@echo off
setlocal
cd /d "%~dp0\.."
echo R3.16.1 is the accepted source baseline for this release.
echo Redirecting to the current R3.17.0 Files/Attachments validation...
call tool\validate_r3170_windows.bat
exit /b %errorlevel%
