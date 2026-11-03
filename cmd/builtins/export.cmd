@echo off
rem export NAME=value (cmd variables are always exported). $VARS, ~ and PATH-style a:b lists are
rem translated by lib\run.ps1, which prints the `set` lines this runs.
if "%~1"=="" (set & exit /b 0)
if "%~1"=="-p" (set & exit /b 0)
for /f "usebackq delims=" %%L in (`""%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\lib\run.ps1" _lc_cmd_export %*"`) do %%L
