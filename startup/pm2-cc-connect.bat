@echo off
cd /d %USERPROFILE%

:: 1. 恢复 pm2 守护进程（cc-connect）
call pm2 resurrect
if errorlevel 1 (
    pm2 start "cc-connect" --name wechat -- --config "%USERPROFILE%\.claude\skills\cc-connect\config.toml"
)

:: 2. 后台启动 token 过期监控（自动弹窗提醒扫码，窗口最小化）
start "cc-connect-monitor" /MIN powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\.claude\skills\cc-connect\token-monitor.ps1"
