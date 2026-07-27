# cc-connect 一键安装脚本
# 用法: .\scripts\setup.ps1
# 需要管理员权限运行

param(
    [string]$ConfigDir = "$env:USERPROFILE\.claude\skills\cc-connect",
    [string]$MonitorScript = "$PSScriptRoot\..\monitor\token-monitor.ps1",
    [string]$StartupBat = "$PSScriptRoot\..\startup\pm2-cc-connect.bat"
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host ""
    Write-Host "[$Step] $Message" -ForegroundColor Cyan
    Write-Host ("-" * 50) -ForegroundColor DarkGray
}

function Write-OK {
    param([string]$Message)
    Write-Host "  OK: $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  WARN: $Message" -ForegroundColor Yellow
}

# ========================================
# 开始安装
# ========================================

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " cc-connect 微信双账号自动部署" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# ---------- Step 1: 检查 Node.js ----------
Write-Step "1/8" "检查 Node.js 环境"

try {
    $nodeVer = node --version 2>$null
    $npmVer = npm --version 2>$null
    Write-OK "Node.js $nodeVer, npm $npmVer"
} catch {
    Write-Host "  ERROR: 未找到 Node.js，请先安装 Node.js >= 18" -ForegroundColor Red
    Write-Host "  下载地址: https://nodejs.org/" -ForegroundColor Red
    exit 1
}

# ---------- Step 2: 安装 cc-connect ----------
Write-Step "2/8" "安装 cc-connect"

$ccPath = (npm list -g cc-connect 2>$null)
if ($ccPath -match "cc-connect") {
    Write-OK "cc-connect 已安装"
} else {
    Write-Host "  正在安装 cc-connect..."
    npm install -g cc-connect 2>&1 | Out-Null
    Write-OK "cc-connect 安装完成"
}

# ---------- Step 3: 安装 pm2 ----------
Write-Step "3/8" "安装 pm2"

$pm2Path = (npm list -g pm2 2>$null)
if ($pm2Path -match "pm2") {
    Write-OK "pm2 已安装"
} else {
    Write-Host "  正在安装 pm2..."
    npm install -g pm2 2>&1 | Out-Null
    Write-OK "pm2 安装完成"
}

# ---------- Step 4: 创建配置目录并复制配置文件 ----------
Write-Step "4/8" "创建配置文件"

if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

$configFile = Join-Path $ConfigDir "config.toml"
$exampleConfig = Join-Path $PSScriptRoot "..\config.example.toml"

if (Test-Path $configFile) {
    Write-Warn "config.toml 已存在，跳过覆盖"
} elseif (Test-Path $exampleConfig) {
    Copy-Item $exampleConfig $configFile
    Write-OK "已复制 config.example.toml -> config.toml"
} else {
    Write-Warn "未找到 config.example.toml，请手动创建配置文件"
}

# ---------- Step 5: 扫码绑定微信 1 ----------
Write-Step "5/8" "绑定微信 1 (wechat-claude)"

Write-Host "  正在生成二维码，请用微信扫码..." -ForegroundColor Yellow
Write-Host ""

$ccBin = Join-Path (npm root -g) "cc-connect\bin\cc-connect.exe"
if (Test-Path $ccBin) {
    & $ccBin weixin setup --project "wechat-claude" --config $configFile
} else {
    cc-connect weixin setup --project "wechat-claude" --config $configFile
}

if ($LASTEXITCODE -eq 0) {
    Write-OK "微信 1 绑定成功"
} else {
    Write-Warn "微信 1 绑定失败，稍后可手动执行: cc-connect weixin setup --project wechat-claude --config $configFile"
}

# ---------- Step 6: 扫码绑定微信 2 ----------
Write-Step "6/8" "绑定微信 2 (wechat-claude-2)"

$skip2 = ""
Read-Host "  是否绑定第二个微信？(Y/n)" | ForEach-Object { $skip2 = $_ }

if ($skip2 -ne "n" -and $skip2 -ne "N") {
    Write-Host "  正在生成二维码，请用微信扫码..." -ForegroundColor Yellow
    Write-Host ""

    if (Test-Path $ccBin) {
        & $ccBin weixin setup --project "wechat-claude-2" --config $configFile
    } else {
        cc-connect weixin setup --project "wechat-claude-2" --config $configFile
    }

    if ($LASTEXITCODE -eq 0) {
        Write-OK "微信 2 绑定成功"
    } else {
        Write-Warn "微信 2 绑定失败，稍后可手动执行: cc-connect weixin setup --project wechat-claude-2 --config $configFile"
    }
} else {
    Write-Host "  跳过微信 2 绑定" -ForegroundColor DarkGray
}

# ---------- Step 7: 启动 pm2 守护进程 ----------
Write-Step "7/8" "启动 pm2 守护进程"

# 清理已有的 wechat 进程
pm2 delete wechat 2>$null | Out-Null

if (Test-Path $ccBin) {
    pm2 start $ccBin --name wechat -- --config $configFile 2>&1 | Out-Null
} else {
    pm2 start "cc-connect" --name wechat -- --config $configFile 2>&1 | Out-Null
}

Start-Sleep -Seconds 3
pm2 save 2>&1 | Out-Null

$status = pm2 jlist 2>$null | ConvertFrom-Json
if ($status -and $status[0].pm2_env.status -eq "online") {
    Write-OK "cc-connect 已通过 pm2 启动 (PID: $($status[0].pid))"
} else {
    Write-Warn "cc-connect 启动可能失败，请运行 pm2 logs wechat 检查"
}

# ---------- Step 8: 配置开机自启 ----------
Write-Step "8/8" "配置开机自启"

$startupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$startupFile = Join-Path $startupDir "pm2-cc-connect.bat"

if (Test-Path $StartupBat) {
    Copy-Item $StartupBat $startupFile -Force
    Write-OK "开机自启脚本已复制到 $startupFile"
} else {
    # 自动生成
    $batContent = @"
@echo off
cd /d $env:USERPROFILE

:: 1. 恢复 pm2 守护进程
call pm2 resurrect
if errorlevel 1 (
    pm2 start "cc-connect" --name wechat -- --config "$configFile"
)

:: 2. 后台启动 token 过期监控
start "cc-connect-monitor" /MIN powershell -ExecutionPolicy Bypass -File "$MonitorScript"
"@
    $batContent | Out-File -FilePath $startupFile -Encoding ASCII
    Write-OK "已生成开机自启脚本"
}

# 复制监控脚本到配置目录
$monitorDest = Join-Path $ConfigDir "token-monitor.ps1"
if (Test-Path $MonitorScript) {
    Copy-Item $MonitorScript $monitorDest -Force
    Write-OK "监控脚本已复制到 $monitorDest"
}

# ========================================
# 完成
# ========================================

Write-Host ""
Write-Host "=====================================" -ForegroundColor Green
Write-Host " 安装完成！" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host ""
Write-Host "  常用命令:" -ForegroundColor White
Write-Host "    pm2 status          # 查看运行状态"
Write-Host "    pm2 logs wechat     # 查看实时日志"
Write-Host "    pm2 restart wechat  # 重启"
Write-Host ""
Write-Host "  配置文件: $configFile" -ForegroundColor White
Write-Host "  监控脚本: $monitorDest" -ForegroundColor White
Write-Host ""
