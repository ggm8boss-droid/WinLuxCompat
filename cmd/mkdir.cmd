@echo off
rem mkdir -p / -v / --parents -> GNU mkdir; anything else -> cmd's own mkdir (which already makes parents).
set "_lc_a=%~1"
if "%_lc_a:~0,1%"=="-" (set "_lc_a=" & call "%~dp0..\bin\mkdir.cmd" %* & exit /b)
set "_lc_a="
mkdir %*
