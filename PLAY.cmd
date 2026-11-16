@echo off
rem Opens the game. Needs Godot 4.7 or newer (the standard build, not .NET).
rem Godot is looked for in this order:
rem   1. the GODOT_EXE environment variable
rem   2. the path written in godot_path.txt, next to this file
rem   3. a Godot*.exe placed in this folder
rem   4. godot or godot4 on the PATH
rem If there is none, or the one found is older than 4.7, it offers to fetch
rem Godot from its official GitHub page into this folder.
rem There are no bracketed blocks in this file on purpose: a folder name with
rem brackets in it, such as "Tattletale-main (1)", must not break it.
setlocal
set "HERE=%~dp0"
set "URL=%GODOT_URL%"
if not defined URL set "URL=https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip"

if not exist "%HERE%project.godot" goto notunzipped
if not exist "%HERE%assets\" goto notunzipped

set "FROM=asked"
set "G=%GODOT_EXE%"
if not defined G if exist "%HERE%godot_path.txt" set /p G=<"%HERE%godot_path.txt"
if defined G set "G=%G:"=%"
if not defined G set "FROM=found"
if not defined G for %%F in ("%HERE%Godot*.exe") do if not defined G set "G=%%~fF"
if "%FROM%"=="found" if defined G set "G=%G:_console.exe=.exe%"
if not defined G for %%F in (godot.exe godot4.exe) do if not defined G set "G=%%~$PATH:F"
if not defined G goto nogodot
rem A bare name such as "godot" is looked up on the PATH.
if not exist "%G%" for %%F in ("%G%" "%G%.exe") do if not "%%~$PATH:F"=="" set "G=%%~$PATH:F"
if not exist "%G%" goto nogodot

rem Which version is it? (Nothing read: go on and let Godot say so itself.)
set "V="
call "%G%" --version >"%HERE%godot_version.tmp" 2>nul
if exist "%HERE%godot_version.tmp" set /p V=<"%HERE%godot_version.tmp"
del "%HERE%godot_version.tmp" >nul 2>&1
set "MAJOR="
set "MINOR="
if defined V for /f "tokens=1,2 delims=." %%A in ("%V%") do set "MAJOR=%%A"& set "MINOR=%%B"
set "OLD="
if defined MINOR if 1%MAJOR% LSS 14 set "OLD=1"
if defined MINOR if "%MAJOR%"=="4" if 1%MINOR% LSS 17 set "OLD=1"
if defined OLD goto oldgodot

:ready
rem "PLAY.cmd where" only says which Godot would be used.
if /i "%~1"=="where" echo %G%& exit /b 0

rem Bring in any art that is new or changed, then open the game. Without this the game has no pictures.
echo Getting the art ready. The first time this takes a minute or two and
echo nothing shows meanwhile; the game opens by itself when it is done...
start "" /wait "%G%" --headless --path "%HERE%." --import
if not exist "%HERE%.godot\imported\" goto noimport
start "" "%G%" --path "%HERE%."
exit /b 0

:notunzipped
echo.
echo The game's files are not next to PLAY.cmd.
echo If you opened this from inside the downloaded ZIP: close it, right-click the
echo ZIP, choose Extract All, and run PLAY.cmd from the folder that makes.
echo.
pause
exit /b 1

:noimport
echo.
echo Godot ran but did not bring in the art, so the game cannot open.
echo Godot used: %G%
echo Try: open Godot yourself, choose Import, pick project.godot in this folder,
echo wait until the bar at the bottom finishes, and press F5.
echo.
pause
exit /b 1

:oldgodot
echo.
echo The Godot found is version %V%
echo   %G%
echo This game needs Godot 4.7 or newer.
if "%FROM%"=="asked" echo That one was named in GODOT_EXE or godot_path.txt: point it at a newer Godot.
if "%FROM%"=="asked" goto manual
goto offer

:nogodot
echo.
if defined G echo Godot was not found at: %G%
if not defined G echo Godot was not found on this computer.
echo This game runs in Godot 4.7 or newer, a free game engine.

:offer
echo.
echo PLAY.cmd can fetch Godot 4.7.2 for you: about 86 MB, from Godot's official
echo GitHub page, into this folder only. Nothing is installed.
echo   %URL%
echo.
choice /c YN /n /m "Download it now? [Y/N] "
if errorlevel 2 goto manual
echo.
echo Downloading Godot...
"%SystemRoot%\System32\curl.exe" -L --fail -o "%HERE%godot_download.zip" "%URL%"
if errorlevel 1 goto failed
"%SystemRoot%\System32\tar.exe" -xf "%HERE%godot_download.zip" -C "%HERE%."
if errorlevel 1 goto failed
del "%HERE%godot_download.zip" >nul 2>&1
set "G="
for %%F in ("%HERE%Godot*.exe") do if not defined G set "G=%%~fF"
if not defined G goto failed
set "G=%G:_console.exe=.exe%"
if not exist "%G%" goto failed
echo Godot is in this folder now.
echo.
goto ready

:failed
del "%HERE%godot_download.zip" >nul 2>&1
echo.
echo The download did not work.

:manual
echo.
echo Get Godot 4.7 or newer, the standard build (not .NET), from
echo   https://godotengine.org/download
echo Then do one of these and run PLAY.cmd again:
echo   - put the Godot .exe in this folder, or
echo   - write its full path in a file named godot_path.txt in this folder, or
echo   - open Godot yourself, choose Import, pick project.godot here, and press F5.
echo.
pause
exit /b 1
