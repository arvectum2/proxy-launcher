@echo off
cd /d "%~dp0"
windivert_nat_probe.exe "%~dp0loopback_smoke.exe" 38180 38181 12 > probe.log 2> probe.err
exit /b %errorlevel%
