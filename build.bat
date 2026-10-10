@echo off
rem Builds plugins\dys_hats.smx and plugins\dys_girl.smx with SourceMod's spcomp (1.11 or newer).
rem Usage: build.bat [path\to\spcomp.exe]   (or set SPCOMP; default: spcomp.exe from PATH)
rem Uses scripting\include if it exists, else the include folder next to spcomp.exe.
setlocal
set ROOT=%~dp0
if not "%~1"=="" set SPCOMP=%~1
if "%SPCOMP%"=="" set SPCOMP=spcomp.exe
for %%I in ("%SPCOMP%") do set SPDIR=%%~dp$PATH:I
if "%SPDIR%"=="" for %%I in ("%SPCOMP%") do set SPDIR=%%~dpI
for %%I in ("%SPCOMP%") do if exist "%%~fI" set SPCOMP=%%~fI
set INC=%SPDIR%include
if exist "%ROOT%scripting\include\sourcemod.inc" set INC=include
if not exist "%ROOT%plugins" mkdir "%ROOT%plugins"
pushd "%ROOT%scripting"
if not exist "%INC%\sourcemod.inc" (echo spcomp.exe not found: pass its path or set SPCOMP & popd & exit /b 1)
set RC=0
for %%P in (dys_hats dys_girl) do (
	"%SPCOMP%" %%P.sp -i"%INC%" -o..\plugins\%%P.smx
	if errorlevel 1 set RC=1
)
popd
exit /b %RC%
