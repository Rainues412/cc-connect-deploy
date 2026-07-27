# 常见问题排查

## cc-connect 启动失败

### "another cc-connect instance is already running"

```bash
# 查找并杀掉残留进程
tasklist | findstr cc-connect
taskkill /PID <进程号> /F

# 或通过 pm2 强制启动
pm2 delete wechat
pm2 start "C:\Users\<你的用户名>\AppData\Roaming\npm\node_modules\cc-connect\bin\cc-connect.exe" --name wechat -- --config ~/.claude/skills/cc-connect/config.toml
```

### pm2 报 SyntaxError

Windows 下 pm2 直接调用 `cc-connect.cmd` 会报错，需要用 `.exe` 路径：

```bash
pm2 delete wechat
pm2 start "C:\Users\<你的用户名>\AppData\Roaming\npm\node_modules\cc-connect\bin\cc-connect.exe" --name wechat -- --config ~/.claude/skills/cc-connect/config.toml
pm2 save
```

## 微信连接断开

### 手动重新扫码

```bash
pm2 stop wechat
cc-connect weixin setup --project wechat-claude --config ~/.claude/skills/cc-connect/config.toml
pm2 restart wechat
```

### 检查 Token 状态

```bash
pm2 logs wechat --lines 50    # 查看最近 50 行日志
```

如果出现 `token expired`、`401`、`ilink error` 等关键词，说明需要重新扫码。

## API Error: 400

### 原因

用户发送空消息（如纯图片）时，cc-connect 会将 API 400 错误作为 assistant 回复存入历史，导致后续所有请求持续失败。

### 自动修复（推荐）

监控脚本 `token-monitor.ps1` 已内置自动修复：
- 检测到日志中的 `API Error: 400` 关键词
- 自动清空被污染的会话历史
- 弹窗通知 + 自动重启 cc-connect

无需手动干预。

### 手动修复

如果监控未运行：

```bash
# 1. 停止 cc-connect
pm2 stop wechat

# 2. 清空被污染的 session（替换 <项目名>）
# 直接删除或编辑对应的 json 文件
del "C:\Users\<你的用户名>\.cc-connect\sessions\<项目名>.json"

# 3. 重启
pm2 restart wechat
```

### 防护措施

已在 config.toml 中配置：
```toml
reset_on_idle_mins = 30  # 30分钟无活动自动重置会话
```

## Token 监控脚本不弹窗

### 检查 PowerShell 执行策略

```powershell
Get-ExecutionPolicy
# 如果不是 Bypass 或 RemoteSigned，执行：
Set-ExecutionPolicy Bypass -Scope CurrentUser
```

### 检查通知权限

Windows 11 可能默认关闭通知：
1. 设置 → 系统 → 通知 → 确保通知已开启
2. 检查"焦点助手"是否屏蔽了通知

### 手动启动监控

```bash
powershell -ExecutionPolicy Bypass -File "C:\Users\<你的用户名>\.claude\skills\cc-connect\token-monitor.ps1"
```

## 开机自启不生效

### 检查启动文件夹

```bash
# 打开启动文件夹
explorer "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
```

确认 `pm2-cc-connect.bat` 存在。

### 检查 pm2 dump 文件

```bash
pm2 save     # 确保进程列表已保存
pm2 list     # 确认 wechat 在列表中
```

## 只绑定一个微信

如果只需要一个微信，编辑 `config.toml`，删除第二个 `[[projects]]` 块即可。监控脚本中的 `$AllProjects` 也对应修改：

```powershell
$AllProjects = @("wechat-claude")
```
