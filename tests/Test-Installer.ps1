#requires -Version 5.1
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$root=Join-Path ([IO.Path]::GetTempPath()) ('agent-brain-test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$utf8=[Text.UTF8Encoding]::new($false)
$composeFile=Join-Path $root 'compose.yaml'
$Action='Install';$Port=8765;$DashboardPort=8766;$Retries=3;$NonInteractive=$true;$InstallDocker=$false
$script:PSBoundParametersSnapshot=@{}
. (Join-Path $project 'installer/Core.ps1')
. (Join-Path $project 'installer/Clients.ps1')
Copy-Item (Join-Path $project 'BRAIN-INSTRUCTIONS.md') (Join-Path $root 'BRAIN-INSTRUCTIONS.md')
$script:checks=0
function Assert($Condition,[string]$Message) {if (-not $Condition) {throw $Message};$script:checks++}
function Expect-Code([scriptblock]$Body,[string]$Code) {
    $caught=$false
    try {& $Body} catch {if ($_.Exception.Data['BrainCode'] -ne $Code) {throw};$caught=$true}
    Assert $caught ('Expected error '+$Code)
}
foreach ($file in @((Join-Path $project 'Install-AgentBrain.ps1'))+@(Get-ChildItem (Join-Path $project 'installer') -Filter '*.ps1' | ForEach-Object {$_.FullName})+@(Get-ChildItem (Join-Path $project 'scripts') -Filter '*.ps1' | ForEach-Object {$_.FullName})) {
    $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0) ('Parser error: '+$file)
    $sourceBytes=[IO.File]::ReadAllBytes($file)
    Assert ($sourceBytes.Length -ge 3 -and $sourceBytes[0] -eq 0xEF -and $sourceBytes[1] -eq 0xBB -and $sourceBytes[2] -eq 0xBF) ('UTF-8 BOM missing for Windows PowerShell 5.1: '+$file)
}
$instructions=Join-Path $root 'AGENTS.md'
Write-Text $instructions 'Existing personal rules.'
Add-Instructions $instructions
$first=[IO.File]::ReadAllBytes($instructions);$timestamp=(Get-Item $instructions).LastWriteTimeUtc
$backupCount=@(Get-ChildItem (Join-Path $root 'backups/client-config')).Count
Add-Instructions $instructions
Assert ([Convert]::ToBase64String($first) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($instructions))) 'Repeated instructions changed bytes.'
Assert ((Get-Item $instructions).LastWriteTimeUtc -eq $timestamp) 'Repeated instructions rewrote file.'
Assert (@(Get-ChildItem (Join-Path $root 'backups/client-config')).Count -eq $backupCount) 'Repeated instructions created backups.'
Assert ([IO.File]::ReadAllText($instructions).Contains('Existing personal rules.')) 'Personal rules lost.'
Assert ([regex]::Matches([IO.File]::ReadAllText($instructions),'<!-- agent-brain:start -->').Count -eq 1) 'Instructions duplicated.'
$configPath=Join-Path $root 'settings.json'
Write-Text $configPath '{"theme":"dark","description":"Größe ändern – für alle","mcpServers":{"existing":{"url":"http://example.invalid/mcp"},"agent-brain":{"url":"http://old.invalid","custom":"keep"}}}'
Merge-McpJson $configPath ([pscustomobject]@{url='http://127.0.0.1:8765/mcp'})
$bytes=[IO.File]::ReadAllBytes($configPath);$backupCount=@(Get-ChildItem (Join-Path $root 'backups/client-config')).Count
Merge-McpJson $configPath ([pscustomobject]@{url='http://127.0.0.1:8765/mcp'})
$data=Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert ($data.description -ceq 'Größe ändern – für alle') 'Unicode JSON settings changed.'
Assert ($data.theme -eq 'dark' -and $data.mcpServers.existing.url -eq 'http://example.invalid/mcp') 'Unrelated JSON changed.'
Assert ($data.mcpServers.'agent-brain'.custom -eq 'keep') 'Custom MCP setting lost.'
Assert ([Convert]::ToBase64String($bytes) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($configPath))) 'Repeated JSON changed bytes.'
Assert (@(Get-ChildItem (Join-Path $root 'backups/client-config')).Count -eq $backupCount) 'Repeated JSON created backup.'
foreach ($bad in @('{broken','[]','null','{"mcpServers":null}','{"mcpServers":[]}')) {
    $invalid=Join-Path $root 'invalid.json';Write-Text $invalid $bad
    Expect-Code {Merge-McpJson $invalid ([pscustomobject]@{url='test'})} 'CONFIG_INVALID'
    Assert ([IO.File]::ReadAllText($invalid) -ceq $bad) 'Invalid JSON overwritten.'
}
$badInstruction=Join-Path $root 'bad.md'
Write-Text $badInstruction '<!-- agent-brain:start -->unfinished'
Expect-Code {Add-Instructions $badInstruction} 'CONFIG_INVALID'
Write-Text $badInstruction '<!-- agent-brain:end --><!-- agent-brain:start -->'
Expect-Code {Add-Instructions $badInstruction} 'CONFIG_INVALID'
$cas=Join-Path $root 'cas.txt';Write-Text $cas 'changed elsewhere'
Expect-Code {Write-Text $cas 'overwrite' -ExpectedHash (Get-TextHash 'old')} 'CONFIG_CHANGED'
Assert ([IO.File]::ReadAllText($cas) -eq 'changed elsewhere') 'Concurrent edit overwritten.'
$script:transaction=@();$original=[IO.File]::ReadAllBytes($configPath)
Merge-McpJson $configPath ([pscustomobject]@{url='http://new.invalid'})
Undo-ClientChanges
Assert ([Convert]::ToBase64String($original) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($configPath))) 'Rollback changed original bytes.'
$script:transaction=@();Merge-McpJson $configPath ([pscustomobject]@{url='http://new.invalid'})
Write-Text $configPath '{"external":"parallel edit"}'
Undo-ClientChanges
Assert ([IO.File]::ReadAllText($configPath) -eq '{"external":"parallel edit"}') 'Rollback overwrote parallel edit.'
$script:transaction=$null
$script:secretValues=@('SYNTHETIC_SECRET_12345')
$safe=Protect-Text 'DB_PASSWORD=SYNTHETIC_SECRET_12345 postgresql://user:other@postgres/db api_key=third'
Assert (-not $safe.Contains('SYNTHETIC_SECRET_12345') -and -not $safe.Contains('user:other') -and -not $safe.Contains('third')) 'Credential redaction failed.'
$processImpl=${function:Invoke-Process}
# Isolated environment setup: Docker volume operations are simulated; no user data is touched.
& {
    function Invoke-Process {param($File,$Arguments,[switch]$Quiet) [pscustomobject]@{ExitCode=0;Output='';Error=''}}
    Ensure-Environment
    $envPath=Join-Path $root '.env';$initial=[IO.File]::ReadAllText($envPath)
    Assert ((Read-Environment $envPath).Values.DB_PASSWORD.Length -eq 64) 'Fresh password missing.'
    Ensure-Environment
    Assert ([IO.File]::ReadAllText($envPath) -ceq $initial) 'Repeated setup changed .env.'
    $firstPassword=(Read-Environment $envPath).Values.DB_PASSWORD
    $old=$initial -replace '(?m)^DASHBOARD_PORT=.*\r?\n?','';Write-Text $envPath $old -Private
    Ensure-Environment
    Assert ((Read-Environment $envPath).Values.DB_PASSWORD -eq $firstPassword -and [IO.File]::ReadAllText($envPath).StartsWith($old.TrimEnd())) 'Upgrade changed original settings.'
    $script:PSBoundParametersSnapshot=@{Port=9000};$Port=9000
    Expect-Code {Ensure-Environment} 'PORT_CONFIG'
    $script:PSBoundParametersSnapshot=@{}
}
& {
    $root=Join-Path $root 'missing-env';[IO.Directory]::CreateDirectory($root) | Out-Null
    function Invoke-Process {param($File,$Arguments,[switch]$Quiet) [pscustomobject]@{ExitCode=0;Output='agent-brain_brain-data';Error=''}}
    Expect-Code {Ensure-Environment} 'ENV_LOST'
    Assert (-not (Test-Path (Join-Path $root '.env'))) 'Lost env generated replacement password.'
}
$environmentFile=Join-Path $root '.env';$valid=[IO.File]::ReadAllText($environmentFile)
foreach ($bad in @($valid+"`nBRAIN_PORT=9999",($valid -replace 'BRAIN_PORT=8765','BRAIN_PORT=1'),($valid -replace 'DASHBOARD_PORT=8766','DASHBOARD_PORT=8765'))) {
    Write-Text $environmentFile $bad -Private
    Expect-Code {Read-Environment $environmentFile} 'ENV_INVALID'
}
Write-Text $environmentFile $valid -Private
# Native process execution really runs a shim in a path with spaces, unicode and shell metacharacters.
$shimFolder=Join-Path $root ('path with spaces & Unicode-'+[char]0x03A9);[IO.Directory]::CreateDirectory($shimFolder) | Out-Null
$shim=Join-Path $shimFolder 'argv.ps1'
Write-Text $shim 'param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Values) ConvertTo-Json -InputObject @($Values) -Compress; exit 23'
$arguments=@('space here','a"b','C:\trailing\','literal $() & ;','apostrophe''ok')
$response=Invoke-Process $shim $arguments -Quiet -AllowFailure
Assert ($response.ExitCode -eq 23) 'Native exit code lost.'
$parsed=$response.Output | ConvertFrom-Json;$received=@($parsed)
Assert (($received | ConvertTo-Json -Compress) -ceq ($arguments | ConvertTo-Json -Compress)) 'Native argument quoting changed data.'
$unicodeShim=Join-Path $shimFolder 'unicode.ps1'
[IO.File]::WriteAllText($unicodeShim, "Write-Output 'Größe ändern – für alle'; exit 0", [Text.UTF8Encoding]::new($true))
$unicodeResponse=Invoke-Process $unicodeShim -Quiet
Assert ($unicodeResponse.Output.Trim() -ceq 'Größe ändern – für alle') 'UTF-8 child process output corrupted.'
$slow=Join-Path $root 'slow.ps1';Write-Text $slow 'Start-Sleep -Seconds 10'
Expect-Code {Invoke-Process $slow -Timeout 1 -Quiet} 'TIMEOUT'
$script:attempts=0
Invoke-WithRetry {$script:attempts++;if ($script:attempts -lt 3) {throw 'connection reset'} }
Assert ($script:attempts -eq 3) 'Transient failures not retried.'
$script:attempts=0
try {Invoke-WithRetry {$script:attempts++;throw 'invalid configuration'}} catch {}
Assert ($script:attempts -eq 1) 'Permanent failure retried.'
# Real local listener proves port conflict detection without terminating any process.
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$listener.Start()
try {
    $activePort=$listener.LocalEndpoint.Port;$activeDashboardPort=65001
    function Get-StackStatus {return @()}
    Expect-Code {Assert-ResourcesAndPorts} 'PORT_BUSY'
} finally {$listener.Stop();Remove-Item Function:Get-StackStatus;. (Join-Path $project 'installer/Core.ps1')}
# Known prerequisite failures get specific codes without installing or starting software.
& {
    $InstallDocker=$true
    function Find-Docker {return $null}
    function Invoke-Process {param($File,$Arguments,[switch]$AllowFailure,[int]$Timeout) [pscustomobject]@{ExitCode=3010;Output='';Error=''}}
    if (Get-Command winget -ErrorAction SilentlyContinue) {Expect-Code {Ensure-Docker} 'REBOOT_REQUIRED'}
}
& {
    function Find-Docker {return $null}
    Expect-Code {Ensure-Docker} 'DOCKER_MISSING'
}
& {
    function Find-Docker {'docker'}
    function Invoke-Process {param($File,$Arguments,[switch]$Quiet,[switch]$AllowFailure) [pscustomobject]@{ExitCode=0;Output='[{"Endpoints":{"docker":{"Host":"ssh://remote.invalid"}}}]';Error=''}}
    Expect-Code {Ensure-Docker} 'REMOTE_DOCKER'
}
& {
    $oldContext=$env:DOCKER_CONTEXT;$oldHost=$env:DOCKER_HOST
    try {
        $env:DOCKER_CONTEXT='remote-context';$env:DOCKER_HOST='tcp://127.0.0.1:2375'
        function Invoke-Process {param($File,$Arguments,[switch]$Quiet,[switch]$AllowFailure) [pscustomobject]@{ExitCode=0;Output='[{"Endpoints":{"docker":{"Host":"ssh://remote.invalid"}}}]';Error=''}}
        Expect-Code {Assert-LocalDocker} 'REMOTE_DOCKER'
    } finally {$env:DOCKER_CONTEXT=$oldContext;$env:DOCKER_HOST=$oldHost}
}
& {
    function Find-Docker {'docker'}
    function Invoke-Process {param($File,$Arguments,[switch]$Quiet,[switch]$AllowFailure,[int]$Timeout) if ($Arguments[0] -eq 'context') {[pscustomobject]@{ExitCode=0;Output='[{"Endpoints":{"docker":{"Host":"npipe://local"}}}]';Error=''}} else {[pscustomobject]@{ExitCode=1;Output='';Error='engine offline'}}}
    $Action='Stop';Ensure-Docker -NoStart
    Assert $script:engineOffline 'Stop attempted to start an offline engine.'
    $Action='Status';Expect-Code {Ensure-Docker -NoStart} 'DOCKER_ENGINE'
}
& {
    function Find-Docker {'docker'}
    function Invoke-Process {param($File,$Arguments,[switch]$Quiet,[switch]$AllowFailure,[int]$Timeout) $value=if ($Arguments[0] -eq 'context') {'[{"Endpoints":{"docker":{"Host":"npipe://local"}}}]'} else {'windows'};[pscustomobject]@{ExitCode=0;Output=$value;Error=''}}
    Expect-Code {Ensure-Docker} 'WINDOWS_CONTAINERS'
}
& {
    function Find-Docker {'docker'}
    function Invoke-Process {param($File,$Arguments,[switch]$Quiet,[switch]$AllowFailure,[int]$Timeout) $value=switch ($Arguments[0]) {'context' {'[{"Endpoints":{"docker":{"Host":"npipe://local"}}}]'} 'info' {'linux'} default {'2.19.0'}};[pscustomobject]@{ExitCode=0;Output=$value;Error=''}}
    Expect-Code {Ensure-Docker} 'COMPOSE_VERSION'
}
& {
    function Invoke-Compose {param($Arguments,[switch]$Quiet,[switch]$AllowFailure) [pscustomobject]@{ExitCode=0;Output='[{"Service":"mcp"},{"Service":"dashboard"}]';Error=''}}
    Assert (@(Get-StackStatus).Count -eq 2) 'JSON-array compose status not parsed consistently.'
}
& {
    function Get-StackFingerprint {'unchanged'}
    function Get-StackStatus {foreach($name in @('postgres','ollama','mcp','dashboard')) {[pscustomobject]@{Service=$name;State='running';Health='healthy'}}}
    function Assert-ServiceEndpoints {}
    function Invoke-Compose {throw 'Unnecessary Docker mutation on healthy repeated setup.'}
    Write-Text (Join-Path $root 'installer-state.json') '{"fingerprint":"unchanged"}'
    Start-Brain
    Assert $true 'Fast path failed.'
}
& {
    function Get-DetectedAgents {'Codex';'Cursor'}
    function Configure-OneAgent {param($Agent,$Endpoint) if ($Agent -eq 'Codex') {Stop-Brain 'CLIENT_FAILED' 'Simulated unavailable client.'}}
    $Agents=@('Codex','Cursor');$activePort=8765
    Expect-Code {Configure-Agents} 'CLIENT_FAILED'
    Assert (@($script:clientResults | Where-Object {$_.status -eq 'failed'}).Count -eq 1) 'Partial client error missing.'
    Assert (@($script:clientResults | Where-Object {$_.status -eq 'configured'}).Count -eq 1) 'Other client not continued.'
}
# Missing package executes the entry point and produces a structured actionable failure.
$incomplete=Join-Path $root 'incomplete';[IO.Directory]::CreateDirectory((Join-Path $incomplete 'installer')) | Out-Null
Copy-Item (Join-Path $project 'Install-AgentBrain.ps1') $incomplete
Copy-Item (Join-Path $project 'installer/Core.ps1') (Join-Path $incomplete 'installer')
Copy-Item (Join-Path $project 'installer/Clients.ps1') (Join-Path $incomplete 'installer')
$response=Invoke-Process powershell.exe @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $incomplete 'Install-AgentBrain.ps1'),'-NoPause','-NonInteractive') -Quiet -AllowFailure
Assert ($response.ExitCode -eq 1 -and $response.Output.Contains('FILES_MISSING')) 'Entry point failure not actionable.'
$report=Get-Content ((Get-ChildItem (Join-Path $incomplete 'logs') -Filter '*.json').FullName) -Raw | ConvertFrom-Json
Assert ($report.exit_code -eq 1 -and $report.failure.recommendations.Count -gt 0) 'Structured error report missing.'
# A second real entry-point process must refuse work while the same-user lock is held.
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$mutex=[Threading.Mutex]::new($false,('Local\agent-brain-installer-'+$sid))
$held=$mutex.WaitOne(15000)
try {
    Assert $held 'Test lock unavailable; another installation is active.'
    $response=Invoke-Process powershell.exe @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $project 'Install-AgentBrain.ps1'),'-Action','Diagnose','-NoPause','-NonInteractive') -Quiet -AllowFailure
    Assert ($response.ExitCode -eq 1 -and $response.Output.Contains('INSTALL_BUSY')) 'Concurrent installer was not blocked.'
} finally {if ($held) {$mutex.ReleaseMutex()};$mutex.Dispose()}
Write-Host ("PASS: $script:checks installer checks on PowerShell $($PSVersionTable.PSVersion). Isolated fixtures: $root")
