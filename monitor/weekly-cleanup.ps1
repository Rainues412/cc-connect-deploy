# Legacy destructive cleanup is retired. This entry point is read-only.
$ErrorActionPreference='Stop'
Write-Output '旧的会话裁剪、备份删除及附件删除已停用。该脚本仅列出日志大小，不修改用户数据。'
foreach($name in @('wechat-out.log','wechat-error.log')){
    $file=Join-Path (Join-Path $env:USERPROFILE '.pm2\logs') $name
    if(Test-Path -LiteralPath $file){Get-Item -LiteralPath $file|Select-Object Name,Length,LastWriteTime}
}
