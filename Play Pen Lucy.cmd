@echo off
setlocal
set "GODOT_BIN="
if defined GODOT_EXE if exist "%GODOT_EXE%" set "GODOT_BIN=%GODOT_EXE%"
if not defined GODOT_BIN for %%G in (godot.exe godot4.exe) do for /f "delims=" %%P in ('where %%G 2^>nul') do if not defined GODOT_BIN set "GODOT_BIN=%%P"
rem Keep the original workstation installation as a fallback.
if not defined GODOT_BIN if exist "C:\files\Godot\Godot_v4.7.2-stable_win64.exe" set "GODOT_BIN=C:\files\Godot\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT_BIN (
    echo Install Godot 4.7 or newer and add godot.exe to PATH,
    echo or set GODOT_EXE to the full path to its executable.
    pause
    exit /b 1
)
set "APPDATA=%~dp0.work\play-profile"
if not exist "%APPDATA%" mkdir "%APPDATA%"
rem Incremental import also picks up changed assets after a git pull.
"%GODOT_BIN%" --headless --editor --import --quit --path "%~dp0godot" --log-file "%~dp0.work\import.log" >nul 2>&1
if errorlevel 1 (
    echo Asset import failed. See .work\import.log for details.
    pause
    exit /b 1
)
"%GODOT_BIN%" --maximized --path "%~dp0godot" --log-file "%~dp0.work\playable.log" res://scenes/city/pen_lucy.tscn
