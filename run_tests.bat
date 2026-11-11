@echo off
rem Run Godot headless: import, then smoke test. Logs go to tests\*.log
rem Set GODOT to your Godot console exe if it is not in ..\Godot\
cd /d "%~dp0"
if "%GODOT%"=="" set GODOT=%~dp0..\Godot\Godot_v4.7.1-stable_win64_console.exe
"%GODOT%" --headless --path "%~dp0." --import > tests\import.log 2>&1
"%GODOT%" --headless --fixed-fps 60 --path "%~dp0." res://tests/Smoke.tscn > tests\smoke.log 2>&1
echo exit=%ERRORLEVEL% >> tests\smoke.log
echo DONE > tests\finished.txt
