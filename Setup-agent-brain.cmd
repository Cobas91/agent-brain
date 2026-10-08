@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-AgentBrain.ps1" -Gui
if errorlevel 1 pause
