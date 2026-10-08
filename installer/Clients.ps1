# Client settings are changed only after selection. Existing unrelated settings survive.
$script:transaction=$null
function Backup-Config([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {return}
    $dir=Join-Path $root 'backups/client-config';[IO.Directory]::CreateDirectory($dir) | Out-Null;Protect-Path $dir
    $name=(Split-Path $Path -Leaf)+'.'+[guid]::NewGuid().ToString('N')+'.bak'
    $target=Join-Path $dir $name;Copy-Item -LiteralPath $Path -Destination $target;Protect-Path $target
}
function Track-Config([string]$Path) {
    if ($null -eq $script:transaction) {return}
    if (@($script:transaction | Where-Object {$_.Path -eq $Path}).Count) {return}
    $exists=Test-Path -LiteralPath $Path
    $content=if ($exists) {[IO.File]::ReadAllText($Path)} else {''}
    $bytes=if ($exists) {[IO.File]::ReadAllBytes($Path)} else {$null}
    $script:transaction+= [pscustomobject]@{Path=$Path;Existed=$exists;Content=$content;Bytes=$bytes;After=$null}
}
function Record-Config([string]$Path) {
    foreach ($item in @($script:transaction | Where-Object {$_.Path -eq $Path})) {
        $item.After=if (Test-Path -LiteralPath $Path) {Get-TextHash ([IO.File]::ReadAllText($Path))} else {Get-TextHash ''}
    }
}
function Undo-ClientChanges {
    foreach ($item in @($script:transaction)) {
        if (-not $item.After) {continue}
        $current=if (Test-Path -LiteralPath $item.Path) {[IO.File]::ReadAllText($item.Path)} else {''}
        if ((Get-TextHash $current) -ne $item.After) {Write-Event 'HINWEIS' "Rollback ausgelassen: parallel geänderte Datei $($item.Path). Sicherung prüfen.";continue}
        if ($item.Existed) {
            # Restore original bytes (including BOM/line endings), guarded against concurrent changes.
            $temp=Join-Path (Split-Path $item.Path -Parent) ('.brain-rollback-'+[guid]::NewGuid().ToString('N'))
            try {
                [IO.File]::WriteAllText($temp,'');Protect-Path $temp;[IO.File]::WriteAllBytes($temp,$item.Bytes)
                if ((Get-TextHash ([IO.File]::ReadAllText($item.Path))) -ne $item.After) {throw 'Concurrent edit during rollback.'}
                [IO.File]::Replace($temp,$item.Path,[NullString]::Value)
            } finally {if (Test-Path -LiteralPath $temp) {Remove-Item -LiteralPath $temp}}
        } elseif (Test-Path -LiteralPath $item.Path) {Remove-Item -LiteralPath $item.Path}
        Write-Event 'HINWEIS' "Client-Änderung zurückgenommen: $($item.Path)"
    }
}
function Get-InstructionText([string]$Path) {
    $block=[IO.File]::ReadAllText((Join-Path $root 'BRAIN-INSTRUCTIONS.md')).Trim()
    $old=if (Test-Path -LiteralPath $Path) {[IO.File]::ReadAllText($Path)} else {''}
    $start=[regex]::Matches($old,'<!-- agent-brain:start -->').Count;$end=[regex]::Matches($old,'<!-- agent-brain:end -->').Count
    if ($start -ne $end -or $start -gt 1) {Stop-Brain 'CONFIG_INVALID' "Unvollständige oder doppelte agent-brain-Markierungen in $Path"}
    $pattern='(?s)<!-- agent-brain:start -->.*?<!-- agent-brain:end -->'
    if ($start -eq 1 -and $old -notmatch $pattern) {Stop-Brain 'CONFIG_INVALID' "Falsche Reihenfolge der Markierungen in $Path"}
    $new=if ($start) {[regex]::Replace($old,$pattern,[Text.RegularExpressions.MatchEvaluator]{param($m) $block})} else {$old.TrimEnd()+"`r`n`r`n"+$block+"`r`n"}
    return [pscustomobject]@{Old=$old;New=$new}
}
function Add-Instructions([string]$Path) {
    $text=Get-InstructionText $Path
    if ($text.Old -ceq $text.New) {Write-Event 'OK' "Instructions bereits aktuell: $Path";return}
    Track-Config $Path;Backup-Config $Path
    Write-Text $Path $text.New -Private -ExpectedHash (Get-TextHash $text.Old)
    Record-Config $Path
}
function Merge-McpJson($Path,$Entry) {
    $old=if (Test-Path -LiteralPath $Path) {[IO.File]::ReadAllText($Path)} else {''}
    try {$config=if ($old) {$old | ConvertFrom-Json -ErrorAction Stop} else {[pscustomobject]@{}}}
    catch {Stop-Brain 'CONFIG_INVALID' "Ungültiges JSON in $Path"}
    if ($config -isnot [pscustomobject]) {Stop-Brain 'CONFIG_INVALID' "JSON-Objekt erwartet in $Path"}
    if (-not $config.PSObject.Properties['mcpServers']) {$config | Add-Member mcpServers ([pscustomobject]@{})}
    if ($config.mcpServers -isnot [pscustomobject]) {Stop-Brain 'CONFIG_INVALID' "Ungültige mcpServers in $Path"}
    $existing=$config.mcpServers.PSObject.Properties['agent-brain']
    if ($existing -and $existing.Value -isnot [pscustomobject]) {Stop-Brain 'CONFIG_INVALID' "Ungültiger agent-brain-Eintrag in $Path"}
    $changed=-not $existing
    $merged=if ($existing) {$existing.Value} else {[pscustomobject]@{}}
    foreach ($property in $Entry.PSObject.Properties) {
        $value=$merged.PSObject.Properties[$property.Name]
        if (-not $value -or (ConvertTo-Json -InputObject $value.Value -Compress -Depth 20) -cne (ConvertTo-Json -InputObject $property.Value -Compress -Depth 20)) {$changed=$true}
        $merged | Add-Member -MemberType NoteProperty -Name $property.Name -Value $property.Value -Force
    }
    if (-not $changed) {Write-Event 'OK' "MCP-Konfiguration bereits aktuell: $Path";return}
    $config.mcpServers | Add-Member -MemberType NoteProperty -Name 'agent-brain' -Value $merged -Force
    $new=$config | ConvertTo-Json -Depth 40
    Track-Config $Path;Backup-Config $Path;Write-Text $Path $new -Private -ExpectedHash (Get-TextHash $old);Record-Config $Path
}
function Get-DetectedAgents {
    $codexRoot=if ($env:CODEX_HOME) {$env:CODEX_HOME} else {Join-Path $env:USERPROFILE '.codex'}
    $claudeRoot=if ($env:CLAUDE_CONFIG_DIR) {$env:CLAUDE_CONFIG_DIR} else {Join-Path $env:USERPROFILE '.claude'}
    if ((Get-Command codex -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath (Join-Path $codexRoot 'config.toml'))) {'Codex'}
    if ((Get-Command claude -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath (Join-Path $claudeRoot 'CLAUDE.md'))) {'ClaudeCode'}
    if ((Get-Command gemini -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath "$env:USERPROFILE/.gemini/settings.json")) {'GeminiCLI'}
    if ((Get-Command cursor -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath "$env:LOCALAPPDATA/Programs/cursor/Cursor.exe") -or (Test-Path -LiteralPath "$env:APPDATA/Cursor")) {'Cursor'}
    $desktop=Test-Path -LiteralPath "$env:APPDATA/Claude"
    if (-not $desktop -and (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {try {$desktop=[bool](Get-AppxPackage -Name '*Claude*' -ErrorAction Stop)} catch {}}
    if ($desktop) {'ClaudeDesktop'}
}
function Configure-OneAgent([string]$Agent,[string]$Endpoint) {
    switch ($Agent) {
        'Codex' {
            if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {Stop-Brain 'CLIENT_FAILED' 'Codex CLI fehlt; Desktop allein kann nicht automatisch konfiguriert werden.'}
            $codexRoot=if ($env:CODEX_HOME) {$env:CODEX_HOME} else {Join-Path $env:USERPROFILE '.codex'}
            $configPath=Join-Path $codexRoot 'config.toml';$instructions=Join-Path $codexRoot 'AGENTS.md'
            if (Test-Path -LiteralPath (Join-Path $codexRoot 'AGENTS.override.md')) {$instructions=Join-Path $codexRoot 'AGENTS.override.md'}
            $null=Get-InstructionText $instructions
            $existing=Invoke-Process codex @('mcp','get','agent-brain','--json') -Quiet -AllowFailure
            if ($existing.ExitCode -eq 0) {
                $entry=$existing.Output | ConvertFrom-Json
                if ($entry.transport.type -ne 'streamable_http' -or $entry.transport.url -ne $Endpoint -or $entry.enabled -eq $false) {Stop-Brain 'CLIENT_ENDPOINT' "Codex: vorhandene Registrierung weicht von $Endpoint ab oder ist deaktiviert."}
                Write-Event 'OK' 'Codex MCP bereits registriert.'
            } else {
                # Validate TOML via Codex before interpreting a failed get as a missing entry.
                $list=Invoke-Process codex @('mcp','list','--json') -Quiet -AllowFailure
                if ($list.ExitCode -ne 0) {Stop-Brain 'CONFIG_INVALID' "Codex kann $configPath nicht lesen. Bestehende Datei bleibt erhalten."}
                Track-Config $configPath;Backup-Config $configPath
                $added=Invoke-Process codex @('mcp','add','agent-brain','--url',$Endpoint) -Quiet -AllowFailure
                Record-Config $configPath
                if ($added.ExitCode -ne 0) {Stop-Brain 'CLIENT_FAILED' 'Codex MCP-Registrierung fehlgeschlagen.'}
            }
            Add-Instructions $instructions
        }
        'ClaudeCode' {
            if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {Stop-Brain 'CLIENT_FAILED' 'Claude Code CLI fehlt.'}
            $claudeRoot=if ($env:CLAUDE_CONFIG_DIR) {$env:CLAUDE_CONFIG_DIR} else {Join-Path $env:USERPROFILE '.claude'}
            $configPath=if ($env:CLAUDE_CONFIG_DIR) {Join-Path $claudeRoot '.claude.json'} else {Join-Path $env:USERPROFILE '.claude.json'}
            $instructions=Join-Path $claudeRoot 'CLAUDE.md';$null=Get-InstructionText $instructions
            if (Test-Path -LiteralPath $configPath) {try {$null=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json} catch {Stop-Brain 'CONFIG_INVALID' "Ungültiges JSON in $configPath"}}
            $existing=Invoke-Process claude @('mcp','get','agent-brain') -Quiet -AllowFailure -Timeout 45
            if ($existing.ExitCode -eq 0) {
                if (-not $existing.Output.Contains($Endpoint)) {Stop-Brain 'CLIENT_ENDPOINT' "Claude Code: Registrierung weicht von $Endpoint ab."}
                Write-Event 'OK' 'Claude Code MCP bereits registriert.'
            } else {
                Track-Config $configPath;Backup-Config $configPath
                $added=Invoke-Process claude @('mcp','add','--scope','user','--transport','http','agent-brain',$Endpoint) -Quiet -AllowFailure
                Record-Config $configPath
                if ($added.ExitCode -ne 0) {Stop-Brain 'CLIENT_FAILED' 'Claude Code MCP-Registrierung fehlgeschlagen.'}
            }
            Add-Instructions $instructions
        }
        'GeminiCLI' {
            $instructions=Join-Path $env:USERPROFILE '.gemini/GEMINI.md';$null=Get-InstructionText $instructions
            Merge-McpJson (Join-Path $env:USERPROFILE '.gemini/settings.json') ([pscustomobject]@{httpUrl=$Endpoint})
            Add-Instructions $instructions
        }
        'Cursor' {
            Merge-McpJson (Join-Path $env:USERPROFILE '.cursor/mcp.json') ([pscustomobject]@{url=$Endpoint})
            Write-Event 'HINWEIS' 'Cursor: BRAIN-INSTRUCTIONS.md in Settings > Rules > User Rules einfügen.'
        }
        'ClaudeDesktop' {
            $entry=[pscustomobject]@{command=$script:dockerPath;args=@('compose','--project-name','agent-brain','--project-directory',$root,'--env-file',(Join-Path $root '.env'),'-f',$composeFile,'exec','-T','mcp','python','server.py','--stdio')}
            if (-not $entry.command) {$entry.command=Find-Docker}
            if (-not $entry.command) {Stop-Brain 'DOCKER_MISSING' 'Docker CLI für Claude Desktop fehlt.'}
            $script:dockerPath=$entry.command;Assert-LocalDocker
            Merge-McpJson (Join-Path $env:APPDATA 'Claude/claude_desktop_config.json') $entry
            Write-Event 'HINWEIS' 'Claude Desktop: BRAIN-INSTRUCTIONS.md in Profil-/Projektanweisungen einfügen.'
        }
    }
}
function Configure-Agents {
    $detected=@(Get-DetectedAgents);$selection=@($Agents | Where-Object {$_})
    if (-not $selection.Count) {
        if ($NonInteractive) {Write-Event 'INFO' 'Keine Clients ausgewählt; automatische Anbindung ausgelassen.';return}
        if (-not $detected.Count) {Write-Event 'HINWEIS' 'Keine unterstützten Clients erkannt. Manuelle Anleitung in README.md.';return}
        Write-Event 'INFO' 'Erkannte Clients (CLI, Installation oder vorhandene Konfiguration):'
        for ($i=0;$i -lt $detected.Count;$i++) {Write-Host "  [$($i+1)] $($detected[$i])" -ForegroundColor Green}
        do {
            $choice=Read-Host '  Nummern mit Komma; A=alle; Enter=überspringen'
            if (-not $choice) {return}
            $valid=$true;$selection=@()
            if ($choice -eq 'A') {$selection=$detected}
            else {
                foreach ($part in ($choice -split ',')) {
                    $number=0
                    if (-not [int]::TryParse($part.Trim(),[ref]$number) -or $number -lt 1 -or $number -gt $detected.Count) {$valid=$false;break}
                    $selection+=$detected[$number-1]
                }
            }
            if (-not $valid) {Write-Event 'HINWEIS' 'Ungültige Auswahl. Bitte eine der angezeigten Nummern verwenden.'}
        } while (-not $valid)
    }
    $endpoint="http://127.0.0.1:$script:activePort/mcp";$failed=$false
    foreach ($agent in @($selection | Select-Object -Unique)) {
        $script:transaction=@()
        try {
            if ($agent -notin $detected) {Stop-Brain 'CLIENT_FAILED' "Client nicht erkannt: $agent"}
            Write-Event 'INFO' "Konfiguriere $agent ..."
            Configure-OneAgent $agent $endpoint
            $script:clientResults+=@{name=$agent;status='configured';manual_instructions=($agent -in @('Cursor','ClaudeDesktop'))}
            Write-Event 'OK' "$agent angebunden. Client neu starten."
        } catch {
            $failed=$true
            try {Undo-ClientChanges} catch {Write-Event 'HINWEIS' 'Client-Rollback unvollständig; Sicherungen und Protokoll prüfen.'}
            $message=Protect-Text $_.Exception.Message
            $code=if ($_.Exception.Data['BrainCode']) {[string]$_.Exception.Data['BrainCode']} else {'CLIENT_FAILED'}
            $script:clientResults+=@{name=$agent;status='failed';message=$message;recommendations=@(Get-Recommendations $code $message)}
            Write-Event 'FEHLER' "$agent : $message"
            foreach ($tip in @(Get-Recommendations $code $message)) {Write-Event 'HINWEIS' $tip}
        } finally {$script:transaction=$null;Write-RunResult -1}
    }
    if ($failed) {Stop-Brain 'CLIENT_FAILED' 'Mindestens eine Client-Anbindung fehlgeschlagen. Andere ausgewählte Clients wurden weiterbearbeitet.'}
}
