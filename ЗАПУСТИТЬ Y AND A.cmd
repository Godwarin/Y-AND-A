@echo off
setlocal
set "YANDA_APP=%~dp0release\BETA-0.42\Windows\Y AND A.exe"
if not exist "%YANDA_APP%" (
 echo BETA-0.42 executable was not found. See README.md.
 pause
 exit /b 1
)
start "" /D "%~dp0release\BETA-0.42\Windows" "%YANDA_APP%"
