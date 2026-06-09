@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0update-html.ps1" %*
pause
