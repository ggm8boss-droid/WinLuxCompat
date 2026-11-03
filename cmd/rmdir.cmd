@echo off
rem rmdir -p / -v / --ignore-fail-on-non-empty -> GNU rmdir; anything else (incl. /s /q) -> cmd's own rmdir.
set "_lc_a=%~1"
if "%_lc_a:~0,1%"=="-" (set "_lc_a=" & call "%~dp0..\bin\rmdir.cmd" %* & exit /b)
set "_lc_a="
rmdir %*
