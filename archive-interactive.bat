@echo off
echo.
echo   4chan Thread Archiver
echo   ====================
echo.
echo   Paste a 4chan thread URL and press Enter.
echo   Type "exit" or "q" to quit.
echo.

:loop
set /p "url=URL: "
if "%url%"=="exit" goto :eof
if "%url%"=="q" goto :eof
if "%url%"=="" goto :loop

powershell -ExecutionPolicy Bypass -File "%~dp0archive.ps1" "%url%"
echo.
goto :loop
