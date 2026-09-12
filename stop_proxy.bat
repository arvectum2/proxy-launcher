@echo off
cd /d "%~dp0"
set "INSTALLED_EXE=%LOCALAPPDATA%\Programs\ArvectumProxyLauncher\Arvectum Proxy Launcher.exe"
set "LEGACY_EXE=%USERPROFILE%\Documents\ArvectumProxyLauncher\Arvectum Proxy Launcher.exe"
if exist "%INSTALLED_EXE%" (
    "%INSTALLED_EXE%" --stop
) else if exist "%LEGACY_EXE%" (
    "%LEGACY_EXE%" --stop
) else if exist "%~dp0Arvectum Proxy Launcher.exe" (
    "%~dp0Arvectum Proxy Launcher.exe" --stop
) else if exist "%~dp0ProxyLauncher.exe" (
    "%~dp0ProxyLauncher.exe" --stop
) else (
    where python >nul 2>nul
    if not errorlevel 1 (
        python.exe "%~dp0proxy_core.py" --stop
    ) else (
        echo Arvectum Proxy Launcher.exe / Python not found.
        pause
        exit /b 1
    )
)
