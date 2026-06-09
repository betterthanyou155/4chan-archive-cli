@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0update-all.ps1" %*
pause
