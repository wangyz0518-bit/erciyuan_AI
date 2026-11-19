@echo off
pwsh -NoProfile -File "%~dp0run.ps1"
if errorlevel 1 pause
