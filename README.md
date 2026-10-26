# cc-connect 本机部署

维护日期：2026-10-26。主程序保持 cc-connect v1.4.1，两个微信项目使用 Claude Code + qwen3.7-max[1M]。

## 当前入口

源码统一在 D:\coding\cc-connect-deploy。已有配置和兼容入口在 C:\Users\76879\.claude\skills\cc-connect；兼容脚本调用 D 盘源码，不是独立的第二套部署。不得提交实际 config.toml、会话或 PM2 dump。

AGENTS.md 和 SKILL.md 属于本机操作指引，只在本地维护，不纳入 GitHub 同步。

- 正常恢复：运行 startup\pm2-cc-connect.bat。
- 修复自启登记：用 Windows PowerShell 执行 scripts\setup.ps1。只校验现有依赖、注册自启和恢复实例，不安装软件、不重新扫码、不重建正常进程。
- 首次安装或新增账号需要单独安装依赖并执行 cc-connect weixin setup，不在现有实例修复时自动进行。
- HKCU Run/CCConnect 登录后启动桥接；脚本有互斥锁、有限重试，并等待监控发布新鲜状态。
- 监控由 Windows 任务 CCConnect-Monitor 托管，登录触发，异常退出重试，并每分钟检查一次是否需要拉起；已运行时忽略重复实例，最长运行时间不限。已实测结束监控后可由周期触发自动恢复。PM2 只托管 wechat，避免原生 PowerShell 在本机 PM2 下反复退出。
- 手动启动器与修复入口均可重复执行，不影响已在线的桥接和监控。

## 会话与权限

两个项目显式 work_dir=C:/Users/76879，mode=default，reset_on_idle_mins=0。任务间保留上下文，需要换话题时用 /new；旧会话可 /list、/switch。发送者分别限定为各自已绑定的本人 ID，admin_from 继续未设置，特权管理命令默认拒绝。工作目录不是文件系统沙箱。

显式工作目录使会话文件采用带目录哈希的名称。原 7 个和 15 个会话已逐字节复制到新文件并核验；旧文件保留。之后只用当前带哈希的文件，不按旧名称直接编辑、裁剪或删除会话。

## 图片保护与错误恢复

当前 3.7 路由文字请求成功，图片请求曾返回上游 503。未把该响应当作“模型永远不支持图片”的证明。

Claude 命令先经过 bin\ClaudeGuardLauncher.exe 无控制台启动器，再由 scripts\claude-image-guard.cjs 转发。启动器为本机 .NET Framework 编译的 Windows GUI 子系统小程序，内部 Node 和 Claude 均隐藏启动，避免每次微信提问弹出终端。缺少该二进制时，setup.ps1 通过 scripts\build-launcher.ps1 在 D 盘重建，不安装新依赖。

图片处理方式：
- 微信输入包含图片时直接给出保护提示，不把该输入送入 Claude 后端。
- 仅对本桥接子进程增加 Read 常见图片文件的工具保护；不修改 Claude 全局 settings.json。
- 图片前后的正常文字和权限协议正常转发，已有后端 session ID 保持不变。
- 真实测试已验证：记住标记 → 图片被拦截 → 仍可答出标记。
- 当前不提供独立 OCR/视觉模型。确有看图需求时需另行确认可用的视觉接口，识图结果作为文字交给主会话。

已受历史图片/上下文错误影响的会话，先排查接口；确定只有某会话持续失败时在对应微信使用 /new，保留旧会话。429、超时和上游临时错误不能成为自动删除历史或重置全部会话的理由。

## 健康监控

monitor\token-monitor.ps1 每 30 秒查询桥接并读取新增日志，重启后按当前桥接启动时间回放已有事件，避免漏掉监控启动前的失败。每 5 分钟对每账号做只读 getconfig 探测，超时 8 秒。进程状态查询也有超时。

monitor-status.json 分别记录 BridgeState、每账号 Channel/Credential/Agent/Context 及检查时间。凭据有效不等于手机实际收到了回复；无消息时 Agent=idle 是正常状态。未带账号的上游网络错误无法精确归属，恢复后仍需消息确认。成功连接或新消息会清除相应已恢复的异常状态，报警状态持久化去重。状态文件原子替换，不记录令牌和消息内容。

- 登录失效：提示对应账号重新绑定。
- 回复令牌过期：先从微信发新消息，不强制扫码。
- Claude 错误：提示检查接口及必要时只新建当前会话。
- 不自动停止两个微信、不清空或裁剪会话、不重绑令牌。

## 清理与记录

monitor\weekly-cleanup.ps1 已改为只读日志大小检查；没有注册自动数据清理，不删除备份、附件、提示或会话。长期日志轮转需要单独配置，不通过删除业务历史节省空间。

运行记录：D:\Software\AI\Codex\04_Codex工具与记录\cc-connect运行记录
加固备份及测试：D:\Software\AI\Codex\04_Codex工具与记录\cc-connect加固_2026-10-26
备份含本地凭据，不上传。源码和 C 盘兼容说明同步维护。
