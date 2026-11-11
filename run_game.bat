@echo off
rem Launch the game window. Set GODOT_GUI to your Godot exe if it is not in ..\Godot\
cd /d "%~dp0"
if "%GODOT_GUI%"=="" set GODOT_GUI=%~dp0..\Godot\Godot_v4.7.1-stable_win64.exe
start "" "%GODOT_GUI%" --path "%~dp0."
