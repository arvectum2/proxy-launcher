@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
if not defined ARVECTUM_APP_DIR set "ARVECTUM_APP_DIR=%LOCALAPPDATA%\Programs\ArvectumProxyLauncher"
set "INSTALLED_EXE=%ARVECTUM_APP_DIR%\Arvectum Proxy Launcher.exe"
set "LEGACY_EXE=%USERPROFILE%\Documents\ArvectumProxyLauncher\Arvectum Proxy Launcher.exe"
set "RC=1"
title Arvectum Proxy Launcher - Restore Network
echo Restoring previous Windows proxy settings...

if exist "%INSTALLED_EXE%" (
    "%INSTALLED_EXE%" --rollback
    set "RC=!ERRORLEVEL!"
) else if exist "%LEGACY_EXE%" (
    "%LEGACY_EXE%" --rollback
    set "RC=!ERRORLEVEL!"
) else if exist "%~dp0Arvectum Proxy Launcher.exe" (
    "%~dp0Arvectum Proxy Launcher.exe" --rollback
    set "RC=!ERRORLEVEL!"
) else if exist "%~dp0dist\Arvectum Proxy Launcher.exe" (
    "%~dp0dist\Arvectum Proxy Launcher.exe" --rollback
    set "RC=!ERRORLEVEL!"
) else if exist "%~dp0proxy_core.py" (
    where python >nul 2>nul
    if errorlevel 1 (
        echo Python not found.
        set "RC=1"
    ) else (
        python.exe "%~dp0proxy_core.py" --rollback
        set "RC=!ERRORLEVEL!"
    )
) else (
    echo Application not found.
    set "RC=1"
)

echo.
if not "%RC%"=="0" (
    echo ERROR: network restore is incomplete.
    echo Do NOT delete the Arvectum state/install folders yet.
    echo Retry this command and inspect proxy_core.log.
    pause
    endlocal & exit /b 1
)

echo Network settings restored successfully.
pause
endlocal & exit /b 0
