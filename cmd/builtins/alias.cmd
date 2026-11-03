@echo off
rem alias name='command args' -> doskey macro (typed commands only, like bash aliases).
rem alias / alias -p lists them, alias name shows one.
setlocal EnableDelayedExpansion
set "_lc_a=%*"
if not defined _lc_a (doskey /macros & exit /b 0)
if "!_lc_a!"=="-p" (doskey /macros & exit /b 0)
for /f "tokens=1* delims==" %%a in ("!_lc_a!") do (set "_lc_n=%%a" & set "_lc_v=%%b")
if not defined _lc_v (doskey /macros | findstr /b /i /c:"!_lc_n!=" || (echo alias: !_lc_n!: not found 1>&2 & exit /b 1)) & exit /b 0
set "_lc_v=!_lc_v:'=!"
set "_lc_v=!_lc_v:"=!"
doskey !_lc_n!=!_lc_v! $*
