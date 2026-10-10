@echo off
rem Compiles light_punk_pink.qc into ..\..\content\models\player\light_punk_pink.* (mdl, vvd, dx90/dx80/sw.vtx, phy).
rem Usage: build.bat [path\to\studiomdl.exe]   (or set STUDIOMDL)
rem   default: Steam's "Source SDK Base 2013 Multiplayer\bin\studiomdl.exe" (MDL v48, as Dystopia's player models)
rem   optional: set DYSTOPIA=<...\common\Dystopia\dystopia> so studiomdl also finds the stock materials (fewer warnings)
rem studiomdl writes into a throw-away game folder in %TEMP% (a minimal gameinfo.txt that reads the materials from
rem ..\..\content); the six model files are then copied to content\models\player\. Nothing else is touched.
setlocal
set HERE=%~dp0
for %%I in ("%HERE%..\..\content") do set CONTENT=%%~fI
if not "%~1"=="" set STUDIOMDL=%~1
if "%STUDIOMDL%"=="" set "STUDIOMDL=%ProgramFiles(x86)%\Steam\steamapps\common\Source SDK Base 2013 Multiplayer\bin\studiomdl.exe"
if not exist "%STUDIOMDL%" (echo studiomdl.exe not found: pass its path or set STUDIOMDL & exit /b 1)

set GAME=%TEMP%\dys_hats_light_punk_pink
if exist "%GAME%" rmdir /s /q "%GAME%"
mkdir "%GAME%"
set GI=%GAME%\gameinfo.txt
set CONTENT_FS=%CONTENT:\=/%
> "%GI%" echo "GameInfo"
>>"%GI%" echo {
>>"%GI%" echo 	game	"light_punk_pink build"
>>"%GI%" echo 	type	multiplayer_only
>>"%GI%" echo 	FileSystem
>>"%GI%" echo 	{
>>"%GI%" echo 		SteamAppId	243750
>>"%GI%" echo 		SearchPaths
>>"%GI%" echo 		{
>>"%GI%" echo 			game+mod+mod_write+default_write_path	^|gameinfo_path^|.
>>"%GI%" echo 			game	"%CONTENT_FS%"
if not "%DYSTOPIA%"=="" >>"%GI%" echo 			game	"%DYSTOPIA:\=/%"
>>"%GI%" echo 		}
>>"%GI%" echo 	}
>>"%GI%" echo }

pushd "%HERE%"
"%STUDIOMDL%" -nop4 -nopause -game "%GAME%" light_punk_pink.qc
set RC=%errorlevel%
popd
if not "%RC%"=="0" (echo studiomdl failed, exit code %RC% & exit /b %RC%)
if not exist "%GAME%\models\player\light_punk_pink.mdl" (echo studiomdl wrote no model & exit /b 1)

if not exist "%CONTENT%\models\player" mkdir "%CONTENT%\models\player"
for %%E in (mdl vvd dx90.vtx dx80.vtx sw.vtx phy) do (
	copy /y "%GAME%\models\player\light_punk_pink.%%E" "%CONTENT%\models\player\" >nul || (echo missing light_punk_pink.%%E & exit /b 1)
)
rmdir /s /q "%GAME%"
echo Wrote %CONTENT%\models\player\light_punk_pink.*
exit /b 0
