@echo off
rem `date` prints the date like Linux (GNU date). Windows' `date /t` and `date /?` still work.
rem (No `call` for GNU date: call would expand the % in `date +%Y` a second time.)
set "_lc_a=%~1"
if "%_lc_a:~0,1%"=="/" (set "_lc_a=" & date %* & exit /b)
set "_lc_a="
"%~dp0..\bin\date.cmd" %*
