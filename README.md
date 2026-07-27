# cc-connect 微信双账号自动部署方案

> 一键部署 cc-connect，让 Claude Code 同时绑定多个微信账号，支持开机自启 + Token 过期自动扫码 + API 错误自动修复。

## 功能特性

- **多微信绑定** — 同时连接多个微信个人号，各自独立与 Claude Code 对话
- **pm2 守护进程** — 脱离终端运行，Claude Code 关闭后微信连接不中断
- **开机自启** — Windows 登录后自动恢复所有服务
- **Token 过期监控** — 实时检测微信 Token 过期，自动弹窗通知并打开扫码窗口
- **自动重连** — 扫码完成后自动重启 cc-connect，无需手动操作
- **API 400 自动修复** — 检测会话污染（空消息/错误历史），自动清空并重启
- **历史长度限制** — 自动裁剪过长会话历史，防止 API 请求超限
- **空闲自动重置** — 配置 `reset_on_idle_mins` 定时清空会话

## 项目结构

```
cc-connect-deploy/
├── README.md                      # 本文件
├── config.example.toml            # cc-connect 配置模板（多微信）
├── scripts/
│   └── setup.ps1                  # 一键安装脚本
├── monitor/
│   └── token-monitor.ps1          # Token 监控 + 400 修复 + 历史裁剪
├── startup/
│   ├── pm2-cc-connect.bat         # 开机自启脚本
│   └── token-monitor.bat          # 监控启动器
└── docs/
    ├── usage.md                   # 使用说明
    └── troubleshooting.md         # 常见问题排查
```

## 快速开始

### 1. 一键安装

以 **管理员权限** 打开 PowerShell，运行：

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\scripts\setup.ps1
```

安装脚本会自动完成以下操作：
- 安装 cc-connect（`npm install -g cc-connect`）
- 安装 pm2（`npm install -g pm2`）
- 复制配置文件到 `~/.claude/skills/cc-connect/`
- 引导扫码绑定第一个微信
- 引导扫码绑定第二个微信
- 启动 pm2 守护进程
- 配置开机自启

### 2. 手动安装

如果你更喜欢手动控制：

```bash
# 安装依赖
npm install -g cc-connect pm2

# 复制并编辑配置
cp config.example.toml ~/.claude/skills/cc-connect/config.toml
# 编辑 config.toml，修改 project 名称和 dir 路径

# 扫码绑定微信（每个 project 执行一次）
cc-connect weixin setup --project wechat-claude --config ~/.claude/skills/cc-connect/config.toml
cc-connect weixin setup --project wechat-claude-2 --config ~/.claude/skills/cc-connect/config.toml

# 启动守护进程（Windows 下必须用 .exe 路径，不能用 cc-connect.cmd）
pm2 start "C:\Users\<用户名>\AppData\Roaming\npm\node_modules\cc-connect\bin\cc-connect.exe" --name wechat -- --config ~/.claude/skills/cc-connect/config.toml
pm2 save

# 启动 Token 监控
powershell -ExecutionPolicy Bypass -File monitor/token-monitor.ps1
```

## 配置说明

### config.toml 关键字段

```toml
[[projects]]
name = "wechat-claude"          # 项目名称，需唯一
dir = "~"                        # Agent 工作目录
reset_on_idle_mins = 30         # 30分钟无活动自动重置会话

[projects.agent]
type = "claudecode"              # AI Agent 类型

[[projects.platforms]]
type = "weixin"                  # 平台类型

[projects.platforms.options]
token = "xxx@im.bot:xxx"         # 扫码自动获取，勿手动修改
allow_from = "*"                 # 允许发送消息的用户，* 表示全部
base_url = "https://ilinkai.weixin.qq.com"
account_id = "xxx@im.bot"        # 扫码自动获取
```

### 添加更多微信

在 config.toml 中追加一个 `[[projects]]` 块，修改 `name`，然后扫码绑定即可。理论上支持绑定任意数量的微信。

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

### 400 错误的原因

当用户发送空消息（如纯图片）时，cc-connect 会将 API 返回的 400 错误信息作为 assistant 回复保存到会话历史中。之后每次发消息都会携带这段污染的历史，导致持续 400 错误。

监控脚本会自动检测并修复此问题，无需手动干预。

## 常用命令

| 命令 | 说明 |
|------|------|
| `pm2 status` | 查看 cc-connect 运行状态 |
| `pm2 logs wechat` | 查看实时日志 |
| `pm2 restart wechat` | 重启 cc-connect |
| `pm2 stop wechat` | 停止 cc-connect |
| `cc-connect list --config ~/.claude/skills/cc-connect/config.toml` | 列出活跃会话 |

## Token 过期处理

Token 过期时，监控脚本会自动：

1. 发送 Windows 通知弹窗
2. 停止 cc-connect 进程
3. 打开新终端窗口显示二维码
4. 你扫码后自动重启 cc-connect

如果需要手动重连：

```bash
pm2 stop wechat
cc-connect weixin setup --project <项目名> --config ~/.claude/skills/cc-connect/config.toml
pm2 restart wechat
```

## 系统要求

- Windows 10/11
- Node.js >= 18
- npm
- 微信客户端（用于扫码）

## 已知问题

- `reset_on_idle_mins` 在 cc-connect v1.4.1 中可能未被正确加载，依赖监控脚本的防护层 2、3 作为替代
- Windows 下 pm2 不能直接调用 `cc-connect.cmd`，必须使用 `cc-connect.exe` 的完整路径
- `pm2 startup` 在 Windows 上不可用，改用启动文件夹中的 .bat 脚本

## License

MIT
