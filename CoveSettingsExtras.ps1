# Loaded in Show-Settings so event handlers share the dialog's live scope.
$accentPresets=@(
 [pscustomobject]@{Name='Menta';Hex='#67D9BE'},[pscustomobject]@{Name='Oceano';Hex='#5AA9EA'},
 [pscustomobject]@{Name='Violeta';Hex='#A78BFA'},[pscustomobject]@{Name='Rosa';Hex='#F08DB7'},
 [pscustomobject]@{Name='Dourado';Hex='#E9BD6A'},[pscustomobject]@{Name='Coral';Hex='#F58C7A'}
)
$accentList=$dialog.FindName('AccentList');$accentHex=$dialog.FindName('AccentHex');$accentPreview=$dialog.FindName('AccentPreview');$accentStatus=$dialog.FindName('AccentStatus')
$accentHex.Text=$script:appearance.Hex;$accentList.ItemsSource=@($accentPresets|ForEach-Object{$_.Name})
$accentList.SelectedItem=($accentPresets|Where-Object{$_.Hex -eq $script:appearance.Hex}|Select-Object -First 1).Name
$accentPreview.Background=$script:appearance.Hex
$accentList.Add_SelectionChanged({$preset=$accentPresets|Where-Object{$_.Name -eq $accentList.SelectedItem}|Select-Object -First 1;if($preset){$accentHex.Text=$preset.Hex}})
$accentHex.Add_TextChanged({if($accentHex.Text -match '^#[0-9a-fA-F]{6}$'){$accentPreview.Background=$accentHex.Text;$accentStatus.Text=''}else{$accentStatus.Text='Use #RRGGBB ou escolha uma cor.'}})
$dialog.FindName('ChooseAccent').Add_Click({
 Add-Type -AssemblyName System.Windows.Forms,System.Drawing
 $picker=New-Object Windows.Forms.ColorDialog
 try{
  $picker.FullOpen=$true
  if($accentHex.Text -match '^#[0-9a-fA-F]{6}$'){$picker.Color=[Drawing.ColorTranslator]::FromHtml($accentHex.Text)}
  if($picker.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){$accentHex.Text='#{0:X2}{1:X2}{2:X2}' -f $picker.Color.R,$picker.Color.G,$picker.Color.B}
 }finally{$picker.Dispose()}
})
$dialog.FindName('ApplyAccent').Add_Click({
 try{
  $hex=$accentHex.Text.Trim().ToUpperInvariant()
  $palette=Set-CoveAccent $window $hex
  [IO.File]::WriteAllText($script:appearance.File,(@{Accent=$hex}|ConvertTo-Json -Compress),[Text.Encoding]::UTF8)
  $script:appearance.Hex=$hex;$script:appearance.Palette=$palette;$orb.Background=$palette.Idle;$glow.Color=$palette.Light
  $accentStatus.Text='Cor aplicada e salva.'
 }catch{$accentStatus.Text=$_.Exception.GetBaseException().Message}
})
$callList=$dialog.FindName('SavedCalls');$callServer=$dialog.FindName('CallServer');$callChannel=$dialog.FindName('CallChannel');$callLink=$dialog.FindName('CallLink');$callStatus=$dialog.FindName('CallStatus');$discordMethod=$dialog.FindName('DiscordMethod')
$discordMethod.ItemsSource=@('Mouse (dois monitores)','Links salvos','Controles do Discord')
try{$callData=Get-CoveDiscordLinks;$callList.ItemsSource=@($callData.Channels);$discordMethod.SelectedIndex=@{mouse=0;links=1;interface=2}[$callData.Method]}catch{$callStatus.Text=$_.Exception.Message}
if($script:pendingLinkTarget){$dialog.FindName('CallsExpander').IsExpanded=$true;$callServer.Text=$script:pendingLinkTarget.Server;$callChannel.Text=$script:pendingLinkTarget.Channel}
$discordMethod.Add_SelectionChanged({try{$data=Get-CoveDiscordLinks;$data.Method=@('mouse','links','interface')[$discordMethod.SelectedIndex];Save-CoveDiscordLinks $data;$callStatus.Text='Metodo salvo. No modo mouse, Esc ou mover o ponteiro interrompe a acao.'}catch{$callStatus.Text=$_.Exception.Message}})
$callList.Add_SelectionChanged({if($callList.SelectedItem){$callServer.Text=$callList.SelectedItem.Server;$callChannel.Text=$callList.SelectedItem.Channel;$callLink.Text=$callList.SelectedItem.Link}})
$dialog.FindName('SaveCallLink').Add_Click({
 try{Add-CoveDiscordLink $callServer.Text $callChannel.Text $callLink.Text;$callList.ItemsSource=@((Get-CoveDiscordLinks).Channels);$discordMethod.SelectedIndex=1;$script:pendingLinkTarget=$null;$callStatus.Text='Canal salvo. Pode pedir pelo nome do servidor e da call.'}catch{$callStatus.Text=$_.Exception.GetBaseException().Message}
})
$dialog.FindName('RemoveCallLink').Add_Click({
 if(-not $callList.SelectedItem){$callStatus.Text='Selecione uma call salva.';return}
 try{$selected=$callList.SelectedItem;$data=Get-CoveDiscordLinks;$data.Channels=@($data.Channels|Where-Object{$_.Server -ne $selected.Server -or $_.Channel -ne $selected.Channel});Save-CoveDiscordLinks $data;$callList.ItemsSource=@($data.Channels);$callStatus.Text='Canal removido da lista.'}catch{$callStatus.Text=$_.Exception.Message}
})
$dialog.FindName('TestCallLink').Add_Click({
 if(-not $callList.SelectedItem){$callStatus.Text='Selecione uma call salva.';return}
 if($script:task -or $script:discordTask -or $script:loginTask -or $script:transcribeTask){$callStatus.Text='Espere o pedido atual terminar.';return}
 $selected=$callList.SelectedItem
 Ask-Cove ('entre na call '+$selected.Channel+' no servidor '+$selected.Server)
 $dialog.Close()
})

$monitorInfo=$dialog.FindName('MouseMonitorInfo')
try{$areas=@([CoveApp.Computer]::Displays());$monitorInfo.Text=$areas.Count.ToString()+' monitor(es): '+(($areas|ForEach-Object{($_.Right-$_.Left).ToString()+' x '+($_.Bottom-$_.Top)+' em ('+$_.Left+','+$_.Top+')'}) -join '; ')}catch{$monitorInfo.Text='Os monitores serao identificados no teste.'}
$script:mouseTestStatus=$dialog.FindName('MouseTestStatus');$script:mouseTestButton=$dialog.FindName('TestMouseMonitors')
if($script:mouseTestProcess -and -not $script:mouseTestProcess.HasExited){$script:mouseTestButton.IsEnabled=$false;$script:mouseTestStatus.Text='Teste em andamento. Esc interrompe.'}
$dialog.FindName('TestMouseMonitors').Add_Click({
 if($script:discordTask -or $script:task -or $script:transcribeTask){$script:mouseTestStatus.Text='Espere o pedido atual terminar.';return}
 if($script:mouseTestProcess -and -not $script:mouseTestProcess.HasExited){return}
 $start=New-Object Diagnostics.ProcessStartInfo
 $start.FileName=Join-Path $PSHOME 'powershell.exe'
 $start.Arguments='-NoProfile -STA -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'Verificar-Mouse.ps1')+'" -Physical'
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 try{
  $script:mouseTestProcess=[Diagnostics.Process]::Start($start)
  $script:mouseTestOut=$script:mouseTestProcess.StandardOutput.ReadToEndAsync();$script:mouseTestErr=$script:mouseTestProcess.StandardError.ReadToEndAsync()
  $script:mouseTestButton.IsEnabled=$false;$script:mouseTestStatus.Text='Testando movimentos e cliques nas janelas de teste. Esc interrompe.'
  $script:mouseTestTimer=New-Object Windows.Threading.DispatcherTimer;$script:mouseTestTimer.Interval=[TimeSpan]::FromMilliseconds(250)
  $script:mouseTestTimer.Add_Tick({
   if($script:mouseTestProcess -and $script:mouseTestProcess.HasExited -and $script:mouseTestOut.IsCompleted -and $script:mouseTestErr.IsCompleted){
    $script:mouseTestTimer.Stop()
    $output=$script:mouseTestOut.GetAwaiter().GetResult();$errorOutput=$script:mouseTestErr.GetAwaiter().GetResult()
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'cove-mouse-test.log'),$output+"`r`n"+$errorOutput,[Text.Encoding]::UTF8)
    $script:mouseTestStatus.Text=if($script:mouseTestProcess.ExitCode -eq 0){'Teste concluido: movimento e cliques conferidos nos monitores detectados.'}else{'O teste nao terminou. Confira se o mouse esta acessivel nesta sessao e tente novamente. O diagnostico ficou salvo.'}
    $script:mouseTestButton.IsEnabled=$true;$script:mouseTestProcess.Dispose();$script:mouseTestProcess=$null
   }
  });$script:mouseTestTimer.Start()
 }catch{$script:mouseTestStatus.Text='Nao consegui iniciar o teste de mouse. '+$_.Exception.Message;$script:mouseTestButton.IsEnabled=$true}
})
