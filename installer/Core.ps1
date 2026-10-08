# Shared implementation; importing this file performs no installation.
$script:secretValues=@();$script:runPath=$null;$script:runJson=$null
$script:progress=0;$script:step='Vorbereitung';$script:failure=$null
$script:clientResults=@();$script:dockerPath=$null

function Stop-Brain([string]$Code,[string]$Message) {
    $problem=[InvalidOperationException]::new($Message);$problem.Data['BrainCode']=$Code;throw $problem
}
function Assert-Windows {
    if ($env:OS -ne 'Windows_NT') { Stop-Brain 'PLATFORM' 'Dieser Installer benötigt Windows und PowerShell 5.1 oder neuer.' }
}
function Protect-Text([string]$Text) {
    $safe=$Text -replace '\x1b\[[0-9;]*[A-Za-z]',''
    foreach ($secret in $script:secretValues) { if ($secret) { $safe=$safe.Replace($secret,'[REDACTED]') } }
    $safe=$safe -replace '(?i)(postgres(?:ql)?://)[^\s/]+@','$1[REDACTED]@'
    $safe=$safe -replace '(?i)(https?://)[^\s/]+@','$1[REDACTED]@'
    $safe=$safe -replace '(?i)(Bearer\s+)[A-Za-z0-9._~+/-]+','$1[REDACTED]'
    $safe=$safe -replace '\b(?:sk-(?:proj-|ant-)?[A-Za-z0-9_-]{12,}|gh[pousr]_[A-Za-z0-9]{20,}|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)\b','[REDACTED]'
    $safe=$safe -replace '(?i)((?:password|passwd|db_password|api[_-]?key|access[_-]?token|bearer|authorization)\s*[=:]\s*)[^\s,;]+','$1[REDACTED]'
    return $safe
}
function Protect-Path([string]$Path) {
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $directory=Test-Path -LiteralPath $Path -PathType Container
    $suffix=if ($directory) {'(OI)(CI)(F)'} else {'(F)'}
    $output=& "$env:SystemRoot/System32/icacls.exe" $Path /inheritance:r /grant:r ("*${sid}:$suffix") ("*S-1-5-18:$suffix") 2>&1
    if ($LASTEXITCODE -ne 0) {Stop-Brain 'FILE_ACCESS' "Dateizugriff konnte nicht geschützt werden: $Path"}
    # Remove unrelated explicit grants from these installer-owned private artifacts.
    foreach ($rule in @((Get-Acl -LiteralPath $Path).Access)) {
        $other=$rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        if ($other -notin @($sid,'S-1-5-18') -and $rule.AccessControlType -eq 'Allow') {
            $output=& "$env:SystemRoot/System32/icacls.exe" $Path /remove:g ("*"+$other) 2>&1
            if ($LASTEXITCODE -ne 0) {Stop-Brain 'FILE_ACCESS' "Dateizugriff konnte nicht eingeschränkt werden: $Path"}
        }
    }
}
function Get-TextHash([string]$Text) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Write-Text {
    param([string]$Path,[string]$Text,[switch]$Private,[string]$ExpectedHash)
    $parent=Split-Path $Path -Parent;[IO.Directory]::CreateDirectory($parent) | Out-Null
    if (Test-Path -LiteralPath $Path) {
        $old=[IO.File]::ReadAllText($Path)
        if ($ExpectedHash -and (Get-TextHash $old) -ne $ExpectedHash) { Stop-Brain 'CONFIG_CHANGED' "Parallel geänderte Datei: $Path" }
        if ($old -ceq $Text) { if ($Private) { Protect-Path $Path };return }
    } elseif ($ExpectedHash -and $ExpectedHash -ne (Get-TextHash '')) { Stop-Brain 'CONFIG_CHANGED' "Parallel entfernte Datei: $Path" }
    $temporary=Join-Path $parent ('.brain-'+[guid]::NewGuid().ToString('N')+'.tmp')
    try {
        [IO.File]::WriteAllText($temporary,'',$utf8)
        if ($Private) { Protect-Path $temporary }
        [IO.File]::WriteAllText($temporary,$Text,$utf8)
        if (Test-Path -LiteralPath $Path) {
            if ($ExpectedHash -and (Get-TextHash ([IO.File]::ReadAllText($Path))) -ne $ExpectedHash) { Stop-Brain 'CONFIG_CHANGED' "Parallel geänderte Datei: $Path" }
            [IO.File]::Replace($temporary,$Path,[NullString]::Value)
        } else { [IO.File]::Move($temporary,$Path) }
        if ($Private) { Protect-Path $Path }
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
}
function Initialize-Run {
    if (-not $RunId) { $script:RunId=[guid]::NewGuid().ToString('N') }
    $directory=Join-Path $root 'logs';[IO.Directory]::CreateDirectory($directory) | Out-Null;Protect-Path $directory
    $script:runPath=Join-Path $directory ($RunId+'.log');$script:runJson=Join-Path $directory ($RunId+'.json')
    Write-Text $script:runPath '' -Private
    $path=Join-Path $root '.env'
    if (Test-Path -LiteralPath $path) {
        $match=[regex]::Match([IO.File]::ReadAllText($path),'(?m)^DB_PASSWORD\s*=\s*(.+?)\s*$')
        if ($match.Success) { $script:secretValues+=$match.Groups[1].Value.Trim('"',"'") }
    }
    Write-RunResult -1
}
function Write-RunResult([int]$ExitCode) {
    if (-not $script:runJson) { return }
    $result=@{run_id=$RunId;action=$Action;step=$script:step;progress=$script:progress;exit_code=$ExitCode;
        updated_at=[DateTimeOffset]::Now.ToString('o');failure=$script:failure;clients=@($script:clientResults);
        log=$script:runPath;dashboard_port=$script:activeDashboardPort;mcp_port=$script:activePort}
    Write-Text $script:runJson ($result | ConvertTo-Json -Depth 8) -Private
}
function Write-Event([string]$Level,[string]$Message) {
    $safe=Protect-Text $Message
    $color=switch ($Level) { 'OK' {'Green'} 'FEHLER' {'Red'} 'HINWEIS' {'Yellow'} 'SCHRITT' {'Cyan'} default {'Gray'} }
    Write-Host ('  {0,-8} {1}' -f $Level,$safe) -ForegroundColor $color
    if ($script:runPath) { [IO.File]::AppendAllText($script:runPath,((Get-Date -Format 'HH:mm:ss')+' ['+$Level+'] '+$safe+"`r`n"),$utf8) }
}
function Show-Header {
    Write-Host "`n  +----------------------------------------------------------+" -ForegroundColor DarkGreen
    Write-Host '  |  agent-brain  /  SETUP & VERWALTUNG                        |' -ForegroundColor Green
    Write-Host '  |  Lokal. Gemeinsames Wissen. Wiederholbar.                  |' -ForegroundColor DarkGreen
    Write-Host "  +----------------------------------------------------------+`n" -ForegroundColor DarkGreen
    Write-Event 'INFO' "Aktion: $Action | Arbeitsordner: $root"
}
function Set-Step([string]$Name,[int]$Percent) {
    $script:step=$Name;$script:progress=$Percent;Write-Event 'SCHRITT' $Name
    Write-Progress -Activity 'agent-brain' -Status $Name -PercentComplete $Percent -Completed:($Percent -eq 100)
    Write-RunResult -1
}
function Quote-Native([string]$Value) {
    return '"'+[regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'
}
function Set-ChildPowerShellEnvironment($Info) {
    # A PS7 parent may pass incompatible bundled modules to Windows PowerShell 5.1.
    if ($Info.FileName -match '(?i)[\\/]WindowsPowerShell[\\/]v1\.0[\\/]powershell\.exe$') {
        $Info.EnvironmentVariables['PSModulePath']=@((Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell/Modules'),(Join-Path $env:ProgramFiles 'WindowsPowerShell/Modules'),(Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/Modules')) -join ';'
    }
}
function Invoke-Process {
    param([string]$File,[string[]]$Arguments=@(),[int]$Timeout=120,[switch]$Quiet,[switch]$AllowFailure,[string]$Code='COMMAND_FAILED',[switch]$ComposeEnvironment)
    $command=Get-Command $File -ErrorAction SilentlyContinue
    if (-not $command) { Stop-Brain 'COMMAND_MISSING' "Nicht gefunden: $File" }
    $path=$command.Source
    if ([IO.Path]::GetExtension($path) -in @('.ps1','.cmd','.bat')) {
        # Encode data separately from code; npm shims run without a visible console.
        $payload=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((@{path=$path;args=@($Arguments)} | ConvertTo-Json -Compress -Depth 5)))
        $wrapper='[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);$OutputEncoding=[Console]::OutputEncoding;$ProgressPreference="SilentlyContinue";$ErrorActionPreference="Stop";$d=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+$payload+''')) | ConvertFrom-Json; $cliArguments=@($d.args); & $d.path @cliArguments; if ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE }'
        $path=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $Arguments=@('-NoProfile','-OutputFormat','Text','-ExecutionPolicy','Bypass','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wrapper)))
    }
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$path
    $info.Arguments=(@($Arguments | ForEach-Object { Quote-Native $_ }) -join ' ')
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.StandardOutputEncoding=[Text.Encoding]::UTF8;$info.StandardErrorEncoding=[Text.Encoding]::UTF8;$info.WorkingDirectory=$root
    Set-ChildPowerShellEnvironment $info
    if ($ComposeEnvironment) { foreach ($key in @('DB_PASSWORD','BRAIN_PORT','DASHBOARD_PORT','COMPOSE_PROFILES','COMPOSE_FILE')) { $info.EnvironmentVariables.Remove($key) } }
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info
    try {
        $null=$process.Start();$outTask=$process.StandardOutput.ReadToEndAsync();$errTask=$process.StandardError.ReadToEndAsync()
        $watch=[Diagnostics.Stopwatch]::StartNew();$lastPulse=0
        while (-not $process.WaitForExit(500)) {
            if ($watch.Elapsed.TotalSeconds -gt $Timeout) {
                try {& "$env:SystemRoot/System32/taskkill.exe" /PID $process.Id /T /F 2>$null | Out-Null} catch {try {$process.Kill()} catch {}}
                Stop-Brain 'TIMEOUT' "Zeitlimit ($Timeout s) bei $File. Bereits gestartete Docker-Dienste können weiterlaufen."
            }
            if (-not $Quiet -and $watch.Elapsed.TotalSeconds-$lastPulse -ge 15) { Write-Event 'INFO' ($script:step+' läuft ... '+[int]$watch.Elapsed.TotalSeconds+' s');$lastPulse=$watch.Elapsed.TotalSeconds }
        }
        $stdout=$outTask.GetAwaiter().GetResult();$stderr=$errTask.GetAwaiter().GetResult()
        $result=[pscustomobject]@{ExitCode=$process.ExitCode;Output=$stdout;Error=$stderr}
        if (-not $Quiet) {
            foreach ($line in (@(($stdout+"`n"+$stderr)-split '\r?\n' | Where-Object {$_.Trim()}) | Select-Object -Last 50)) { Write-Event 'DETAIL' $line }
        }
        if ($result.ExitCode -ne 0 -and -not $AllowFailure) { Stop-Brain $Code ("$File fehlgeschlagen (Exitcode $($result.ExitCode)). "+(Protect-Text ($stderr+"`n"+$stdout).Trim())) }
        return $result
    } finally { $process.Dispose() }
}
function Invoke-Compose {
    param([string[]]$Arguments,[switch]$Quiet,[switch]$AllowFailure,[int]$Timeout=120,[string]$Code='COMPOSE_FAILED')
    return Invoke-Process $script:dockerPath (@('compose','--project-name','agent-brain','--project-directory',$root,'--env-file',(Join-Path $root '.env'),'-f',$composeFile)+$Arguments) -Quiet:$Quiet -AllowFailure:$AllowFailure -Timeout $Timeout -Code $Code -ComposeEnvironment
}
function Get-Recommendations([string]$Code,[string]$Detail='') {
    switch ($Code) {
        'INSTALL_BUSY' { 'Das andere Setup-Fenster abschließen. Danach erneut starten.';break }
        'PLATFORM' { 'Auf einem 64-Bit-Windows-PC mit PowerShell 5.1 oder neuer starten.';break }
        'FILES_MISSING' { 'Das gesamte agent-brain-Paket entpacken, nicht nur die PS1-Datei kopieren.';break }
        'DOCKER_MISSING' { 'Im Assistenten Docker Desktop installieren aktivieren oder mit -InstallDocker starten.';'https://docs.docker.com/desktop/setup/install/windows-install/';break }
        'WINGET_MISSING' { 'App Installer aus dem Microsoft Store aktualisieren oder Docker Desktop von der offiziellen Website installieren.';break }
        'REBOOT_REQUIRED' { 'Windows neu starten, Docker Desktop öffnen und dessen Einrichtung abschließen. Dann denselben Installer erneut starten.';break }
        'DOCKER_ENGINE' { 'Docker Desktop öffnen und die Ersteinrichtung abschließen. Linux-Container verwenden.';'Falls WSL fehlt: wsl --install --no-distribution in einer administrativen PowerShell; danach Windows neu starten. Vorhandenes WSL mit wsl --update aktualisieren.';'Bei Virtualisierungsfehlern Virtualisierung im UEFI/BIOS aktivieren. Ein Neustart wird nicht erzwungen.';break }
        'REMOTE_DOCKER' { 'Mit docker context use desktop-linux den lokalen Kontext auswählen. DOCKER_HOST und DOCKER_CONTEXT auf Overrides prüfen.';break }
        'WINDOWS_CONTAINERS' { 'In Docker Desktop auf Linux-Container wechseln. Dann erneut starten.';break }
        'COMPOSE_VERSION' { 'Docker Desktop aktualisieren; Docker Compose v2.20 oder neuer wird benötigt.';break }
        'ENV_LOST' { 'Die ursprüngliche .env aus deinem bisherigen agent-brain-Ordner oder eigener Sicherung hierher kopieren.';'Datenbank-Volumes behalten. Kein neues Passwort erzeugen und keine Volumes löschen.';break }
        'ENV_INVALID' { 'Lokale .env prüfen: genau je ein DB_PASSWORD, BRAIN_PORT und DASHBOARD_PORT. Ports 1024-65535, unterschiedliche Werte.';'Das ursprüngliche Datenbankpasswort beibehalten; keine Zugangsdaten in Chats kopieren.';break }
        'PORT_CONFIG' { 'Bei bestehenden Installationen gelten die Ports in .env. Zum Wechseln .env bearbeiten und Clients erneut konfigurieren.';break }
        'PORT_BUSY' { 'Den genannten Port freigeben oder vor dem Start verschiedene freie Ports in .env festlegen.';'Fremde Anwendungen werden nicht beendet. Nach Portwechsel Clients neu konfigurieren.';break }
        'DISK_SPACE' { 'Auf dem genannten Laufwerk Platz schaffen. Zusätzlich den eigenen Speicherort von Docker Desktop prüfen.';break }
        'FILE_ACCESS' { 'Schreibrechte für den Arbeitsordner prüfen. Einen eigenen lokalen NTFS-Ordner verwenden; Windows-Schutz vor unberechtigten Ordneränderungen prüfen.';break }
        'CONFIG_INVALID' { 'Die genannte Client-Datei manuell reparieren oder aus backups/client-config wiederherstellen. Andere Einstellungen bleiben erhalten.';break }
        'CONFIG_CHANGED' { 'Client-Einstellungen während des Setups nicht parallel bearbeiten. Danach Configure erneut starten.';break }
        'CLIENT_FAILED' { 'Die Client-Ergebnisse im Protokoll prüfen; der Brain-Dienst kann bereits nutzbar sein.';'Mit -Action Configure -Agents <Client> gezielt erneut versuchen. CLI gegebenenfalls aktualisieren; Client neu starten.';break }
        'CLIENT_ENDPOINT' { 'Vorhandene agent-brain-Registrierung im genannten Client auf den angezeigten Endpunkt prüfen. Abweichende Einträge werden nicht gelöscht.';'Endpunkt manuell korrigieren und Configure erneut starten.';break }
        'TIMEOUT' { 'Mit -Action Diagnose prüfen, ob der Dienst bereits gestartet ist. Bei langsamem Download -TimeoutSeconds 1800 verwenden.';'Bei langsamem Docker-Start -DockerWaitSeconds 300 verwenden; Netzwerk, Proxy und freien Docker-Speicher prüfen.';break }
        'STACK_UNHEALTHY' { 'Mit -Action Diagnose Zustand prüfen. Docker Desktop und Ollama-Modellverfügbarkeit kontrollieren.';'Bei Datenbank-Anmeldefehlern die ursprüngliche .env wiederherstellen. Volumes nicht löschen.';break }
        'SERVICE_UNAVAILABLE' { 'Mit -Action Diagnose prüfen, danach -Action Start erneut versuchen. Lokale Proxy-Ausnahmen für 127.0.0.1 prüfen.';break }
        default {
            if ($Detail -match '(?i)access.*path|Zugriff.*(Pfad|Datei)') { 'Schreibrechte und Windows-Schutz für den genannten Ordner prüfen. Einen eigenen lokalen Arbeitsordner verwenden.' }
            elseif ($Detail -match '(?i)space|disk full|no space') { 'Freien Platz im Docker-Datenspeicher und auf dem Projektlaufwerk prüfen.' }
            elseif ($Detail -match '(?i)authentication|password|28P01') { 'Ursprüngliche .env wiederherstellen. Vorhandene Datenbank nicht zurücksetzen.' }
            elseif ($Detail -match '(?i)denied|unauthorized|forbidden|429|rate limit') { 'Registry-Zugriff, Docker-Anmeldung und Download-Limits in Docker Desktop prüfen.' }
            elseif ($Detail -match '(?i)network|timeout|TLS|certificate|resolve|proxy') { 'Internetverbindung, DNS und Proxy in Docker Desktop prüfen. Zertifikatsprüfungen aktiviert lassen.' }
            else { 'Mit -Action Diagnose Zustand prüfen. Das bereinigte Protokoll enthält den betroffenen Schritt.' }
            'Nach Behebung erneut starten. Daten und erfolgreiche Schritte werden beibehalten.'
        }
    }
}
function Assert-Package {
    foreach ($relative in @('compose.yaml','BRAIN-INSTRUCTIONS.md','server/Dockerfile','server/requirements.lock','server/schema.sql','server/server.py','server/dashboard.py','server/dashboard/index.html')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)) { Stop-Brain 'FILES_MISSING' "Datei fehlt: $relative" }
    }
    if (-not [Environment]::Is64BitOperatingSystem) { Stop-Brain 'PLATFORM' '64-Bit-Windows erforderlich.' }
    $probe=Join-Path $root ('.write-test-'+[guid]::NewGuid().ToString('N'))
    try { [IO.File]::WriteAllText($probe,'test') } finally { if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe } }
}
function Find-Docker {
    $command=Get-Command docker -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($candidate in @((Join-Path $env:ProgramFiles 'Docker/Docker/resources/bin/docker.exe'),(Join-Path $env:LOCALAPPDATA 'Programs/DockerDesktop/resources/bin/docker.exe'))) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}
function Assert-LocalDocker {
    $arguments=@('context','inspect')
    if ($env:DOCKER_CONTEXT) {$arguments+=$env:DOCKER_CONTEXT}
    $context=Invoke-Process $script:dockerPath $arguments -Quiet -AllowFailure
    if ($context.ExitCode -ne 0) {Stop-Brain 'REMOTE_DOCKER' 'Docker-Kontext kann nicht geprüft werden. Lokalen Kontext kontrollieren.'}
    $contexts=$context.Output | ConvertFrom-Json
    $endpoint=$contexts[0].Endpoints.docker.Host
    # DOCKER_CONTEXT has precedence over DOCKER_HOST in Docker itself.
    if ($env:DOCKER_HOST -and -not $env:DOCKER_CONTEXT) {$endpoint=$env:DOCKER_HOST}
    if (-not $endpoint -or $endpoint -notmatch '^(npipe:|unix:|tcp://(localhost|127\.0\.0\.1|\[::1\])(:|/|$))') {Stop-Brain 'REMOTE_DOCKER' 'Entfernter oder unbekannter Docker-Endpunkt aktiv; agent-brain soll auf diesem PC laufen.'}
}
function Ensure-Docker {
    param([switch]$NoStart)
    $script:engineOffline=$false
    $script:dockerPath=Find-Docker
    if (-not $script:dockerPath) {
        if (-not $InstallDocker) { Stop-Brain 'DOCKER_MISSING' 'Docker Desktop ist nicht installiert oder nicht auffindbar.' }
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Stop-Brain 'WINGET_MISSING' 'Windows-Paketverwaltung winget fehlt.' }
        Write-Event 'INFO' 'Docker Desktop wird über winget installiert. Windows kann eine Freigabe anfordern.'
        $installation=Invoke-Process winget @('install','--exact','--id','Docker.DockerDesktop','--source','winget','--accept-package-agreements','--accept-source-agreements','--disable-interactivity') -Timeout $TimeoutSeconds -AllowFailure
        if ($installation.ExitCode -in @(3010,1641,-1978334967)) { Stop-Brain 'REBOOT_REQUIRED' 'Docker-Installation benötigt einen Neustart.' }
        if ($installation.ExitCode -ne 0) { Stop-Brain 'DOCKER_INSTALL' "Docker-Installation fehlgeschlagen (Exitcode $($installation.ExitCode))." }
        $script:dockerPath=Find-Docker
        if (-not $script:dockerPath) { Stop-Brain 'REBOOT_REQUIRED' 'Docker installiert, in dieser Sitzung noch nicht auffindbar.' }
    }
    Assert-LocalDocker
    $engine=Invoke-Process $script:dockerPath @('info','--format','{{.OSType}}') -Quiet -AllowFailure -Timeout 15
    if ($engine.ExitCode -ne 0) {
        if ($NoStart) {
            if ($Action -eq 'Stop') {$script:engineOffline=$true;Write-Event 'OK' 'Lokale Docker-Engine bereits gestoppt; kein Neustart erforderlich.';return}
            Stop-Brain 'DOCKER_ENGINE' 'Docker-Engine ist gestoppt. Dieser Aufruf startet sie nicht automatisch.'
        }
        $desktop=@((Join-Path $env:ProgramFiles 'Docker/Docker/Docker Desktop.exe'),(Join-Path $env:LOCALAPPDATA 'Programs/DockerDesktop/Docker Desktop.exe')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $desktop) { Stop-Brain 'DOCKER_ENGINE' 'Docker-Engine nicht erreichbar; Docker Desktop nicht gefunden.' }
        Start-Process -FilePath $desktop -WindowStyle Hidden
        Write-Event 'INFO' "Docker Desktop startet; maximal $DockerWaitSeconds Sekunden Wartezeit."
        $watch=[Diagnostics.Stopwatch]::StartNew()
        do {
            Start-Sleep -Seconds 2
            $engine=Invoke-Process $script:dockerPath @('info','--format','{{.OSType}}') -Quiet -AllowFailure -Timeout 10
        } while ($engine.ExitCode -ne 0 -and $watch.Elapsed.TotalSeconds -lt $DockerWaitSeconds)
        if ($engine.ExitCode -ne 0) { Stop-Brain 'DOCKER_ENGINE' 'Docker Desktop wurde innerhalb der Wartezeit nicht bereit.' }
    }
    if ($engine.Output.Trim() -ne 'linux') { Stop-Brain 'WINDOWS_CONTAINERS' 'Docker verwendet Windows-Container; der Stack braucht Linux-Container.' }
    $version=Invoke-Process $script:dockerPath @('compose','version','--short') -Quiet -AllowFailure
    $match=[regex]::Match($version.Output,'(\d+)\.(\d+)\.(\d+)')
    if ($version.ExitCode -ne 0 -or -not $match.Success -or [version]$match.Value -lt [version]'2.20.0') { Stop-Brain 'COMPOSE_VERSION' 'Docker Compose v2.20 oder neuer fehlt.' }
    Write-Event 'OK' ('Lokale Linux-Engine und Docker Compose '+$match.Value+' bereit.')
}
function Read-Environment([string]$Path) {
    $text=[IO.File]::ReadAllText($Path);$values=@{}
    foreach ($line in ($text -split '\r?\n')) {
        if ($line -match '^\s*(#|$)') { continue }
        if ($line -notmatch '^([A-Z_]+)=(.*)$') { Stop-Brain 'ENV_INVALID' 'Die .env enthält eine ungültige Zeile.' }
        $key=$Matches[1];$value=$Matches[2].Trim()
        if ($values.ContainsKey($key)) { Stop-Brain 'ENV_INVALID' "Doppelter Schlüssel in .env: $key" }
        $values[$key]=$value
    }
    if (-not $values.ContainsKey('DB_PASSWORD') -or $values.DB_PASSWORD -notmatch '^[a-zA-Z0-9_-]{16,128}$') { Stop-Brain 'ENV_INVALID' 'Internes DB_PASSWORD fehlt oder hat inkompatibles Format.' }
    $script:secretValues+=$values.DB_PASSWORD
    foreach ($key in @('BRAIN_PORT','DASHBOARD_PORT')) {
        if (-not $values.ContainsKey($key)) { continue };$value=0
        if (-not [int]::TryParse($values[$key],[ref]$value) -or $value -lt 1024 -or $value -gt 65535) { Stop-Brain 'ENV_INVALID' "Ungültiger Port: $key" }
    }
    if (-not $values.ContainsKey('BRAIN_PORT')) { Stop-Brain 'ENV_INVALID' 'BRAIN_PORT fehlt in .env.' }
    if ($values.DASHBOARD_PORT -eq $values.BRAIN_PORT) { Stop-Brain 'ENV_INVALID' 'MCP und Dashboard brauchen unterschiedliche Ports.' }
    return [pscustomobject]@{Text=$text;Values=$values}
}
function Assert-PortNumbers([int]$Mcp,[int]$Dashboard) {
    if ($Mcp -lt 1024 -or $Mcp -gt 65535 -or $Dashboard -lt 1024 -or $Dashboard -gt 65535 -or $Mcp -eq $Dashboard) { Stop-Brain 'ENV_INVALID' 'Ports müssen 1024-65535 und verschieden sein.' }
}
function Ensure-Environment {
    $path=Join-Path $root '.env'
    if (-not (Test-Path -LiteralPath $path)) {
        if ($Action -notin @('Install','Start')) { Stop-Brain 'ENV_LOST' 'Lokale .env fehlt. Zuerst installieren oder Originaldatei wiederherstellen.' }
        $volume=Invoke-Process $script:dockerPath @('volume','ls','--filter','name=^agent-brain_brain-data$','--format','{{.Name}}') -Quiet
        if ($volume.Output.Trim()) { Stop-Brain 'ENV_LOST' 'Datenbank-Volume vorhanden, .env fehlt. Kein neues Passwort erzeugt.' }
        Assert-PortNumbers $Port $DashboardPort
        $random=[byte[]]::new(32);$rng=[Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($random) } finally { $rng.Dispose() }
        $password=[BitConverter]::ToString($random).Replace('-','').ToLowerInvariant();$script:secretValues+=$password
        Write-Text $path "DB_PASSWORD=$password`nBRAIN_PORT=$Port`nDASHBOARD_PORT=$DashboardPort`n" -Private
        Write-Event 'OK' 'Lokale Einstellungen angelegt und Dateizugriff geschützt.'
    }
    $configuration=Read-Environment $path
    if (-not $configuration.Values.ContainsKey('DASHBOARD_PORT')) {
        Assert-PortNumbers ([int]$configuration.Values.BRAIN_PORT) $DashboardPort
        Write-Text $path ($configuration.Text.TrimEnd()+"`nDASHBOARD_PORT=$DashboardPort`n") -Private -ExpectedHash (Get-TextHash $configuration.Text)
        $configuration=Read-Environment $path;Write-Event 'OK' 'Vorhandene Einstellungen um Dashboard-Port ergänzt.'
    }
    $script:activePort=[int]$configuration.Values.BRAIN_PORT;$script:activeDashboardPort=[int]$configuration.Values.DASHBOARD_PORT
    foreach ($name in @('Port','DashboardPort')) {
        $actual=if ($name -eq 'Port') { $script:activePort } else { $script:activeDashboardPort }
        if ($script:PSBoundParametersSnapshot.ContainsKey($name) -and (Get-Variable $name -ValueOnly) -ne $actual) { Stop-Brain 'PORT_CONFIG' "Parameter $name widerspricht gespeichertem Port $actual in .env." }
    }
    Protect-Path $path
    Write-Event 'OK' "Einstellungen verwendet: MCP $script:activePort, Dashboard $script:activeDashboardPort."
}
function Get-StackStatus {
    $response=Invoke-Compose @('ps','--all','--format','json') -Quiet -AllowFailure
    if ($response.ExitCode -ne 0) { return @() };$text=$response.Output.Trim()
    if (-not $text) { return @() }
    if ($text.StartsWith('[')) { $objects=$text | ConvertFrom-Json;return @($objects) }
    return @($text -split '\r?\n' | Where-Object {$_.Trim()} | ForEach-Object {$_ | ConvertFrom-Json})
}
function Test-StackHealthy($Services) {
    foreach ($name in @('postgres','ollama','mcp','dashboard')) {
        $service=@($Services | Where-Object {$_.Service -eq $name})
        if ($service.Count -ne 1 -or $service[0].State -ne 'running') { return $false }
        if ($name -ne 'ollama' -and $service[0].Health -ne 'healthy') { return $false }
    };return $true
}
function Assert-ResourcesAndPorts {
    $drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($root))
    if ($drive.IsReady -and $drive.AvailableFreeSpace -lt 2GB) { Stop-Brain 'DISK_SPACE' ('Weniger als 2 GB frei auf '+$drive.Name) }
    try { if ((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory -lt 8GB) { Write-Event 'HINWEIS' 'Unter 8 GB RAM: Docker und lokale Embeddings können langsam sein.' } }
    catch { Write-Event 'HINWEIS' 'RAM-Prüfung nicht verfügbar; Dienstprüfungen bleiben aktiv.' }
    $status=@(Get-StackStatus);$listeners=@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners())
    foreach ($portValue in @($script:activePort,$script:activeDashboardPort)) {
        if (-not @($listeners | Where-Object {$_.Port -eq $portValue}).Count) { continue }
        $owner=@($status | Where-Object {$_.State -eq 'running' -and @($_.Publishers | Where-Object {$_.PublishedPort -eq $portValue -and $_.URL -eq '127.0.0.1'}).Count})
        if (-not $owner.Count) { Stop-Brain 'PORT_BUSY' "Port $portValue wird von einer anderen Anwendung verwendet." }
    }
}
function Get-StackFingerprint {
    $paths=@((Get-Item -LiteralPath $composeFile),(Get-Item -LiteralPath (Join-Path $root '.env')))
    $paths+=@(Get-ChildItem -LiteralPath (Join-Path $root 'server') -File -Recurse | Where-Object {$_.FullName -notmatch '[\\/](__pycache__|\.pytest_cache)[\\/]'})
    [string[]]$manifest=@($paths | ForEach-Object {$_.FullName.Substring($root.Length)+':'+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash})
    [Array]::Sort($manifest,[StringComparer]::Ordinal)
    return Get-TextHash ($manifest -join "`n")
}
function Invoke-WithRetry([scriptblock]$Operation) {
    for ($attempt=1;$attempt -le $Retries;$attempt++) {
        try { & $Operation;return }
        catch {
            $transient=$_.Exception.Message -match '(?i)temporary|temporarily|i/o timeout|connection reset|unexpected EOF|TLS handshake timeout|network is unreachable|no such host|429|too many requests|502|503|504'
            if (-not $transient -or $attempt -eq $Retries) { throw }
            Write-Event 'HINWEIS' "Vorübergehender Netzwerkfehler; Versuch $($attempt+1)/$Retries."
            Start-Sleep -Seconds ([Math]::Min(12,3*$attempt))
        }
    }
}
function Get-LocalJson([string]$Url) {
    $request=[Net.HttpWebRequest]::Create($Url);$request.Proxy=$null;$request.Timeout=5000;$request.ReadWriteTimeout=5000
    $response=$request.GetResponse()
    try { $reader=[IO.StreamReader]::new($response.GetResponseStream());try { return $reader.ReadToEnd() | ConvertFrom-Json } finally {$reader.Dispose()} }
    finally {$response.Dispose()}
}
function Assert-ServiceEndpoints {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    do {
        try {
            $health=Get-LocalJson "http://127.0.0.1:$script:activeDashboardPort/health"
            $overview=Get-LocalJson "http://127.0.0.1:$script:activeDashboardPort/api/overview"
            if ($health.status -ne 'ok' -or $null -eq $overview.stats.active) { throw 'Dashboard identity mismatch.' }
            return
        } catch { if ($watch.Elapsed.TotalSeconds -gt 30) { Stop-Brain 'SERVICE_UNAVAILABLE' 'Dashboard antwortet nach Start nicht erwartungsgemäß.' };Start-Sleep -Seconds 2 }
    } while ($true)
}
function Start-Brain {
    $fingerprint=Get-StackFingerprint;$statePath=Join-Path $root 'installer-state.json';$previous=$null
    if (Test-Path -LiteralPath $statePath) { try {$previous=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json} catch {Write-Event 'HINWEIS' 'Unlesbarer Installationsstatus wird nach Prüfung neu erzeugt.'} }
    if ($previous -and $previous.fingerprint -eq $fingerprint -and (Test-StackHealthy @(Get-StackStatus))) {
        Assert-ServiceEndpoints;Write-Event 'OK' 'Stack aktuell und gesund. Kein Neubau und kein erneuter Modell-Download.';return
    }
    $build=-not $previous -or $previous.fingerprint -ne $fingerprint
    $images=Invoke-Process $script:dockerPath @('image','inspect','agent-brain-mcp','agent-brain-dashboard','--format','{{.Id}}') -Quiet -AllowFailure
    if ($images.ExitCode -ne 0) {$build=$true}
    $arguments=@('up','-d','--wait','--wait-timeout',[string]$TimeoutSeconds)
    if ($build) {$arguments+='--build'} else {$arguments+='--no-build'}
    Invoke-WithRetry {
        try {$null=Invoke-Compose $arguments -Timeout $TimeoutSeconds}
        catch {
            $original=$_
            try {
                $logs=Invoke-Compose @('logs','--no-color','--tail','40','model-init') -Quiet -AllowFailure -Timeout 15
                $detail=Protect-Text ($logs.Output+$logs.Error)
                if ($detail.Trim()) {Write-Event 'DETAIL' $detail}
            } catch {$detail=''}
            $code=if ($original.Exception.Data['BrainCode']) {[string]$original.Exception.Data['BrainCode']} else {'COMPOSE_FAILED'}
            Stop-Brain $code ($original.Exception.Message+"`n"+$detail)
        }
    }
    if (-not (Test-StackHealthy @(Get-StackStatus))) {Stop-Brain 'STACK_UNHEALTHY' 'Nicht alle Dienste sind gesund gestartet.'}
    Assert-ServiceEndpoints
    Write-Text $statePath (@{version=2;fingerprint=$fingerprint;verified_at=[DateTimeOffset]::Now.ToString('o')} | ConvertTo-Json) -Private
    Write-Event 'OK' 'Stack und Dashboard erfolgreich geprüft.'
}
function Show-Diagnostics {
    Write-Event 'INFO' 'Diagnose startet oder installiert keine Dienste.'
    $script:dockerPath=Find-Docker
    Write-Event 'INFO' ('PowerShell '+$PSVersionTable.PSVersion+' | Windows '+[Environment]::OSVersion.Version)
    Write-Event 'INFO' ('Erkannte Clients: '+(@(Get-DetectedAgents)-join ', '))
    if (-not $script:dockerPath) {Stop-Brain 'DOCKER_MISSING' 'Docker CLI fehlt.'}
    Assert-LocalDocker
    $info=Invoke-Process $script:dockerPath @('info','--format','{{.OSType}}') -Quiet -AllowFailure -Timeout 15
    if ($info.ExitCode -ne 0) {Stop-Brain 'DOCKER_ENGINE' 'Docker-Engine nicht erreichbar.'}
    Write-Event 'INFO' ('Docker-Engine: '+$info.Output.Trim())
    $envFile=Join-Path $root '.env'
    if (-not (Test-Path -LiteralPath $envFile)) {Stop-Brain 'ENV_LOST' 'Lokale .env fehlt.'}
    $config=Read-Environment $envFile;$script:activePort=[int]$config.Values.BRAIN_PORT;$script:activeDashboardPort=[int]$config.Values.DASHBOARD_PORT
    $null=Invoke-Compose @('config','--quiet') -Code 'ENV_INVALID'
    $status=@(Get-StackStatus)
    foreach ($service in $status) {Write-Event 'INFO' ("$($service.Service): $($service.State) $($service.Health)")}
    if (-not (Test-StackHealthy $status)) {Stop-Brain 'STACK_UNHEALTHY' 'Mindestens ein Dienst fehlt, ist gestoppt oder ungesund.'}
    Assert-ServiceEndpoints;Write-Event 'OK' 'Dienste und Website erreichbar.'
}
function Invoke-AgentBrainAction {
    Set-Step 'Paket und Schreibzugriff prüfen' 5;Assert-Package
    if ($Action -eq 'Diagnose') {Show-Diagnostics;return}
    if ($Action -eq 'Configure') {
        Set-Step 'Vorhandene Einstellungen lesen' 25
        if (-not (Test-Path -LiteralPath (Join-Path $root '.env'))) {Stop-Brain 'ENV_LOST' 'Vor Client-Konfiguration fehlt .env.'}
        $configuration=Read-Environment (Join-Path $root '.env');$script:activePort=[int]$configuration.Values.BRAIN_PORT;$script:activeDashboardPort=[int]$configuration.Values.DASHBOARD_PORT
        Configure-Agents;return
    }
    Set-Step 'Docker und Linux-Engine prüfen' 15;Ensure-Docker -NoStart:($Action -in @('Stop','Status','Backup','Test'))
    if ($script:engineOffline -and $Action -eq 'Stop') {return}
    Set-Step 'Lokale Einstellungen prüfen' 30;Ensure-Environment
    $null=Invoke-Compose @('config','--quiet') -Code 'ENV_INVALID'
    switch ($Action) {
        {$_ -in @('Install','Start')} {
            Set-Step 'Ressourcen und Ports prüfen' 40;Assert-ResourcesAndPorts
            Set-Step 'Dienste installieren oder fortsetzen' 55;Start-Brain
            Set-Step 'Client-Anbindung' 90
            Write-Event 'OK' "MCP: http://127.0.0.1:$script:activePort/mcp"
            Write-Event 'OK' "Dashboard: http://127.0.0.1:$script:activeDashboardPort"
            if (-not $SkipAgentSetup) {Configure-Agents}
        }
        'Stop' {Set-Step 'Dienste stoppen, Daten behalten' 60;$null=Invoke-Compose @('stop')}
        'Status' {$null=Invoke-Compose @('ps','--all')}
        'Test' {
            Set-Step 'MCP und Embeddings testen' 55;$null=Invoke-Compose @('exec','-T','mcp','python','integration_test.py') -Timeout $TimeoutSeconds
            Set-Step 'Dashboard und Wissenskarte testen' 80;$null=Invoke-Compose @('exec','-T','dashboard','python','dashboard_test.py') -Timeout $TimeoutSeconds
        }
        'Backup' {
            Set-Step 'Datenbanksicherung erstellen' 60
            $dir=Join-Path $root 'backups/database';[IO.Directory]::CreateDirectory($dir) | Out-Null;Protect-Path $dir
            $file='agent-brain-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.dump';$destination=Join-Path $dir $file
            $partial=$destination+'.partial'
            try {
                $null=Invoke-Compose @('exec','-T','postgres','pg_dump','-U','agent_brain','-d','agent_brain','-Fc','-f',"/tmp/$file") -Timeout $TimeoutSeconds
                $null=Invoke-Compose @('exec','-T','postgres','pg_restore','--list',"/tmp/$file") -Quiet
                $null=Invoke-Compose @('cp',"postgres:/tmp/$file",$partial)
                if ((Get-Item -LiteralPath $partial).Length -eq 0) {Stop-Brain 'BACKUP_FAILED' 'Sicherung ist leer.'}
                [IO.File]::Move($partial,$destination)
                Protect-Path $destination;Write-Event 'OK' "Sicherung: $destination"
            } finally {
                $null=Invoke-Compose @('exec','-T','postgres','rm','-f',"/tmp/$file") -Quiet -AllowFailure
                if (Test-Path -LiteralPath $partial) {Remove-Item -LiteralPath $partial}
            }
        }
    }
}
