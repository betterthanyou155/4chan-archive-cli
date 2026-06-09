@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0archive.ps1" %*
pause
