#requires -Version 5.1
[CmdletBinding()]
param([string]$PreviewPath,[switch]$SmokeTest,[switch]$WorkerCheck)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$composeFile=Join-Path $root 'compose.yaml'
$utf8=[Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding=$utf8
$OutputEncoding=$utf8
. (Join-Path $PSScriptRoot 'Core.ps1')
. (Join-Path $PSScriptRoot 'Clients.ps1')
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="agent-brain - Installation" Width="980" Height="850" MinWidth="740" MinHeight="700"
 WindowStartupLocation="CenterScreen" Background="#101815" Foreground="#DAE5DC" FontFamily="Segoe UI" FontSize="13">
 <Window.Resources>
  <Style TargetType="Button"><Setter Property="Padding" Value="18,11"/><Setter Property="Margin" Value="0,0,10,0"/><Setter Property="Background" Value="#26372B"/><Setter Property="Foreground" Value="#D4EACD"/><Setter Property="BorderBrush" Value="#44634A"/><Setter Property="Cursor" Value="Hand"/></Style>
  <Style TargetType="TextBox"><Setter Property="Background" Value="#132019"/><Setter Property="Foreground" Value="#D4EACD"/><Setter Property="BorderBrush" Value="#344A3B"/><Setter Property="Padding" Value="9,7"/><Setter Property="CaretBrush" Value="#B9ECA0"/></Style>
  <Style TargetType="CheckBox"><Setter Property="Foreground" Value="#D4EACD"/><Setter Property="Margin" Value="0,6,20,6"/><Setter Property="VerticalContentAlignment" Value="Center"/></Style>
 </Window.Resources>
 <Grid x:Name="RootGrid" Margin="30,24" Background="#101815">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <Grid Grid.Row="0" Margin="0,0,0,22">
   <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
   <StackPanel><TextBlock Text="agent-brain" FontSize="29" FontWeight="SemiBold" Foreground="#C5F7AC"/>
    <TextBlock Text="DEIN GEMEINSAMES KI-GEDÄCHTNIS" FontSize="10" Foreground="#83A28A" Margin="1,6,0,0"/></StackPanel>
   <Border Grid.Column="1" Background="#223B29" CornerRadius="16" Padding="16,8" VerticalAlignment="Center"><TextBlock Text="LOKAL AUF DEINEM PC" FontSize="10" Foreground="#B2DEA1"/></Border>
  </Grid>
  <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
   <StackPanel Margin="0,0,12,0">
    <TextBlock Text="Einrichten. Fortsetzen. Verwalten." FontSize="23" FontWeight="SemiBold"/>
    <TextBlock Text="Der Assistent prüft deinen PC und verwendet vorhandene Daten und Einstellungen weiter." Foreground="#93AA99" Margin="0,9,0,20" TextWrapping="Wrap"/>
    <Border Background="#1B2820" BorderBrush="#334939" BorderThickness="1" CornerRadius="9" Padding="18" Margin="0,0,0,14">
     <StackPanel>
      <TextBlock Text="01  DIENST &amp; VORAUSSETZUNGEN" Foreground="#B0D5A1" FontSize="11" FontWeight="SemiBold" Margin="0,0,0,12"/>
      <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="130"/><ColumnDefinition Width="150"/></Grid.ColumnDefinitions>
       <StackPanel Margin="0,0,15,0"><TextBlock Text="Was möchtest du tun?" Margin="0,0,0,7"/><ComboBox x:Name="ActionChoice" Height="32" SelectedIndex="0">
        <ComboBoxItem Tag="Install">Installieren / aktualisieren</ComboBoxItem><ComboBoxItem Tag="Start">Starten / fortsetzen</ComboBoxItem>
        <ComboBoxItem Tag="Configure">Nur Clients anbinden</ComboBoxItem><ComboBoxItem Tag="Diagnose">Diagnose</ComboBoxItem>
        <ComboBoxItem Tag="Test">Funktionstest</ComboBoxItem><ComboBoxItem Tag="Backup">Datenbank sichern</ComboBoxItem>
        <ComboBoxItem Tag="Status">Status</ComboBoxItem><ComboBoxItem Tag="Stop">Dienste stoppen</ComboBoxItem>
       </ComboBox></StackPanel>
       <StackPanel Grid.Column="1" Margin="0,0,15,0"><TextBlock Text="MCP-Port" Margin="0,0,0,7"/><TextBox x:Name="McpPort" Text="8765"/></StackPanel>
       <StackPanel Grid.Column="2"><TextBlock Text="Dashboard-Port" Margin="0,0,0,7"/><TextBox x:Name="WebPort" Text="8766"/></StackPanel>
      </Grid>
      <CheckBox x:Name="DockerInstall" Content="Docker Desktop installieren, falls es fehlt (über winget)" Margin="0,15,0,6"/>
      <TextBlock x:Name="ConfigHint" Text="Bei der ersten Installation werden lokale Einstellungen sicher angelegt." FontSize="11" Foreground="#83A28A" TextWrapping="Wrap"/>
     </StackPanel>
    </Border>
    <Border Background="#1B2820" BorderBrush="#334939" BorderThickness="1" CornerRadius="9" Padding="18" Margin="0,0,0,14">
     <StackPanel>
      <TextBlock Text="02  DEINE KI-CLIENTS" Foreground="#B0D5A1" FontSize="11" FontWeight="SemiBold"/>
      <TextBlock Text="Wähle die Clients, die agent-brain verwenden sollen. Keine Auswahl lässt die Anbindung aus." Foreground="#93AA99" FontSize="12" Margin="0,8,0,9" TextWrapping="Wrap"/>
      <WrapPanel x:Name="ClientChoices"/>
      <TextBlock Text="Cursor und Claude Desktop: Globale Instructions anschließend manuell einfügen. Alle Clients nach der Anbindung neu starten." Foreground="#809B86" FontSize="11" Margin="0,8,0,0" TextWrapping="Wrap"/>
     </StackPanel>
    </Border>
    <Border Background="#15211A" BorderBrush="#334939" BorderThickness="1" CornerRadius="9" Padding="18">
     <StackPanel><TextBlock Text="03  FORTSCHRITT &amp; EMPFEHLUNGEN" Foreground="#B0D5A1" FontSize="11" FontWeight="SemiBold"/>
      <TextBlock x:Name="StatusText" Text="Bereit. Du kannst den Assistenten jederzeit erneut ausführen." Margin="0,12,0,10" TextWrapping="Wrap"/>
      <ProgressBar x:Name="Progress" Minimum="0" Maximum="100" Height="6" Background="#29372D" Foreground="#B9ECA0" BorderThickness="0"/>
      <TextBox x:Name="LogBox" Height="145" IsReadOnly="True" FontFamily="Consolas" FontSize="11" Margin="0,14,0,0" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" BorderThickness="0"/>
      <TextBlock x:Name="ResultHint" Text="Das Fenster bleibt nach Erfolg und Fehler offen. Bestehende Daten werden nicht gelöscht." Foreground="#93AA99" FontSize="11" Margin="0,12,0,0" TextWrapping="Wrap"/>
     </StackPanel>
    </Border>
    <TextBlock x:Name="FolderLabel" Foreground="#6F8976" FontSize="10" TextWrapping="Wrap" Margin="2,14,0,16"/>
   </StackPanel>
  </ScrollViewer>
  <Grid Grid.Row="2" Margin="0,18,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
   <StackPanel Orientation="Horizontal"><Button x:Name="RunButton" Content="Jetzt ausführen" Background="#B9ECA0" Foreground="#162A18" FontWeight="SemiBold"/>
    <Button x:Name="DashboardButton" Content="Dashboard öffnen" IsEnabled="False"/><Button x:Name="LogButton" Content="Protokoll" IsEnabled="False"/></StackPanel>
   <Button Grid.Column="1" x:Name="CloseButton" Content="Schließen" Margin="0"/>
  </Grid>
 </Grid>
</Window>
'@
$reader=[Xml.XmlNodeReader]::new($xaml)
$window=[Windows.Markup.XamlReader]::Load($reader)
$controls=@{}
foreach ($name in @('RootGrid','ActionChoice','McpPort','WebPort','DockerInstall','ConfigHint','ClientChoices','StatusText','Progress','LogBox','ResultHint','FolderLabel','RunButton','DashboardButton','LogButton','CloseButton')) {$controls[$name]=$window.FindName($name)}
$controls.FolderLabel.Text='Arbeitsordner: '+$root
$detected=@(Get-DetectedAgents)
$clientBoxes=@{}
foreach ($name in @('Codex','ClaudeCode','GeminiCLI','Cursor','ClaudeDesktop')) {
    $box=[Windows.Controls.CheckBox]::new();$box.Content=$name;$box.Tag=$name;$box.IsEnabled=($name -in $detected)
    if (-not $box.IsEnabled) {$box.Opacity=0.45}
    $box.ToolTip=if ($box.IsEnabled) {'Erkannt über CLI, Installation oder Konfiguration.'} else {'Nicht erkannt. Client installieren und den Assistenten erneut öffnen.'}
    $null=$controls.ClientChoices.Children.Add($box);$clientBoxes[$name]=$box
}
if (-not $detected.Count) {$controls.ConfigHint.Text='Keine unterstützten Clients erkannt. Dienstinstallation ist trotzdem möglich.'}
$savedEnv=Join-Path $root '.env'
if (Test-Path -LiteralPath $savedEnv) {
    try {
        $saved=Read-Environment $savedEnv
        $controls.McpPort.Text=$saved.Values.BRAIN_PORT
        if ($saved.Values.DASHBOARD_PORT) {$controls.WebPort.Text=$saved.Values.DASHBOARD_PORT}
        $controls.McpPort.IsReadOnly=$true;$controls.WebPort.IsReadOnly=$true
        $controls.ConfigHint.Text='Vorhandene .env wird verwendet. Ports dort ändern; danach Clients erneut anbinden.'
        $controls.DashboardButton.IsEnabled=$true
    } catch {$controls.ConfigHint.Text='Lokale .env ist ungültig. Diagnose liefert Handlungsempfehlungen.'}
}
$script:worker=$null;$script:outputTask=$null;$script:errorTask=$null;$script:currentRun=$null;$script:currentLog=$null
$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(500)
function New-GuiArguments {
    $mcp=0;$web=0
    if (-not [int]::TryParse($controls.McpPort.Text,[ref]$mcp) -or -not [int]::TryParse($controls.WebPort.Text,[ref]$web)) {throw 'Bitte gültige Portnummern eingeben.'}
    Assert-PortNumbers $mcp $web
    $selected=@($clientBoxes.Keys | Where-Object {$clientBoxes[$_].IsEnabled -and $clientBoxes[$_].IsChecked})
    $action=[string]$controls.ActionChoice.SelectedItem.Tag
    $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'Install-AgentBrain.ps1'),'-Action',$action,'-NonInteractive','-NoPause','-RunId',$script:currentRun)
    # Existing ports are authoritative. No default parameter accidentally changes them.
    if (-not (Test-Path -LiteralPath $savedEnv)) {$arguments+=@('-Port',[string]$mcp,'-DashboardPort',[string]$web)}
    if ($controls.DockerInstall.IsChecked) {$arguments+='-InstallDocker'}
    # Windows PowerShell -File cannot bind string-array arguments reliably from native argv.
    # Use an encoded script with a data payload and splat a real string array instead.
    $parameters=@{Action=$action;NonInteractive=$true;NoPause=$true;RunId=$script:currentRun}
    if (-not (Test-Path -LiteralPath $savedEnv)) {$parameters.Port=$mcp;$parameters.DashboardPort=$web}
    if ($controls.DockerInstall.IsChecked) {$parameters.InstallDocker=$true}
    if ($selected.Count) {$parameters.Agents=$selected} else {$parameters.SkipAgentSetup=$true}
    $payload=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((@{script=(Join-Path $root 'Install-AgentBrain.ps1');parameters=$parameters} | ConvertTo-Json -Depth 5 -Compress)))
    $code='$d=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+$payload+''')) | ConvertFrom-Json;$p=@{};foreach($v in $d.parameters.PSObject.Properties){$p[$v.Name]=$v.Value}; & $d.script @p; exit $LASTEXITCODE'
    return @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code)))
}
$controls.RunButton.Add_Click({
    try {
        $script:currentRun=[guid]::NewGuid().ToString('N')
        $arguments=New-GuiArguments
        $script:currentLog=Join-Path $root ('logs/'+$script:currentRun+'.log')
        $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $info.Arguments=(@($arguments | ForEach-Object {Quote-Native $_})-join ' ');$info.WorkingDirectory=$root
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        $info.StandardOutputEncoding=[Text.Encoding]::UTF8;$info.StandardErrorEncoding=[Text.Encoding]::UTF8
        Set-ChildPowerShellEnvironment $info
        $script:worker=[Diagnostics.Process]::new();$script:worker.StartInfo=$info;$null=$script:worker.Start()
        $script:outputTask=$script:worker.StandardOutput.ReadToEndAsync();$script:errorTask=$script:worker.StandardError.ReadToEndAsync()
        $controls.RunButton.IsEnabled=$false;$controls.CloseButton.IsEnabled=$false;$controls.ActionChoice.IsEnabled=$false
        $controls.StatusText.Text='Vorbereitung ...';$controls.Progress.Value=0;$controls.Progress.IsIndeterminate=$true;$controls.LogBox.Text=''
        $controls.ResultHint.Text='Das Setup arbeitet. Downloads können einige Minuten dauern. Zeitlimits verhindern endloses Warten.'
        $timer.Start()
    } catch {$controls.StatusText.Text='Start fehlgeschlagen';$controls.ResultHint.Text=Protect-Text $_.Exception.Message;$controls.RunButton.IsEnabled=$true;$controls.CloseButton.IsEnabled=$true}
})
$timer.Add_Tick({
    try {
        if ($script:currentLog -and (Test-Path -LiteralPath $script:currentLog)) {
            $log=[IO.File]::ReadAllText($script:currentLog)
            if ($controls.LogBox.Text -ne $log) {$controls.LogBox.Text=$log;$controls.LogBox.ScrollToEnd()}
            $controls.LogButton.IsEnabled=$true
        }
        $reportPath=Join-Path $root ('logs/'+$script:currentRun+'.json')
        $report=$null
        if (Test-Path -LiteralPath $reportPath) {
            $report=Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $controls.Progress.IsIndeterminate=$false;$controls.Progress.Value=$report.progress;$controls.StatusText.Text=$report.step
        }
        if ($script:worker.HasExited) {
            $timer.Stop();$controls.Progress.IsIndeterminate=$false
            $controls.RunButton.IsEnabled=$true;$controls.CloseButton.IsEnabled=$true;$controls.ActionChoice.IsEnabled=$true
            if ($script:worker.ExitCode -eq 0) {
                $controls.StatusText.Text='Abgeschlossen';$controls.StatusText.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#B9ECA0')
                $controls.Progress.Value=100;$controls.ResultHint.Text='Fertig. Ausgewählte KI-Clients neu starten. Das Fenster bleibt offen.'
                if ($report.dashboard_port) {$controls.WebPort.Text=[string]$report.dashboard_port;$controls.DashboardButton.IsEnabled=$true}
            } else {
                $controls.StatusText.Text='Nicht vollständig abgeschlossen';$controls.StatusText.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#EFBA89')
                $controls.ResultHint.Text=if ($report.failure) {$report.failure.message+"`n"+(@($report.failure.recommendations)-join "`n")} else {'Aufruf fehlgeschlagen. Protokoll prüfen und erneut versuchen.'}
                if (-not $controls.LogBox.Text) {$controls.LogBox.Text=Protect-Text ($script:outputTask.GetAwaiter().GetResult()+$script:errorTask.GetAwaiter().GetResult())}
            }
            $script:worker.Dispose();$script:worker=$null
        }
    } catch {$controls.ResultHint.Text='Fortschrittsbericht kurzzeitig nicht lesbar; das Setup arbeitet weiter.'}
})
$controls.DashboardButton.Add_Click({try {Start-Process ("http://127.0.0.1:"+$controls.WebPort.Text+'/')} catch {$controls.ResultHint.Text='Dashboard im Browser unter http://127.0.0.1:'+ $controls.WebPort.Text+' öffnen.'}})
$controls.LogButton.Add_Click({if ($script:currentLog -and (Test-Path -LiteralPath $script:currentLog)) {Start-Process notepad.exe -ArgumentList ('"'+$script:currentLog+'"')}})
$controls.CloseButton.Add_Click({$window.Close()})
$window.Add_Closing({param($sender,$event) if ($script:worker -and -not $script:worker.HasExited) {$event.Cancel=$true;$controls.ResultHint.Text='Bitte den laufenden Schritt abwarten. Das Setup hat begrenzte Zeitlimits.'}})
if ($SmokeTest) {
    $script:currentRun=[guid]::NewGuid().ToString('N');$arguments=New-GuiArguments
    if (-not $arguments.Count -or $clientBoxes.Count -ne 5 -or $controls.RunButton.IsEnabled -ne $true) {throw 'GUI smoke check failed.'}
    Write-Host ('PASS: WPF window, five client choices, existing settings and safe worker argument construction. Detected: '+($detected -join ', '))
    if ($WorkerCheck) {
        # Exercise the same hidden worker used by the window, using read-only Diagnose.
        $controls.ActionChoice.SelectedIndex=3
        $arguments=New-GuiArguments
        $result=Invoke-Process powershell.exe $arguments -Quiet -AllowFailure -Timeout 45
        if ($result.ExitCode -ne 0) {throw ('GUI worker failed: '+(Protect-Text ($result.Output+$result.Error)))}
        $report=Get-Content (Join-Path $root ('logs/'+$script:currentRun+'.json')) -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($report.action -ne 'Diagnose' -or $report.exit_code -ne 0 -or $report.progress -ne 100) {throw 'GUI worker result mismatch.'}
        Write-Host 'PASS: actual GUI worker, argument transport, progress and completion report.'
        $controls.ActionChoice.SelectedIndex=0
    }
}
if ($PreviewPath) {
    # Preview uses a neutral display path; worker actions still use the real root.
    $controls.FolderLabel.Text='Arbeitsordner: <dein Ordner>\agent-brain'
    $content=$window.Content;$content.Measure([Windows.Size]::new(920,900));$content.Arrange([Windows.Rect]::new(0,0,920,900));$content.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(920,900,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $background=[Windows.Media.DrawingVisual]::new();$drawing=$background.RenderOpen()
    try {$drawing.DrawRectangle($window.Background,$null,[Windows.Rect]::new(0,0,920,900))} finally {$drawing.Close()}
    $bitmap.Render($background);$bitmap.Render($content)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=[IO.File]::Create($PreviewPath);try {$encoder.Save($stream)} finally {$stream.Dispose()}
    Write-Host "GUI preview saved: $PreviewPath"
    return
}
if ($SmokeTest) {return}
$null=$window.ShowDialog()
