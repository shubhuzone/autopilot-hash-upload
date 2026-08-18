@echo off
REM ============================================================
REM Autopilot Hardware Hash Upload - Cloud Wrapper
REM Run from OOBE (Shift+F10): downloads the PS1 from cloud, then runs it.
REM Usage at OOBE cmd prompt:
REM    curl -o run.bat https://<yourhost>/run.bat && run.bat
REM (or place this .bat itself on the cloud host and download it first)
REM ============================================================

setlocal

if not exist "C:\Temp" mkdir "C:\Temp"
cd /d C:\Temp

REM --- EDIT THIS: direct HTTPS link to the raw .ps1 file ---
set SCRIPT_URL=https://raw.githubusercontent.com/shubhuzone/autopilot-hash-upload/main/Upload-AutopilotHash-Interactive.ps1

set TEMPDIR=C:\Temp\AutopilotUpload
set SCRIPT=%TEMPDIR%\Upload-AutopilotHash-Interactive.ps1

if not exist "%TEMPDIR%" mkdir "%TEMPDIR%"

echo ============================================
echo  Windows Autopilot Hash Upload (Cloud)
echo ============================================
echo.
echo Downloading script...
curl.exe -sSL "%SCRIPT_URL%" -o "%SCRIPT%"

if not exist "%SCRIPT%" (
    echo Download failed. Check network / URL and try again.
    pause
    exit /b 1
)

set /p GTAG=Enter Group Tag (or leave blank): 

echo.
echo Running upload script - sign in with your admin IDP when prompted...
echo.

if "%GTAG%"=="" (
    powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT%" -RestartAfter
) else (
    powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT%" -GroupTag "%GTAG%" -RestartAfter
)

echo.
echo Done. Check %ProgramData%\AutopilotUpload\upload.log for details if needed.
pause
endlocal
