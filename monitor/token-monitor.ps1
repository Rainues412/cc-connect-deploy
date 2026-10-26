# Read-only account health monitor, supervised by PM2.
$ErrorActionPreference='Stop'
. 'D:\coding\cc-connect-deploy\scripts\runtime-common.ps1'
$StatePath=Join-Path $script:CcRuntime 'monitor-status.json'
$LogPath=Join-Path $script:CcRuntime 'token-monitor.log'
$LogPaths=@((Join-Path $env:USERPROFILE '.pm2\logs\wechat-out.log'),(Join-Path $env:USERPROFILE '.pm2\logs\wechat-error.log'))
function ConvertFrom-CcLogLine([string]$Line){
    $fields=@{}
    foreach($match in [regex]::Matches($Line,'(?:^|\s)([A-Za-z_]\w*)=("(?:\\.|[^"\\])*"|[^\s]+)')){
        $value=$match.Groups[2].Value
        if($value.StartsWith('"')){try{$value=$value|ConvertFrom-Json}catch{continue}}
        $fields[$match.Groups[1].Value]=$value
    }
    return $fields
}
function Read-NewLogLines([string]$Path,[hashtable]$Cursors){
    if(-not $Cursors.ContainsKey($Path)){$Cursors[$Path]=@{Position=0;Identity=0;Pending=''}}
    if(-not(Test-Path -LiteralPath $Path)){return @()}
    $item=Get-Item -LiteralPath $Path;$cursor=$Cursors[$Path]
    if($cursor.Identity -ne $item.CreationTimeUtc.Ticks -or $item.Length -lt $cursor.Position){$cursor.Position=0;$cursor.Pending='';$cursor.Identity=$item.CreationTimeUtc.Ticks}
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{
        [void]$stream.Seek($cursor.Position,[IO.SeekOrigin]::Begin)
        $reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8,$true,4096,$true)
        try{$text=$cursor.Pending+$reader.ReadToEnd();$cursor.Position=$stream.Position}finally{$reader.Dispose()}
    }finally{$stream.Dispose()}
    $lines=$text -split [char]10;$cursor.Pending=$lines[-1]
    if($lines.Count -gt 1){return @($lines[0..($lines.Count-2)]|ForEach-Object{$_.TrimEnd([char]13)})}
    return @()
}
function New-CcAccountState{
    return @{Channel='pending';Credential='unchecked';Agent='idle';Context='ok';LastIncoming=$null;LastAgentSuccess=$null;LastError=$null;LastEventAt=$null;FaultSince=$null;LastProbeAt=$null;ProbeError=$null}
}
function Apply-CcEvent([hashtable]$Event,[hashtable]$Health,$Accounts,[hashtable]$MessageProjects){
    $project=$Event.project
    if(-not $Health.ContainsKey([string]$project)){
        $project=$null
        foreach($account in $Accounts){
            if(($Event.account -and $Event.account -eq $account.account_id) -or ($Event.session -and $Event.session -eq ('weixin:dm:'+$account.allow_from)) -or ($Event.peer -and $Event.peer -eq $account.allow_from)){$project=$account.name;break}
        }
        if(-not $project -and $Event.msg_id -and $MessageProjects.ContainsKey($Event.msg_id)){$project=$MessageProjects[$Event.msg_id]}
    }
    $message=[string]$Event.msg;$targets=@()
    if($project){$targets=@($project)}elseif($message -eq 'weixin: getUpdates failed'){$targets=@($Health.Keys)}
    foreach($target in $targets){
        $state=$Health[$target];$time=$Event.time;$previousError=$state.LastError
        if($message -eq 'platform ready' -and $Event.platform -eq 'weixin'){$state.Channel='ready';$state.LastError=$null}
        elseif($message -eq 'message received' -and $Event.platform -eq 'weixin'){
            $state.Channel='ready';$state.Context='ok';$state.LastIncoming=$time
            if($state.LastError -in @('Login','Context','Network')){$state.LastError=$null}
            if($Event.msg_id){$MessageProjects[$Event.msg_id]=$target}
        }
        elseif($message -eq 'turn complete'){$state.Agent='ok';$state.LastAgentSuccess=$time;if($state.LastError -eq 'Agent'){$state.LastError=$null}}
        elseif($message -eq 'processing message'){$state.Agent='processing'}
        elseif($message -eq 'weixin: session paused after gateway error' -or $Event.errcode -eq '-14'){$state.Channel='login_expired';$state.LastError='Login'}
        elseif($message -eq 'weixin: getUpdates failed'){$state.Channel='network_error';$state.LastError='Network'}
        elseif($message -match '^weixin:.*no fresh context_token' -or ($message -eq 'platform send failed' -and $Event.error -match 'expired context_token')){$state.Context='expired';$state.LastError='Context'}
        elseif($Event.level -eq 'ERROR' -and $message -match 'agent error|claudeSession: process failed'){$state.Agent='error';$state.LastError='Agent'}
        else{continue}
        if($state.LastError -ne $previousError){$state.FaultSince=if($state.LastError){$time}else{$null}}
        $state.LastEventAt=$time
    }
}
function Test-CcCredential($Account){
    $cachePath=Join-Path (Join-Path (Join-Path (Join-Path $env:USERPROFILE '.cc-connect\weixin') $Account.name) $Account.account_id) 'context_tokens.json'
    if(-not(Test-Path -LiteralPath $cachePath)){return @{Credential='unchecked';Error='No cached conversation token.'}}
    $cache=Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8|ConvertFrom-Json
    $property=$cache.PSObject.Properties|Where-Object Name -eq $Account.allow_from|Select-Object -First 1
    if(-not $property){return @{Credential='unchecked';Error='No cached token for allowed sender.'}}
    $payload=@{ilink_user_id=$Account.allow_from;context_token=$property.Value;base_info=@{channel_version='cc-connect-weixin/1.0'}}|ConvertTo-Json -Compress
    $headers=@{AuthorizationType='ilink_bot_token';Authorization=('Bearer '+$Account.token);'X-WECHAT-UIN'=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('123456789'))}
    try{
        $response=Invoke-WebRequest -UseBasicParsing -Uri ($Account.base_url.TrimEnd('/')+'/ilink/bot/getconfig') -Method Post -Headers $headers -ContentType 'application/json' -Body $payload -TimeoutSec 8
        $body=if($response.Content -is [byte[]]){[Text.Encoding]::UTF8.GetString($response.Content)}else{[string]$response.Content}
        $result=$body|ConvertFrom-Json
        if($result.ret -eq 0 -and (-not $result.errcode -or $result.errcode -eq 0)){return @{Credential='valid';Error=$null}}
        if($result.errcode -eq -14){return @{Credential='expired';Error='WeChat login expired (-14).'}}
        return @{Credential='unknown';Error='Gateway rejected probe; no automatic reset.'}
    }catch{return @{Credential='unknown';Error='Network/gateway probe failed; not classified as expired login.'}}
}
function Show-CcNotice([string]$Body){
    try{
        [Windows.UI.Notifications.ToastNotificationManager,Windows.UI.Notifications,ContentType=WindowsRuntime]|Out-Null
        [Windows.Data.Xml.Dom.XmlDocument,Windows.Data.Xml.Dom.XmlDocument,ContentType=WindowsRuntime]|Out-Null
        $xml=New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml('<toast><visual><binding template="ToastGeneric"><text>cc-connect 连接提醒</text><text>'+[Security.SecurityElement]::Escape($Body)+'</text></binding></visual></toast>')
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Windows PowerShell').Show([Windows.UI.Notifications.ToastNotification]::new($xml))
    }catch{Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "$(Get-Date -Format o) notification unavailable; see status file."}
}
if(-not(Test-Path -LiteralPath $script:CcRuntime)){New-Item -ItemType Directory -Path $script:CcRuntime|Out-Null}
$mutex=New-Object Threading.Mutex($false,'Local\CCConnectTokenMonitor');$owns=$false
try{
    try{$owns=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owns=$true}
    if(-not $owns){exit 0}
    $accounts=@(Get-CcAccounts);$health=@{};$cursors=@{};$messages=@{};$alerts=@{};$bridgePid=0;$since=[DateTimeOffset]::MaxValue;$lastProbe=[DateTime]::MinValue
    if(Test-Path -LiteralPath $StatePath){try{$old=Get-Content -LiteralPath $StatePath -Raw|ConvertFrom-Json;foreach($prop in $old.Alerts.PSObject.Properties){$alerts[$prop.Name]=[string]$prop.Value}}catch{}}
    Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "$(Get-Date -Format o) supervised monitor started pid=$PID."
    while($true){
        $errorMessage=$null;$bridgeState='unknown'
        try{
            $entries=@(Get-CcProcesses);$bridge=@($entries|Where-Object name -eq 'wechat')
            if($bridge.Count -ne 1){$bridgeState='missing-or-duplicate'}else{
                $bridgeState=$bridge[0].pm2_env.status
                if($bridgePid -ne $bridge[0].pid){
                    $bridgePid=$bridge[0].pid;$cursors=@{};$messages=@{};$health=@{}
                    foreach($account in $accounts){$health[$account.name]=New-CcAccountState}
                    $since=[DateTimeOffset]::FromUnixTimeMilliseconds([long]$bridge[0].pm2_env.pm_uptime).AddSeconds(-1);$lastProbe=[DateTime]::MinValue
                }
                $events=@(foreach($path in $LogPaths){foreach($line in @(Read-NewLogLines $path $cursors)){
                    $event=ConvertFrom-CcLogLine $line
                    if($event.time){$eventTime=[DateTimeOffset]::MinValue;if([DateTimeOffset]::TryParse($event.time,[ref]$eventTime) -and $eventTime -ge $since){$event}}
                }})
                foreach($event in ($events|Sort-Object {$_.time})){Apply-CcEvent $event $health $accounts $messages}
                if(((Get-Date)-$lastProbe).TotalMinutes -ge 5){
                    foreach($account in $accounts){
                        $probe=Test-CcCredential $account;$state=$health[$account.name]
                        $state.Credential=$probe.Credential;$state.LastProbeAt=Get-Date -Format o;$state.ProbeError=$probe.Error
                        if($probe.Credential -eq 'expired'){$state.Channel='login_expired';if($state.LastError -ne 'Login'){$state.FaultSince=Get-Date -Format o};$state.LastError='Login'}
                        # Credential success is not proof of actual message delivery.
                        if($probe.Credential -eq 'valid' -and $state.Channel -eq 'network_error'){$state.Channel='awaiting_message';$state.LastError=$null}
                    }
                    $lastProbe=Get-Date
                }
            }
            foreach($name in @($health.Keys)){
                $state=$health[$name];$kind=$state.LastError
                if(-not $kind){continue}
                if($kind -eq 'Network' -and ((Get-Date)-[DateTime]$state.FaultSince).TotalMinutes -lt 2){continue}
                $key=$name+'/'+$kind;$eventAt=[string]$state.FaultSince
                if($alerts.ContainsKey($key) -and $alerts[$key] -eq $eventAt){continue}
                $alerts[$key]=$eventAt
                $body=switch($kind){
                    'Login'{"$($name)：微信登录失效，请仅重新绑定该账号，保留现有会话。"}
                    'Context'{"$($name)：回复令牌过期，请从微信发送新消息刷新，无需清空历史。"}
                    'Agent'{"$($name)：Claude 请求异常。先排查接口；若仅该会话持续失败，用 /new 新建，旧会话保留。"}
                    default{"$($name)：微信网络连续异常，请检查连接。"}
                }
                Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "$(Get-Date -Format o) $name $kind"
                Show-CcNotice $body
            }
        }catch{$errorMessage=$_.Exception.Message}
        if($bridgeState -ne 'online'){
            if(-not $alerts.ContainsKey('Bridge') -or ((Get-Date)-[DateTime]$alerts.Bridge).TotalMinutes -ge 30){
                $alerts.Bridge=Get-Date -Format o
                Show-CcNotice 'cc-connect 桥接进程异常，请运行启动脚本恢复。这不代表微信令牌过期。'
            }
        }elseif($alerts.ContainsKey('Bridge')){$alerts.Remove('Bridge')}
        Write-CcJson $StatePath @{Pid=$PID;CheckedAt=(Get-Date -Format o);BridgePid=$bridgePid;BridgeState=$bridgeState;Error=$errorMessage;Accounts=$health;Alerts=$alerts}
        Start-Sleep -Seconds 30
    }
}finally{if($owns){$mutex.ReleaseMutex()};$mutex.Dispose()}
