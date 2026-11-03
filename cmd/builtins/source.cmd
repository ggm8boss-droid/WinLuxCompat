@echo off
rem source FILE: .cmd/.bat files are run in this cmd; a bash rc file (.bashrc, .bash_aliases) has its
rem alias and export lines applied, the rest is skipped.
if "%~1"=="" (echo source: filename argument required 1>&2 & exit /b 2)
set "_lc_f=%~1"
if "%_lc_f:~0,2%"=="~/" set "_lc_f=%USERPROFILE%\%_lc_f:~2%"
if "%_lc_f:~0,2%"=="~\" set "_lc_f=%USERPROFILE%\%_lc_f:~2%"
if not exist "%_lc_f%" (echo source: %_lc_f%: No such file or directory 1>&2 & set "_lc_f=" & exit /b 1)
if /i "%~x1"==".cmd" (call "%_lc_f%" & set "_lc_f=" & exit /b)
if /i "%~x1"==".bat" (call "%_lc_f%" & set "_lc_f=" & exit /b)
for /f "usebackq tokens=1*" %%a in (`findstr /r /b /c:"alias " /c:"export " "%_lc_f%"`) do call "%~dp0%%a.cmd" %%b
set "_lc_f="
