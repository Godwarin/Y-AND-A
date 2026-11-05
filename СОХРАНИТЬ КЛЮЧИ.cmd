@echo off
setlocal
set "YANDA_PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not exist "%YANDA_PWSH%" set "YANDA_PWSH=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe"
if not exist "%YANDA_PWSH%" (
  echo PowerShell 7 was not found. Please report this message to the developer.
  pause
  exit /b 1
)
set "YANDA_BACKUP_SCRIPT=%~dp0scripts\backup-android-signing.ps1"
if /I "%~1"=="--self-test" set "YANDA_BACKUP_SCRIPT=%~dp0scripts\test-signing-backup.ps1"
"%YANDA_PWSH%" -NoProfile -ExecutionPolicy RemoteSigned -File "%YANDA_BACKUP_SCRIPT%"
set "YANDA_BACKUP_EXIT=%ERRORLEVEL%"
if /I "%~1"=="--self-test" exit /b %YANDA_BACKUP_EXIT%
echo.
pause
