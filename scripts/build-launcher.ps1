$ErrorActionPreference='Stop'
$root='D:\coding\cc-connect-deploy'
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(-not(Test-Path -LiteralPath $compiler)){throw 'The existing Windows .NET Framework compiler is missing.'}
$bin=Join-Path $root 'bin'
if(-not(Test-Path -LiteralPath $bin)){New-Item -ItemType Directory -Path $bin|Out-Null}
& $compiler /nologo /target:winexe /platform:anycpu /optimize ('/out:'+(Join-Path $bin 'ClaudeGuardLauncher.exe')) (Join-Path $root 'scripts\ClaudeGuardLauncher.cs')
if($LASTEXITCODE -ne 0){throw 'Hidden launcher build failed.'}
