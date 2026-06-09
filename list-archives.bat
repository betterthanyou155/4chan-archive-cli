@echo off
setlocal

set "archiveDir=%~dp0archives"

if not exist "%archiveDir%" (
    echo No archives found.
    pause
    exit /b 0
)

echo.
echo   Archived Threads
echo   ================
echo.

for /d %%D in ("%archiveDir%\*") do (
    set "folder=%%~nxD"
    set "htmlFile=%%D\thread.html"
    if exist "%%D\thread.html" (
        set /a imgCount=0
        for %%F in ("%%D\images\*") do set /a imgCount+=1
        echo   %%~nxD  [!imgCount! files]
    )
)

echo.
pause
