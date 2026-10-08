#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Install','Start','Stop','Status','Configure','Backup','Test','Diagnose')][string]$Action='Install',
    [ValidateSet('Codex','ClaudeCode','GeminiCLI','Cursor','ClaudeDesktop')][string[]]$Agents,
    [switch]$SkipAgentSetup,[switch]$InstallDocker,[switch]$DetectionOnly,
    [switch]$NonInteractive,[switch]$NoPause,[switch]$Gui,
    [int]$Port=8765,[int]$DashboardPort=8766,
    [ValidateRange(30,7200)][int]$TimeoutSeconds=900,
    [ValidateRange(5,1800)][int]$DockerWaitSeconds=180,
    [ValidateRange(1,5)][int]$Retries=3,
    [ValidatePattern('^[a-f0-9]{32}$')][string]$RunId
)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$composeFile=Join-Path $root 'compose.yaml'
$utf8=[Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding=$utf8
$OutputEncoding=$utf8
$script:PSBoundParametersSnapshot=@{}+$PSBoundParameters
$completionCode=0;$lock=$null;$lockHeld=$false
try {
    foreach ($file in @('installer/Core.ps1','installer/Clients.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $file))) { throw "Paket unvollständig: $file fehlt. Den gesamten Ordner entpacken." }
        . (Join-Path $root $file)
    }
    if ($Gui) {
        $guiScript=Join-Path $root 'installer/Gui.ps1'
        $shell=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$shell;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
        $info.Arguments=(@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',$guiScript) | ForEach-Object {Quote-Native $_}) -join ' '
        Set-ChildPowerShellEnvironment $info
        $process=[Diagnostics.Process]::Start($info);$process.Dispose()
        return
    }
    if ($DetectionOnly) { Get-DetectedAgents;return }
    Assert-Windows
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $lock=[Threading.Mutex]::new($false,('Local\agent-brain-installer-'+$sid))
    try { $lockHeld=$lock.WaitOne(0) } catch [Threading.AbandonedMutexException] { $lockHeld=$true }
    if (-not $lockHeld) { Stop-Brain 'INSTALL_BUSY' 'Eine weitere agent-brain-Installation arbeitet bereits.' }
    Initialize-Run
    Show-Header
    Invoke-AgentBrainAction
    Set-Step 'Fertig' 100
    Write-Event 'OK' "Aktion '$Action' abgeschlossen."
} catch {
    $completionCode=1
    if (Get-Command Protect-Text -ErrorAction SilentlyContinue) {
        $errorId=if ($_.Exception.Data['BrainCode']) { [string]$_.Exception.Data['BrainCode'] } else { 'UNEXPECTED' }
        $errorMessage=Protect-Text $_.Exception.Message
        Write-Event 'FEHLER' $errorMessage
        $help=@(Get-Recommendations $errorId $errorMessage)
        Write-Host "`n  Nächste Schritte [$errorId]" -ForegroundColor Yellow
        foreach ($item in $help) { Write-Event 'HINWEIS' $item }
        $script:failure=@{code=$errorId;message=$errorMessage;recommendations=$help}
    } else { Write-Host $_.Exception.Message -ForegroundColor Red }
} finally {
    if ($script:runPath) {
        try { Write-RunResult $completionCode;Write-Host "`n  Protokoll: $script:runPath" -ForegroundColor DarkGray }
        catch { Write-Host '  Abschlussbericht konnte nicht gespeichert werden.' -ForegroundColor Yellow }
    }
    if ($lockHeld) { $lock.ReleaseMutex() }
    if ($lock) { $lock.Dispose() }
    if (-not $NoPause -and -not $NonInteractive -and -not $DetectionOnly -and -not $Gui) {
        Write-Host "`n  Zum Beenden eine beliebige Taste drücken ..."
        try { $null=$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') }
        catch { $null=Read-Host '  Zum Beenden Enter drücken' }
    }
}
if ($completionCode -ne 0) { exit $completionCode }
