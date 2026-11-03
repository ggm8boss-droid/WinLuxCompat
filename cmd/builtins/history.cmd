@echo off
rem history [N] / history -c
if "%~1"=="-c" (doskey /reinstall >nul & doskey /macrofile="%~dp0..\cmd\macros.doskey" & exit /b 0)
setlocal EnableDelayedExpansion
set /a _lc_n=0
for /f "delims=" %%h in ('doskey /history') do (set /a _lc_n+=1 & set "_lc_h!_lc_n!=%%h")
set /a _lc_from=1
if not "%~1"=="" set /a _lc_from=_lc_n-%~1+1
if !_lc_from! lss 1 set _lc_from=1
for /l %%i in (!_lc_from!,1,!_lc_n!) do (set "_lc_x=     %%i" & echo !_lc_x:~-5!  !_lc_h%%i!)
