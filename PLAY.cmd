@echo off
rem Opens the game. Needs Godot 4.7 or newer (the standard build, not .NET).
rem Godot is looked for in this order:
rem   1. the GODOT_EXE environment variable
rem   2. the path written in godot_path.txt, next to this file
rem   3. a Godot*.exe placed in this folder
rem   4. godot or godot4 on the PATH
setlocal
set "G=%GODOT_EXE%"
if not defined G if exist "%~dp0godot_path.txt" set /p G=<"%~dp0godot_path.txt"
if defined G set "G=%G:"=%"
if not defined G for %%F in ("%~dp0Godot*.exe") do if not defined G set "G=%%~fF"
if not defined G for %%F in (godot.exe godot4.exe) do if not defined G set "G=%%~$PATH:F"
if not defined G goto nogodot
rem A bare name such as "godot" is looked up on the PATH.
if not exist "%G%" for %%F in ("%G%" "%G%.exe") do if not "%%~$PATH:F"=="" set "G=%%~$PATH:F"
if not exist "%G%" goto nogodot
rem "PLAY.cmd where" only says which Godot would be used.
if /i "%~1"=="where" echo %G%& exit /b 0

rem Bring in any art that is new or changed (about a minute the first time, a few
rem seconds after that), then open the game. Without this the game has no pictures.
echo Getting the art ready...
start "" /wait "%G%" --headless --path "%~dp0." --import
start "" "%G%" --path "%~dp0."
exit /b 0

:nogodot
echo.
if defined G echo Godot was not found at: %G%
if not defined G echo Godot was not found.
echo.
echo Get Godot 4.7 or newer, the standard build, from https://godotengine.org/download
echo Then do one of these and run PLAY.cmd again:
echo   - put the Godot .exe in this folder, or
echo   - write its full path in a file named godot_path.txt in this folder, or
echo   - open Godot yourself, choose Import, pick project.godot here, and press F5.
echo.
pause
exit /b 1
