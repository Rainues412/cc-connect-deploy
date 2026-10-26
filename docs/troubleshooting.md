# 故障排查

## 连接或监控未运行

运行 startup\pm2-cc-connect.bat，随后检查 monitor-status.json 的时间、Pid、BridgeState 和每账号状态。监控任务为 CCConnect-Monitor，桥接进程名为 PM2/wechat。

恢复自启登记使用 scripts\setup.ps1。不删除或重建正常进程，不全量 resurrect 历史 PM2 dump，不永久降低用户执行策略。

## 微信无回复

区分：
- Channel=login_expired 或明确 -14：只重新登录对应账号。
- Context=expired：先用该微信发送新消息刷新回复令牌。
- Credential=unknown：探测失败不代表令牌过期，应检查网络/网关。
- Agent=error：检查模型接口，不能当成微信登录故障。
- PM2 online 只说明进程存在，仍需看通道和手机端回复。

重新登录前保留配置备份，确认 affected project。需要停止共用桥接才能修改配置时，完成扫码后再次运行启动脚本，不删除历史。

## 图片或 API 错误

微信项目默认 qwen3.8-max，已实测识图及图片后的文字上下文。只有显式指定这个已验证模型才放行图片；旧模型或其他未验证路由仍提示转成文字。不要把不支持的图片反复追加到同一后端会话。

若某个旧会话已持续报图片/上下文错误，在对应微信用 /new 新建；原会话保留。429、503、网络超时先检查限流或上游，不清空历史。

不直接编辑运行中的 session JSON，不把“裁剪桥接 history”当作压缩 Claude 的真实上下文，不删除会话备份。需要压缩时使用上游原生 /compress 能力，并核对所用模型及版本支持情况。

## 通知未显示

检查 Windows 通知及勿扰设置。通知投递不保证在勿扰期间弹出，健康状态仍写入 D 盘 monitor-status.json。不要因此永久更改执行策略。
