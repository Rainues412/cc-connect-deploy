@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\coding\cc-connect-deploy\startup\start-cc-connect.ps1"
exit /b %errorlevel%
