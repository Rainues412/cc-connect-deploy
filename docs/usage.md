# 使用说明

以根目录 README.md 为当前部署依据。

1. 运行 startup\pm2-cc-connect.bat 恢复连接；可以重复执行。
2. 微信发送文字后可继续同一任务；不再在空闲 30 分钟后自动换会话。
3. 图片会收到输入保护提示。先将图片内容转成文字；图片不会进入 Claude 主会话。
4. 需要换话题或某个历史会话持续报上下文错误时，用 /new 新建；旧会话仍可 /list、/switch。
5. admin_from 未开启，远程特权命令默认不可用；不应把它改成通配符。
6. 日志和状态位于 D:\Software\AI\Codex\04_Codex工具与记录\cc-connect运行记录。monitor-status.json 区分进程、账号通道、凭据、上下文和 Agent 状态。
7. 用 scripts\setup.ps1 修复当前部署的自启登记。它不重绑微信，不清空会话，不删除进程项。

窗口关闭不影响 PM2 桥接和 Windows 任务监控。此配置在本人登录 Windows 后工作，不承诺未登录时运行。修改 config.toml 前备份；修改 work_dir 会影响会话文件名，不能只改目录后就断言历史已恢复。
