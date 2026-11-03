@rem linux-compat: find the GNU tools (Git for Windows, MSYS2, Cygwin, Scoop) and set LC_GNU.
@rem LC_GNU=none means native only. Same search order as lib\common.ps1.
@if exist "%~dp0..\state\nognu" (set "LC_GNU=none" & exit /b 0)
@if defined LC_GNU if exist "%LC_GNU%\ls.exe" exit /b 0
@for %%D in ("%ProgramFiles%\Git\usr\bin" "%ProgramFiles(x86)%\Git\usr\bin" "%LOCALAPPDATA%\Programs\Git\usr\bin" "%USERPROFILE%\scoop\apps\git\current\usr\bin" "C:\msys64\usr\bin" "C:\cygwin64\bin") do @if exist "%%~D\ls.exe" (set "LC_GNU=%%~D" & exit /b 0)
@for /f "delims=" %%G in ('where git.exe 2^>nul') do @if exist "%%~dpG..\usr\bin\ls.exe" (for %%U in ("%%~dpG..\usr\bin") do @set "LC_GNU=%%~fU") & exit /b 0
@set "LC_GNU=none"
@exit /b 0
