@echo off
setlocal EnableExtensions

set "MOD_NAME=oarc-rx"
set "MOD_VERSION=2.0.0"
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "BUILD_DIR=%SCRIPT_DIR%\build"
set "ZIP_NAME=%MOD_NAME%_%MOD_VERSION%.zip"
set "MOD_FOLDER=%MOD_NAME%_%MOD_VERSION%"
set "STAGE_DIR=%BUILD_DIR%\%MOD_FOLDER%"
set "ZIP_PATH=%BUILD_DIR%\%ZIP_NAME%"
set "MODS_DIR=%APPDATA%\Factorio\mods"

echo Packaging %MOD_NAME% %MOD_VERSION%

if not exist "%MODS_DIR%" (
    echo Factorio mods directory not found:
    echo   %MODS_DIR%
    exit /b 1
)

if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%"
mkdir "%STAGE_DIR%" >nul 2>&1
if errorlevel 1 (
    echo Failed to create build directory.
    exit /b 1
)

echo Copying files into staging folder...
robocopy "%SCRIPT_DIR%" "%STAGE_DIR%" /E /XD ".git" ".vscode" "build" >nul
set "ROBOCOPY_EXIT=%ERRORLEVEL%"
if %ROBOCOPY_EXIT% GEQ 8 (
    echo Failed to copy files. Robocopy exit code: %ROBOCOPY_EXIT%
    exit /b 1
)

if exist "%ZIP_PATH%" del /f /q "%ZIP_PATH%"

echo Creating zip...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Compress-Archive -Path '%STAGE_DIR%' -DestinationPath '%ZIP_PATH%' -Force"
if errorlevel 1 (
    echo Failed to create zip archive.
    exit /b 1
)

echo Copying zip to Factorio mods folder...
copy /y "%ZIP_PATH%" "%MODS_DIR%\%ZIP_NAME%" >nul
if errorlevel 1 (
    echo Failed to copy zip to mods folder.
    exit /b 1
)

echo Done.
echo   Zip:  %ZIP_PATH%
echo   Mods: %MODS_DIR%\%ZIP_NAME%

endlocal
