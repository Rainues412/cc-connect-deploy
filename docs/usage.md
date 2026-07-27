# 使用说明

## 架构概览

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│  微信账号 1  │────▶│                  │────▶│             │
│  (扫码登录)  │     │   cc-connect     │     │ Claude Code │
├─────────────┤────▶│   (pm2 守护)      │────▶│   Agent     │
│  微信账号 2  │     │                  │     │             │
│  (扫码登录)  │     └──────────────────┘     └─────────────┘
└─────────────┘              │
                             ▼
                    ┌──────────────────┐
                    │  token-monitor   │
                    │  (后台监控)       │
                    └──────────────────┘
```

## 日常使用

### 查看状态

```bash
pm2 status              # 查看进程是否在线
pm2 logs wechat         # 查看实时日志
```

### 从微信发消息

直接用任一微信给绑定的账号发消息，cc-connect 会自动路由到 Claude Code 处理。多个微信各自维护独立的对话上下文。

### 重启服务

```bash
pm2 restart wechat      # 重启 cc-connect（所有微信同时重连）
pm2 stop wechat         # 停止
pm2 start wechat        # 启动
```

## 添加更多微信

### 方法 1：编辑配置

在 `~/.claude/skills/cc-connect/config.toml` 中追加：

```toml
[[projects]]
name = "wechat-claude-3"
dir = "~"
reset_on_idle_mins = 30

[projects.agent]
type = "claudecode"

[[projects.platforms]]
type = "weixin"

[projects.platforms.options]
token = ""
allow_from = "*"
base_url = "https://ilinkai.weixin.qq.com"
account_id = ""
```

然后扫码绑定并重启：

```bash
cc-connect weixin setup --project wechat-claude-3 --config ~/.claude/skills/cc-connect/config.toml
pm2 restart wechat
```

### 方法 2：同时更新监控

编辑 `~/.claude/skills/cc-connect/token-monitor.ps1`，在 `$AllProjects` 数组中添加新项目名：

```powershell
$AllProjects = @("wechat-claude", "wechat-claude-2", "wechat-claude-3")
```

## 防护机制

### 三层防护防止 API 400 错误

```
用户发消息
    ↓
┌──────────────────────────────────────┐
│ 防护层 1: reset_on_idle_mins = 30    │  ← config.toml
│ 30分钟无活动自动重置会话              │
└──────────────────────────────────────┘
    ↓
┌──────────────────────────────────────┐
│ 防护层 2: 400 错误自动修复           │  ← token-monitor.ps1
│ 检测到 API Error 400 → 清空污染历史  │
│ → 弹窗通知 → 自动重启 cc-connect    │
└──────────────────────────────────────┘
    ↓
┌──────────────────────────────────────┐
│ 防护层 3: 历史长度限制               │  ← token-monitor.ps1
│ 每 session 最多 100 条历史           │
│ 超出自动裁剪到最新 50 条             │
└──────────────────────────────────────┘
```

### 防护层 1：空闲自动重置

在 `config.toml` 中配置：

```toml
[[projects]]
name = "wechat-claude"
dir = "~"
reset_on_idle_mins = 30  # 30分钟无活动自动清空会话
```

**注意**：cc-connect v1.4.1 可能未正确加载此配置，依赖防护层 2、3 作为替代。

### 防护层 2：400 错误自动修复

`token-monitor.ps1` 会：
- 每 30 秒检查 pm2 日志
- 检测 `API Error.*400`、`bad response status code 400` 等关键词
- 自动定位是哪个 project 出错
- 清空该 project 的污染历史
- 弹窗通知用户
- 自动重启 cc-connect

### 防护层 3：历史长度限制

`token-monitor.ps1` 会：
- 检查每个 session 的历史条数
- 超过 100 条时自动裁剪到最新 50 条
- 防止历史过长导致 API 请求超限

## Token 过期自动重连流程

```
token-monitor.ps1 (每 30s 检查日志)
        ↓ 检测到过期关键词
   Windows 弹窗通知
        ↓
   自动停掉 pm2 wechat
        ↓
   弹出新终端窗口显示二维码
        ↓ 你扫码
   自动重启 pm2 wechat
        ↓
   通知"已恢复连接"
```

## 监控脚本日志

监控脚本会输出彩色日志，方便排查问题：

```
========================================
 cc-connect Token Monitor
 Error log: C:\Users\<用户名>\.pm2\logs\wechat-error.log
 Projects: wechat-claude, wechat-claude-2
 Checking every 30s
 Press Ctrl+C to stop
========================================
[2026-07-27 10:30:15] 400 error detected for wechat-claude
  Log: level=ERROR msg="API Error: 400 bad response..."
[2026-07-27 10:30:15] Corrupted session in wechat-claude! Clearing...
[2026-07-27 10:30:16] Session repaired: wechat-claude
```
