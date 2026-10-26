---
name: cc-connect
description: Manage the existing local Claude Code / dual WeChat bridge safely.
allowed-tools: Bash(cc-connect:*), Bash(pm2:*), Read
---

# 本机 cc-connect

源码：D:\coding\cc-connect-deploy。
实际配置：C:\Users\76879\.claude\skills\cc-connect\config.toml。
本目录为兼容副本，运行脚本调用 D 盘源码。先读 README.md；不要凭本文件猜测实时 PID 或运行状态。

## 当前部署约定

- Claude Code + qwen3.7-max[1M]；发送者分别限制本人 ID。
- work_dir 明确指定用户主目录；reset_on_idle_mins=0，保留上下文。
- 图片通过输入保护层拒绝进入主会话；转文字后继续。当前没有独立 OCR。
- cc-connect 的 cmd 指向 D 盘 bin\ClaudeGuardLauncher.exe 无控制台启动器，不直接指向 node.exe，以免微信提问弹出终端。
- PM2 只托管 wechat。Windows 任务 CCConnect-Monitor 托管只读健康监控。
- 当前用户登录自启，启动器有重试和健康握手；监控任务每分钟检查拉起，已运行时忽略重复触发。
- 运行状态查看 D:\Software\AI\Codex\04_Codex工具与记录\cc-connect运行记录\monitor-status.json，不能只看 PM2 online。

## 操作

正常恢复运行 D:\coding\cc-connect-deploy\startup\pm2-cc-connect.bat。
修复当前部署的注册执行 D:\coding\cc-connect-deploy\scripts\setup.ps1；该入口不会安装软件、重新绑定微信或删除正常进程。

API 400 不等于会话必坏；429/503/网络错误不清空历史。只有确认当前会话持续无法恢复时才在对应微信用 /new，新会话之外的旧记录保留。微信登录失效与回复 context_token 过期分别处理。

禁止通过外部脚本改写运行中的会话、批量裁剪 history、删除 .bak 或用户附件。weekly-cleanup.ps1 现仅提供只读大小检查，没有自动清理任务。不要恢复旧的自动扫码、停止双微信或“400 自动清空”逻辑。

实际 config.toml 和备份可能含凭据，禁止上传。AGENTS.md 仅本地维护。
