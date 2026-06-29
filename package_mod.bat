@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
python "%SCRIPT_DIR%\devtools\build_mod_zip.py"
if errorlevel 1 (
    echo Packaging failed.
    exit /b 1
)

endlocal
