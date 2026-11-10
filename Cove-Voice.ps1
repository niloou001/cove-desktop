param([switch]$SmokeTest)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'CoveApps.ps1')
. (Join-Path $PSScriptRoot 'CoveAppPanel.ps1')
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Speech,System.Security,System.Net.Http,System.Web.Extensions
trap { if($SmokeTest){Write-Output $_.Exception.Message;exit 1};try { [Windows.MessageBox]::Show($_.Exception.Message,'Cove: erro') | Out-Null } catch {}; exit 1 }
Add-Type -Path @((Join-Path $PSScriptRoot 'CoveCore.cs'),(Join-Path $PSScriptRoot 'CoveASR.cs')) -ReferencedAssemblies System.Net.Http,System.Web.Extensions
$transcriber=New-Object CoveApp.CoveTranscription($PSScriptRoot)
$script:transcribeTask=$null;$script:asrSetup=$null;$script:asrStatus=$null
Add-Type -Path (Join-Path $PSScriptRoot 'CoveChatGPT.cs') -ReferencedAssemblies System.Net.Http,System.Web.Extensions,System.Security
Add-Type -Path @((Join-Path $PSScriptRoot 'CoveVoice.cs'),(Join-Path $PSScriptRoot 'CoveNeural.cs')) -ReferencedAssemblies System.Web.Extensions
$audioFile=Join-Path $PSScriptRoot 'cove-audio.json'
$script:micId=-1;$script:voiceId='';$script:speechTask=$null
$script:micMeter=$null;$script:micHint=$null;$script:lastHeard='';$script:voiceSetup=$null;$script:voiceHint=$null
if(Test-Path -LiteralPath $audioFile){try{$audioSettings=Get-Content -LiteralPath $audioFile -Raw|ConvertFrom-Json;$script:micId=[int]$audioSettings.Microphone;$script:voiceId=[string]$audioSettings.Voice}catch{}}
$script:voices=@([CoveApp.CoveSpeech]::Voices())
if(-not $audioSettings -or -not $audioSettings.PresetVersion){$script:voiceId='kokoro:serena'}
if(-not ($script:voices|Where-Object{$_.Id -eq $script:voiceId})){
 $preferred=$script:voices|Where-Object{$_.Id -eq 'kokoro:serena'}|Select-Object -First 1
 if(-not $preferred){$preferred=$script:voices|Select-Object -First 1}
 if($preferred){$script:voiceId=$preferred.Id}
}
$voiceEngine=New-Object CoveApp.CoveSpeech($PSScriptRoot)
$script:voiceAvailable=$script:voices.Count -gt 0
$script:account=$null;$script:loginTask=$null;$script:loginCancel=$null;$script:loginKind='login'
$modeFile=Join-Path $PSScriptRoot '.cove-mode.txt'
$script:mode='chatgpt'
if(-not $SmokeTest -and (Test-Path -LiteralPath $modeFile)){$savedMode=[IO.File]::ReadAllText($modeFile).Trim();if($savedMode -eq 'api'){$script:mode='api'}}
if(-not $SmokeTest){
 try{$script:account=New-Object CoveApp.ChatGPTAccount((Join-Path $PSScriptRoot '.cove-account'))}
 catch{[Windows.MessageBox]::Show('Nao foi possivel abrir a conexao ChatGPT protegida. Confira as permissoes da pasta Cove.','Cove')|Out-Null}
}
$script:listener=$null; $script:task=$null; $script:cancel=$null
$script:history=@(); $script:state='Idle'; $script:muted=$false
$script:listenUntil=[datetime]::MinValue; $script:cooldown=[datetime]::MinValue
$script:pendingQuestion=''; $script:lastError=''; $script:quitting=$false
$script:pendingAppName='';$script:pendingAppUntil=[datetime]::MinValue;$script:resumeListeningAt=[datetime]::MinValue;$script:listenAfterSpeech=$false
$script:key=$env:OPENAI_API_KEY
$keyFile=Join-Path $PSScriptRoot 'cove-key.dat'
if (-not $script:key -and (Test-Path -LiteralPath $keyFile)) {
 try { $raw=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($keyFile),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser); $script:key=[Text.Encoding]::UTF8.GetString($raw); [Array]::Clear($raw,0,$raw.Length) } catch {}
}
$window=New-Object Windows.Window
$window.Title='Cove';$window.Width=164;$window.Height=172
$window.WindowStyle='None';$window.ResizeMode='NoResize';$window.AllowsTransparency=$true
$window.Background='Transparent';$window.Topmost=$false;$window.ShowActivated=$false
$window.FontFamily='Segoe UI'
$window.Left=[Windows.SystemParameters]::WorkArea.Right-$window.Width-26
$window.Top=[Windows.SystemParameters]::WorkArea.Bottom-$window.Height-26
$theme=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Cove-Theme.xaml')))
$window.Resources.MergedDictionaries.Add($theme)
$panel=New-Object Windows.Controls.StackPanel
$orb=New-Object Windows.Controls.Button
$orb.Width=68;$orb.Height=68;$orb.Margin='12,12,12,8';$orb.Content='cove';$orb.Foreground='#EBF8FF';$orb.FontSize=14
$orb.Template=[Windows.Markup.XamlReader]::Parse(@'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button"><Grid><Ellipse Fill="{TemplateBinding Background}" Stroke="#80C7E3" StrokeThickness="1.3"/><Ellipse Margin="6" Stroke="#305C79" StrokeThickness="0.8"/><Ellipse Margin="9" IsHitTestVisible="False"><Ellipse.Fill><RadialGradientBrush Center="0.3,0.15" GradientOrigin="0.25,0.1" RadiusX="0.8" RadiusY="0.8"><GradientStop Color="#3868BBE8" Offset="0"/><GradientStop Color="#00172940" Offset="1"/></RadialGradientBrush></Ellipse.Fill></Ellipse><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Grid></ControlTemplate>
'@)
$glow=New-Object Windows.Media.Effects.DropShadowEffect
$glow.Color=[Windows.Media.ColorConverter]::ConvertFromString('#64B6DA');$glow.ShadowDepth=0;$glow.BlurRadius=16;$glow.Opacity=0.45;$orb.Effect=$glow
$status=New-Object Windows.Controls.TextBlock
$status.Foreground='#CBDCEB';$status.TextAlignment='Center';$status.TextWrapping='Wrap';$status.Padding='8,5';$status.FontSize=10
$statusPill=New-Object Windows.Controls.Border
$statusPill.Background='#EA142131';$statusPill.CornerRadius='12';$statusPill.Margin='5,0,5,0';$statusPill.Child=$status
$openChat=New-Object Windows.Controls.Button
$openChat.Content='Conversar';$openChat.Margin='26,6,26,0';$openChat.Padding='10,5';$openChat.FontSize=11
$panel.Children.Add($orb)|Out-Null;$panel.Children.Add($statusPill)|Out-Null;$panel.Children.Add($openChat)|Out-Null;$window.Content=$panel
$status.Add_MouseLeftButtonDown({$window.DragMove()})
$orb.ToolTip='Clique para falar. Arraste pelo texto. Botao direito: pausar ou sair.'
$chat=[Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Conversa com Cove" Width="480" Height="580" WindowStartupLocation="CenterScreen" WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True" Background="Transparent" Foreground="#E6EEF8" FontFamily="Segoe UI">
<Border CornerRadius="24" Background="#0E1927" BorderBrush="#2A3B50" BorderThickness="1" Padding="22"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<Grid x:Name="DragHeader" Background="Transparent" Margin="0,0,0,20"><StackPanel><TextBlock Text="cove" FontSize="25" FontWeight="SemiBold"/><TextBlock Text="Conversa e apps por voz - v2" FontSize="12" Foreground="#91A6BE" Margin="0,4,0,0"/></StackPanel><StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top"><Button x:Name="Minimize" Content="&#x2212;" Width="32" Height="32" Padding="0" Background="Transparent" BorderThickness="0" ToolTip="Minimizar"/><Button x:Name="CloseChat" Content="&#x00D7;" Width="32" Height="32" Padding="0" Background="Transparent" BorderThickness="0" ToolTip="Fechar conversa"/></StackPanel></Grid>
<TextBox x:Name="Transcript" Grid.Row="1" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" BorderThickness="0" FontSize="14"/>
<DockPanel Grid.Row="2" Margin="0,16,0,0"><Button x:Name="Send" Content="Enviar" DockPanel.Dock="Right" Background="#235D74" BorderBrush="#397D91" Padding="16,10"/><TextBox x:Name="Prompt" Margin="0,0,8,0" ToolTip="Escreva uma mensagem" VerticalContentAlignment="Center"/></DockPanel>
<StackPanel Grid.Row="3" Margin="0,14,0,0"><WrapPanel><Button x:Name="Configure" Content="Ajustes" Padding="11,7" Background="Transparent"/><Button x:Name="Mute" Content="Pausar microfone" Margin="8,0,0,0" Padding="11,7" Background="Transparent"/><Button x:Name="Clear" Content="Limpar" Margin="8,0,0,0" Padding="11,7" Background="Transparent"/><Button x:Name="Apps" Content="Apps" Margin="8,0,0,0" Padding="11,7" Background="Transparent"/></WrapPanel><TextBlock x:Name="Heard" Text="Diga Cove e espere ficar verde, ou clique na bolinha." TextWrapping="Wrap" Foreground="#91A6BE" FontSize="11" Margin="1,13,0,0"/></StackPanel>
</Grid></Border></Window>
'@)
$chat.Resources.MergedDictionaries.Add($theme)
$chat.Topmost=$false
$chat.FindName('DragHeader').Add_MouseLeftButtonDown({param($sender,$eventArgs) if($eventArgs.OriginalSource -is [Windows.Controls.TextBlock] -or $eventArgs.OriginalSource -eq $sender){$chat.DragMove()}})
$chat.FindName('CloseChat').Add_Click({$chat.Hide()})
$chat.FindName('Minimize').Add_Click({$chat.WindowState='Minimized'})
$transcript=$chat.FindName('Transcript');$promptBox=$chat.FindName('Prompt')
$sendButton=$chat.FindName('Send');$muteButton=$chat.FindName('Mute')
$heardLabel=$chat.FindName('Heard')
$chat.Add_Closing({param($sender,$eventArgs) if(-not $script:quitting){$eventArgs.Cancel=$true;$chat.Hide()}})
function Add-Message([string]$who,[string]$text){$transcript.AppendText($who+': '+$text+"`r`n`r`n");$transcript.ScrollToEnd()}
function Update-Capture {if($script:listener){$script:listener.Paused=$script:muted -or $null -ne $script:loginTask -or $script:state -in @('Thinking','Speaking','Transcribing') -or [datetime]::Now -lt $script:cooldown;$script:listener.ListeningMode=$script:state -eq 'Listening'}}
function Restart-Listener {
 $transcriber.Stop();$script:transcribeTask=$null
 if($script:listener){$script:listener.Dispose();$script:listener=$null}
 $script:lastError='';$script:lastHeard='';$script:state='Idle'
 if(-not $SmokeTest -and $modelReady -and (Test-Path -LiteralPath (Join-Path $assets 'native\libvosk.dll'))){$script:listener=New-Object CoveApp.Listener((Join-Path $assets 'native'),(Join-Path $assets 'vosk-model-small-pt-0.3'),$script:micId);$script:listener.UseNeural=$transcriber.Installed;Update-Capture}
}
function Set-ConnectionMode([string]$value){[IO.File]::WriteAllText($modeFile,$value);$script:mode=$value;$script:history=@()}
function Start-ChatGPTConnection([string]$action){
 if($script:task -or $script:loginTask){Add-Message 'Cove' 'Espere a operacao atual terminar.';return}
 if(-not $script:account){Add-Message 'Cove' 'A conexao protegida nao esta disponivel. Reinicie o Cove.';return}
 $script:loginCancel=New-Object Threading.CancellationTokenSource
 $script:loginKind=$action
 if($action -eq 'disconnect'){$script:loginTask=$script:account.Disconnect($script:loginCancel.Token)}
 else{$script:loginTask=$script:account.SignIn($script:loginCancel.Token);Add-Message 'Cove' 'Continue no navegador para entrar e autorizar seu plano ChatGPT. Nenhuma senha e digitada no Cove.'}
 $sendButton.IsEnabled=$false;Update-Capture
}
function Say([string]$text){
 if($script:voiceAvailable){try{$script:state='Speaking';Update-Capture;$script:speechTask=$voiceEngine.Speak($text,$script:voiceId);return}catch{Add-Message 'Cove' 'A voz selecionada nao esta disponivel. Escolha outra em Ajustes.'}}
 $script:state='Idle'
}
function Start-CoveTranscription([byte[]]$pcm){
 if($script:transcribeTask -or $script:task -or $script:loginTask){return}
 $script:state='Transcribing';$script:listenUntil=[datetime]::MinValue;Update-Capture
 $heardLabel.Text='Estou entendendo sua frase...';$sendButton.IsEnabled=$false
 $names=(@(Get-CoveApplications|ForEach-Object{$_.Name})+@('Cove')) -join ', '
 if($script:pendingAppName){$names='Sim, nao, pode abrir, cancelar'}
 $script:transcribeTask=$transcriber.Transcribe($pcm,$names)
}
function Show-Settings {
 $dialog=[Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Ajustes do Cove" Width="460" SizeToContent="Height" MaxHeight="760" WindowStartupLocation="CenterOwner" WindowStyle="None" AllowsTransparency="True" Background="Transparent" Foreground="#E6EEF8" FontFamily="Segoe UI" ResizeMode="NoResize"><Border CornerRadius="24" Background="#0E1927" BorderBrush="#2A3B50" BorderThickness="1" Padding="24"><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel><DockPanel x:Name="SettingsHeader" Background="Transparent" Margin="0,0,0,20"><Button x:Name="CloseSettings" Content="&#x00D7;" DockPanel.Dock="Right" Width="30" Height="30" Padding="0" Background="Transparent" BorderThickness="0" HorizontalAlignment="Right"/><TextBlock Text="Ajustes" FontSize="22" FontWeight="SemiBold"/></DockPanel>
<TextBlock Text="Sua conta ChatGPT" FontSize="17"/>
<TextBlock x:Name="AccountStatus" Foreground="#91A6BE" Margin="0,8,0,12" TextWrapping="Wrap"/>
<Button x:Name="ConnectChatGPT" Content="Continuar com ChatGPT" Background="#F2F5F8" Foreground="#15202B" BorderBrush="#F2F5F8"/>
<TextBlock Text="Entre e autorize no navegador. A disponibilidade depende do seu plano e das permissoes da conta. Suas conversas do ChatGPT nao sao importadas." Foreground="#91A6BE" FontSize="12" TextWrapping="Wrap" Margin="0,12,0,0"/>
<WrapPanel Margin="0,10,0,0"><Button x:Name="DisconnectChatGPT" Content="Desconectar" Background="Transparent" Padding="10,7"/><Button x:Name="ManageUsage" Content="Gerenciar uso" Background="Transparent" Padding="10,7" Margin="8,0,0,0"/><Button x:Name="CancelLogin" Content="Cancelar login" Background="Transparent" Padding="10,7" Margin="8,0,0,0"/></WrapPanel>
<TextBlock Text="Voz" FontSize="17" Margin="0,24,0,10"/>
<ComboBox x:Name="VoiceList" DisplayMemberPath="Name"/>
<TextBlock x:Name="VoiceHint" TextWrapping="Wrap" Foreground="#91A6BE" FontSize="11" Margin="0,8,0,0"/>
<Button x:Name="TestVoice" Content="Ouvir esta voz" Margin="0,8,0,0" Background="Transparent"/>
<Button x:Name="PrepareVoices" Content="Preparar Serena e Atlas" Margin="0,8,0,0" Background="Transparent"/>
<TextBlock Text="Microfone" FontSize="17" Margin="0,22,0,10"/>
<TextBlock x:Name="RecognitionStatus" Foreground="#91A6BE" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,8"/>
<Button x:Name="ImproveListening" Content="Preparar escuta aprimorada" Background="Transparent" Margin="0,0,0,10"/>
<ComboBox x:Name="MicList" DisplayMemberPath="Name"/>
<ProgressBar x:Name="MicMeter" Minimum="0" Maximum="100" Height="6" Margin="0,12,0,6" Foreground="#67D9BE" Background="#203247" BorderThickness="0"/>
<TextBlock x:Name="MicHint" Text="Fale e observe o nivel do microfone." Foreground="#91A6BE" FontSize="11" TextWrapping="Wrap"/>
<Button x:Name="ApplyAudio" Content="Aplicar voz e microfone" Background="#235D74" BorderBrush="#397D91" Margin="0,12,0,0"/>
<TextBlock Text="Se o nivel nao mexer, escolha outro microfone e aplique. Depois diga Cove, espere ficar verde e fale." Foreground="#91A6BE" FontSize="11" TextWrapping="Wrap" Margin="0,8,0,0"/>
<Expander Header="Usar chave da API (alternativa)" Margin="0,24,0,0" Foreground="#91A6BE"><StackPanel Margin="0,14,0,0"><TextBlock Text="A API tem faturamento separado. So sera usada se voce escolher Salvar e usar API." TextWrapping="Wrap" FontSize="12"/><PasswordBox x:Name="Key" Margin="0,14,0,12"/><Button x:Name="Save" Content="Salvar e usar API" Background="#235D74" BorderBrush="#397D91"/><Button x:Name="Forget" Content="Remover chave salva" Background="Transparent" BorderThickness="0" Margin="0,6,0,0"/></StackPanel></Expander>
</StackPanel></ScrollViewer></Border></Window>
'@)
 $dialog.Resources.MergedDictionaries.Add($theme)
 $dialog.Owner=$chat
 $voiceList=$dialog.FindName('VoiceList');$micList=$dialog.FindName('MicList')
 $script:asrStatus=$dialog.FindName('RecognitionStatus')
 if($transcriber.Installed){$script:asrStatus.Text='Escuta aprimorada ativada. Fale no seu ritmo.';$dialog.FindName('ImproveListening').Visibility='Collapsed'}else{$script:asrStatus.Text='Escuta leve em uso. Prepare a escuta aprimorada para entender melhor frases naturais.'}
 $dialog.FindName('ImproveListening').Add_Click({
  try{
   if($script:asrSetup -and -not $script:asrSetup.HasExited){return}
   $setup=New-Object Diagnostics.ProcessStartInfo
   $setup.FileName=Join-Path $PSHOME 'powershell.exe';$setup.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'Preparar-Escuta.ps1')+'"'
   $setup.UseShellExecute=$false;$setup.CreateNoWindow=$true;$setup.WindowStyle='Hidden';$setup.WorkingDirectory=$PSScriptRoot
   $script:asrSetup=[Diagnostics.Process]::Start($setup);$script:asrStatus.Text='Preparando a escuta aprimorada. Aguarde o download terminar...'
  }catch{$script:asrStatus.Text='Abra Preparar-Escuta.cmd na pasta Cove para preparar.'}
 })
 $voiceList.ItemsSource=$script:voices
 $voiceList.SelectedItem=$script:voices|Where-Object{$_.Id -eq $script:voiceId}|Select-Object -First 1
 $script:voiceHint=$dialog.FindName('VoiceHint')
 $voiceList.Add_SelectionChanged({if($voiceList.SelectedItem){$script:voiceHint.Text=$voiceList.SelectedItem.Description;if($voiceList.SelectedItem.Id.StartsWith('kokoro:') -and -not $voiceEngine.Installed){$script:voiceHint.Text+=' Clique em Preparar Serena e Atlas para o download inicial.'}}})
 if($voiceList.SelectedItem){$script:voiceHint.Text=$voiceList.SelectedItem.Description}
 if(-not $voiceEngine.Installed){$script:voiceHint.Text+=' Primeiro uso: clique em Preparar Serena e Atlas.'}
 $dialog.FindName('PrepareVoices').Add_Click({
  try{
   if($script:voiceSetup -and -not $script:voiceSetup.HasExited){$script:voiceHint.Text='A preparacao ja esta aberta. Aguarde a janela terminar.';return}
   $setup=New-Object Diagnostics.ProcessStartInfo
   $setup.FileName=Join-Path $PSHOME 'powershell.exe'
   $setup.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'Preparar-Vozes.ps1')+'"'
   $setup.WorkingDirectory=$PSScriptRoot;$setup.UseShellExecute=$false;$setup.CreateNoWindow=$true;$setup.WindowStyle='Hidden'
   $script:voiceSetup=[Diagnostics.Process]::Start($setup)
   $script:voiceHint.Text='Baixando e preparando as vozes. Pode levar alguns minutos...'
  }catch{$script:voiceHint.Text='Nao foi possivel iniciar. Abra Preparar-Vozes.cmd na pasta Cove.'}
 })
 $devices=@([CoveApp.Listener]::Devices());$micList.ItemsSource=$devices
 $micList.SelectedItem=$devices|Where-Object{$_.Id -eq $script:micId}|Select-Object -First 1
 if(-not $micList.SelectedItem){$micList.SelectedIndex=0}
 $script:micMeter=$dialog.FindName('MicMeter');$script:micHint=$dialog.FindName('MicHint')
 $dialog.FindName('TestVoice').IsEnabled=$script:voices.Count -gt 0
 $dialog.FindName('TestVoice').Add_Click({if($voiceList.SelectedItem){$script:voiceId=$voiceList.SelectedItem.Id;if($script:voiceId -eq 'kokoro:atlas'){Say 'Ola. Estou a disposicao. Diga o que precisa e vamos organizar os proximos passos.'}else{Say 'Oi. Estou aqui com voce. Podemos conversar com calma, no seu tempo.'}}})
 $dialog.FindName('ApplyAudio').Add_Click({
  try{
   if($script:task -or $script:loginTask -or $script:transcribeTask){$script:micHint.Text='Espere a operacao atual terminar antes de aplicar.';return}
   if($voiceList.SelectedItem){$script:voiceId=$voiceList.SelectedItem.Id}
   if($micList.SelectedItem){$script:micId=[int]$micList.SelectedItem.Id}
   @{Voice=$script:voiceId;Microphone=$script:micId;PresetVersion=1}|ConvertTo-Json|Set-Content -LiteralPath $audioFile -Encoding UTF8
   $voiceEngine.Stop();$script:speechTask=$null;Restart-Listener
   $script:muted=$false;$muteButton.Content='Pausar microfone';Update-Capture
   $script:micHint.Text='Aplicado. Fale para conferir o nivel.'
  }catch{$script:micHint.Text='Nao foi possivel aplicar o audio. Confira o microfone e tente novamente.'}
 })
 $accountStatus=$dialog.FindName('AccountStatus')
 if($script:account -and $script:account.Connected){$accountStatus.Text=$script:account.AccountLabel+' - conectada';$dialog.FindName('ConnectChatGPT').Content='Usar esta conta ChatGPT'}else{$accountStatus.Text='Ainda nao conectada'}
 if($script:mode -eq 'api'){$accountStatus.Text+=' | Modo atual: API'}
 $dialog.FindName('ConnectChatGPT').Add_Click({
  try{if($script:account -and $script:account.Connected){Set-ConnectionMode 'chatgpt';Add-Message 'Cove' 'Usando sua conexao ChatGPT.'}else{Start-ChatGPTConnection 'login'};$dialog.Close()}
  catch{[Windows.MessageBox]::Show('Nao foi possivel iniciar a conexao. Tente novamente.','Cove')|Out-Null}
 })
 $dialog.FindName('DisconnectChatGPT').IsEnabled=$script:account -and $script:account.Connected
 $dialog.FindName('DisconnectChatGPT').Add_Click({Start-ChatGPTConnection 'disconnect';$dialog.Close()})
 $dialog.FindName('CancelLogin').IsEnabled=$null -ne $script:loginTask
 $dialog.FindName('CancelLogin').Add_Click({if($script:loginCancel){$script:loginCancel.Cancel()};$dialog.Close()})
 $dialog.FindName('ManageUsage').Add_Click({Start-Process 'https://chatgpt.com/settings/usage'})
 $dialog.FindName('CloseSettings').Add_Click({$dialog.Close()})
 $dialog.FindName('SettingsHeader').Add_MouseLeftButtonDown({param($sender,$eventArgs) if($eventArgs.OriginalSource -is [Windows.Controls.TextBlock]){$dialog.DragMove()}})
 $inputKey=$dialog.FindName('Key')
 $dialog.FindName('Save').Add_Click({
  $value=$inputKey.Password.Trim()
  if(-not $value.StartsWith('sk-') -or $value.Length -lt 20){[Windows.MessageBox]::Show('Confira sua chave da API. Ela normalmente comeca com sk-.','Cove')|Out-Null;return}
  try{
   $raw=[Text.Encoding]::UTF8.GetBytes($value)
   $encrypted=[Security.Cryptography.ProtectedData]::Protect($raw,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
   [IO.File]::WriteAllBytes($keyFile,$encrypted);[Array]::Clear($raw,0,$raw.Length)
   $script:key=$value;Set-ConnectionMode 'api';$inputKey.Clear();$dialog.Close();Add-Message 'Cove' 'Modo API escolhido. A chave sera validada ao enviar a primeira pergunta.'
  }catch{[Windows.MessageBox]::Show('Nao foi possivel salvar a chave neste usuario do Windows.','Cove')|Out-Null}
 })
 $dialog.FindName('Forget').Add_Click({if(Test-Path -LiteralPath $keyFile){Remove-Item -LiteralPath $keyFile};$script:key='';$dialog.Close();Add-Message 'Cove' 'Chave removida do Cove.'})
 if($SmokeTest){
  $settingsTimer=New-Object Windows.Threading.DispatcherTimer
  $settingsTimer.Interval=[TimeSpan]::FromMilliseconds(600)
  $settingsTimer.Add_Tick({
   $settingsTimer.Stop();$dialog.UpdateLayout()
   $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$dialog.ActualWidth,[int]$dialog.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
   $bitmap.Render($dialog);$png=New-Object Windows.Media.Imaging.PngBitmapEncoder
   $png.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
   $file=[IO.File]::Create((Join-Path $PSScriptRoot 'preview-settings.png'))
   try{$png.Save($file)}finally{$file.Dispose()};$dialog.Close()
  });$settingsTimer.Start()
 }
 try{$dialog.ShowDialog()|Out-Null}finally{$script:micMeter=$null;$script:micHint=$null;$script:voiceHint=$null;$script:asrStatus=$null}
}
function Ask-Cove([string]$question,[switch]$FromVoice,[double]$Confidence=1){
 $question=$question.Trim();if(-not $question -or $script:task -or $script:loginTask -or $script:transcribeTask){return}
 $displayQuestion=$question;$confirmed=$false
 if($script:pendingAppName -and [datetime]::Now -lt $script:pendingAppUntil){
  $reply=ConvertTo-CoveAppName $question
  if($reply -in @('sim','isso','isso mesmo','sim pode abrir','pode abrir','confirmo','confirma')){$question='abra '+$script:pendingAppName;$confirmed=$true}
  elseif($reply -in @('nao','cancela','cancelar','nao obrigado','nao abre','nao pode cancelar')){
   $script:pendingAppName='';$script:listenAfterSpeech=$false;$script:resumeListeningAt=[datetime]::MinValue
   Add-Message 'Voce' $displayQuestion;Add-Message 'Cove' 'Cancelado. Nao vou abrir o aplicativo.';Say 'Cancelado.';return
  }
 }
 $script:pendingAppName='';$script:listenAfterSpeech=$false;$script:resumeListeningAt=[datetime]::MinValue
 $localAction=Invoke-CoveAppRequest $question -DryRun:$SmokeTest -RequireConfirmation:($FromVoice -and $Confidence -lt 0.72 -and -not $confirmed)
 if($localAction.Handled){
  $voiceEngine.Stop();$script:speechTask=$null;$script:listenUntil=[datetime]::MinValue;$script:state='Idle'
  if($localAction.NeedsConfirmation){$script:pendingAppName=$localAction.AppName;$script:pendingAppUntil=[datetime]::Now.AddSeconds(90);$script:listenAfterSpeech=$true}
  Add-Message 'Voce' $displayQuestion;Add-Message 'Cove' $localAction.Message
  Say $localAction.Message
  if($script:listenAfterSpeech -and $script:state -ne 'Speaking'){$script:resumeListeningAt=[datetime]::Now.AddMilliseconds(400);$script:listenAfterSpeech=$false}
  Update-Capture;return
 }
 if($script:mode -eq 'chatgpt' -and (-not $script:account -or -not $script:account.Connected)){$script:state='Idle';$chat.Show();Add-Message 'Cove' 'Entre em Ajustes > Continuar com ChatGPT para conectar sua conta.';Show-Settings;return}
 if($script:mode -eq 'api' -and -not $script:key){$script:state='Idle';$chat.Show();Add-Message 'Cove' 'Cadastre uma chave em Ajustes ou escolha Continuar com ChatGPT.';Show-Settings;return}
 try{
  $voiceEngine.Stop();$script:speechTask=$null
  $script:state='Thinking';$script:listenUntil=[datetime]::MinValue;Update-Capture
  Add-Message 'Voce' $question;$script:pendingQuestion=$question
  $messages=@($script:history)+@(@{role='user';content=$question})
  $body=@{model='gpt-4.1-mini';instructions='Voce e Cove, um assistente de voz amigavel. Fale portugues brasileiro natural, com respostas curtas, sem markdown. Seu nome se pronuncia Couve. Voce e a conversa de um aplicativo independente. O Cove pode abrir apps cadastrados por comandos locais, como abre o Discord. Esses comandos sao tratados pelo aplicativo, fora desta conversa. Se um pedido de abertura chegar aqui, oriente a usar o botao Apps ou dizer abre o Discord; nao afirme que o Cove e incapaz de abrir apps. Voce nao executa acoes pelo texto da resposta nem ve arquivos ou tela. Nao finja executar acoes. Quando nao souber, diga com clareza.';input=$messages;max_output_tokens=400;store=$false}|ConvertTo-Json -Depth 12 -Compress
  $script:cancel=New-Object Threading.CancellationTokenSource
  if($script:mode -eq 'chatgpt'){$script:task=$script:account.Ask($body,$script:cancel.Token)}else{$script:task=[CoveApp.Brain]::Ask($script:key,$body,$script:cancel.Token)}
  $sendButton.IsEnabled=$false
 }catch{$script:state='Idle';Add-Message 'Cove' 'Nao foi possivel iniciar a pergunta. Confira a configuracao.';Update-Capture}
}
function Begin-Listening([switch]$FromWake) {
 if($script:task -or $script:transcribeTask){return}
 if(-not $script:listener -or -not $script:listener.Ready){$chat.Show();Add-Message 'Cove' 'A escuta ainda nao esta disponivel. Voce pode digitar sua pergunta aqui.';return}
 if($script:muted){return}
 $voiceEngine.Stop();$script:speechTask=$null
 $script:listener.ReplayWakeAudio=[bool]$FromWake
 $script:state='Listening';$script:listenUntil=[datetime]::Now.AddSeconds(12);$script:cooldown=[datetime]::MinValue;Update-Capture
}
function Toggle-Microphone {
 $script:muted=-not $script:muted;$script:listenUntil=[datetime]::MinValue
 if($script:muted -and $script:transcribeTask){$transcriber.Stop();$script:transcribeTask=$null;$script:state='Idle';$sendButton.IsEnabled=$true}
 if($script:state -eq 'Listening'){$script:state='Idle'}
 if($script:muted){$muteButton.Content='Retomar microfone'}else{$muteButton.Content='Pausar microfone'}
 Update-Capture
}
$openChat.Add_Click({$chat.WindowState='Normal';$chat.Show();$chat.Activate()|Out-Null})
$orb.Add_Click({if($script:state -eq 'Speaking'){$voiceEngine.Stop();$script:speechTask=$null;$script:state='Idle';$script:cooldown=[datetime]::Now.AddMilliseconds(900)}elseif($script:state -eq 'Transcribing'){$transcriber.Stop();$script:transcribeTask=$null;$script:state='Idle';$sendButton.IsEnabled=$true;Begin-Listening}else{Begin-Listening}})
$sendButton.Add_Click({$q=$promptBox.Text;$promptBox.Clear();Ask-Cove $q})
$promptBox.Add_KeyDown({param($sender,$eventArgs) if($eventArgs.Key -eq 'Return' -and $sendButton.IsEnabled){$q=$promptBox.Text;$promptBox.Clear();Ask-Cove $q;$eventArgs.Handled=$true}})
$chat.FindName('Configure').Add_Click({Show-Settings})
$chat.FindName('Apps').Add_Click({Show-CoveApplications})
$muteButton.Add_Click({Toggle-Microphone})
$chat.FindName('Clear').Add_Click({if(-not $script:task){$script:history=@();$transcript.Clear()}})
$menu=New-Object Windows.Controls.ContextMenu
foreach($label in @('Pausar / retomar microfone','Conversa','Sair')){$item=New-Object Windows.Controls.MenuItem;$item.Header=$label;$menu.Items.Add($item)|Out-Null}
$menu.Items[0].Add_Click({Toggle-Microphone});$menu.Items[1].Add_Click({$chat.Show()});$menu.Items[2].Add_Click({$window.Close()});$orb.ContextMenu=$menu
$assets=Join-Path $PSScriptRoot 'assets'
$modelReady=(Test-Path -LiteralPath (Join-Path $assets 'vosk-model-small-pt-0.3\final.mdl')) -or (Test-Path -LiteralPath (Join-Path $assets 'vosk-model-small-pt-0.3\am\final.mdl'))
if(-not $SmokeTest -and (Test-Path -LiteralPath (Join-Path $assets 'native\libvosk.dll')) -and $modelReady){
 Restart-Listener
}elseif(-not $SmokeTest){Add-Message 'Cove' 'Para ativar o microfone local, execute Preparar-Cove.cmd. Enquanto isso, voce pode digitar.'}
Add-Message 'Cove' 'Oi! Diga meu nome ou escreva aqui. Estou por perto.'
if($script:mode -eq 'chatgpt' -and (-not $script:account -or -not $script:account.Connected)){Add-Message 'Cove' 'Para conectar sua conta, abra Ajustes e escolha Continuar com ChatGPT.'}
$script:pulse=0
$timer=New-Object Windows.Threading.DispatcherTimer
$timer.Interval=[TimeSpan]::FromMilliseconds(80)
$timer.Add_Tick({
 $script:pulse+=0.16
 try{
  if($script:asrSetup -and $script:asrSetup.HasExited){
   if($script:asrSetup.ExitCode -eq 0 -and $transcriber.Installed){Restart-Listener;$asrMessage='Escuta aprimorada ativada. Fale no seu ritmo.'}
   else{$asrMessage='Nao foi possivel preparar a escuta. Abra Preparar-Escuta.cmd para ver o erro.'}
   if($script:asrStatus){$script:asrStatus.Text=$asrMessage}else{Add-Message 'Cove' $asrMessage}
   $script:asrSetup.Dispose();$script:asrSetup=$null
  }
  if($script:transcribeTask -and $script:transcribeTask.IsCompleted){
   $finishedTranscription=$script:transcribeTask;$script:transcribeTask=$null;$script:state='Idle';$sendButton.IsEnabled=$true
   try{
    $recognized=$finishedTranscription.GetAwaiter().GetResult()|ConvertFrom-Json
    if($recognized.error){throw [Exception]::new([string]$recognized.error)}
    $spokenText=[string]$recognized.text
    if($spokenText.Trim()){
     $script:lastHeard='Ouvi: '+$spokenText;$heardLabel.Text=$script:lastHeard;$status.ToolTip=$script:lastHeard
     $question=[regex]::Replace($spokenText,'(?i)^\s*(?:oi[, ]+)?(?:cove|couve|couvi|coube)\b[ ,.!?:]*','').Trim()
     if($question){$certainty=1.0;if($recognized.uncertain){$certainty=0.6};Ask-Cove $question -FromVoice -Confidence $certainty}
     else{Begin-Listening}
    }else{$heardLabel.Text='Nao identifiquei uma frase. Clique na bolinha para tentar de novo.'}
   }catch{if(-not $finishedTranscription.IsCanceled){Add-Message 'Cove' $_.Exception.GetBaseException().Message;$heardLabel.Text='Nao consegui entender. Clique na bolinha para repetir.'}}
  }
  if($script:voiceSetup -and $script:voiceSetup.HasExited){
   if($script:voiceSetup.ExitCode -eq 0 -and $voiceEngine.Installed){$setupMessage='Serena e Atlas estao prontas. Escolha uma voz e clique em Ouvir esta voz.'}else{$setupMessage='A preparacao das vozes falhou. Abra Preparar-Vozes.cmd para ver a mensagem e tentar novamente.'}
   if($script:voiceHint){$script:voiceHint.Text=$setupMessage}else{Add-Message 'Cove' $setupMessage}
   $script:voiceSetup.Dispose();$script:voiceSetup=$null
  }
  if($script:loginTask -and $script:loginTask.IsCompleted){
   try{
    $connectionResult=$script:loginTask.GetAwaiter().GetResult()
    if($script:loginKind -eq 'login'){Set-ConnectionMode 'chatgpt';Add-Message 'Cove' ('Conta conectada: '+$connectionResult+'. Agora pode me chamar por voz.')}
    else{Set-ConnectionMode 'chatgpt';Add-Message 'Cove' $connectionResult}
   }catch{
    if($_.Exception.GetBaseException() -is [OperationCanceledException]){Add-Message 'Cove' 'Conexao cancelada ou tempo de login esgotado.'}
    else{Add-Message 'Cove' $_.Exception.GetBaseException().Message}
   }finally{$script:loginTask=$null;if($script:loginCancel){$script:loginCancel.Dispose();$script:loginCancel=$null};$sendButton.IsEnabled=$true}
  }
  if($script:task -and $script:task.IsCompleted){
   try{
    $answer=$script:task.GetAwaiter().GetResult()
    $script:history=@($script:history)+@(@{role='user';content=$script:pendingQuestion},@{role='assistant';content=$answer})
    if($script:history.Count -gt 16){$script:history=@($script:history|Select-Object -Last 16)}
    Add-Message 'Cove' $answer;Say $answer
   }catch{$script:state='Idle';Add-Message 'Cove' $_.Exception.GetBaseException().Message;$chat.Show()}
   finally{$script:task=$null;if($script:cancel){$script:cancel.Dispose();$script:cancel=$null};$sendButton.IsEnabled=$true}
  }
  if($script:speechTask -and $script:speechTask.IsCompleted){
   try{$script:speechTask.GetAwaiter().GetResult()|Out-Null}catch{if(-not $script:speechTask.IsCanceled){$voiceError=$_.Exception.GetBaseException().Message;Add-Message 'Cove' $voiceError;if($script:voiceHint){$script:voiceHint.Text=$voiceError}}}
   $script:speechTask=$null;if($script:state -eq 'Speaking'){$script:state='Idle';$script:cooldown=[datetime]::Now.AddMilliseconds(900)}
   if($script:listenAfterSpeech){$script:resumeListeningAt=[datetime]::Now.AddMilliseconds(1000);$script:listenAfterSpeech=$false}
  }
  if($script:resumeListeningAt -ne [datetime]::MinValue -and [datetime]::Now -ge $script:resumeListeningAt){$script:resumeListeningAt=[datetime]::MinValue;Begin-Listening}
  if($script:pendingAppName -and [datetime]::Now -gt $script:pendingAppUntil){$script:pendingAppName=''}
  Update-Capture
  if($script:listener){
   if($script:micMeter){$script:micMeter.Value=[Math]::Min(100,$script:listener.Level*100)}
   if($script:micHint){
    if($script:lastError){$script:micHint.Text=$script:lastError}
    elseif($script:listener.Paused){$script:micHint.Text='Escuta pausada enquanto o Cove fala ou esta conectando.'}
    elseif($script:listener.Ready){$script:micHint.Text='Fale e observe a barra. '+$script:lastHeard}
    else{$script:micHint.Text='Preparando o microfone...'}
   }
   $ev=''
   while($script:listener.Events.TryDequeue([ref]$ev)){
    if($ev.StartsWith('ERROR:')){Add-Message 'Cove' $ev.Substring(6);$script:lastError=$ev.Substring(6);$chat.Show();continue}
    if($script:listener.Paused -or $script:state -in @('Thinking','Speaking') -or $script:muted){continue}
    if($ev -eq 'AUDIO'){$pcm=[byte[]]@();if($script:listener.Audio.TryDequeue([ref]$pcm)){Start-CoveTranscription $pcm};continue}
    if($ev -eq 'WAKE'){$script:lastHeard='Nome reconhecido: Cove';$status.ToolTip='Nome reconhecido. Pode fazer sua pergunta.';$heardLabel.Text='Estou ouvindo. Pode fazer sua pergunta.';Begin-Listening -FromWake;continue}
    $text='';$final=$false;$confidence=1.0
    if($ev.StartsWith('FINAL:')){
     $recognition=$ev.Substring(6)|ConvertFrom-Json;$text=$recognition.text;$final=$true
     if($recognition.result){$confidence=[double](($recognition.result|Measure-Object -Property conf -Average).Average)}
    }
    elseif($ev.StartsWith('PARTIAL:')){$text=($ev.Substring(8)|ConvertFrom-Json).partial}
    if(-not $text){continue}
    $script:lastHeard='Ouvi: '+$text;$status.ToolTip=$script:lastHeard;$heardLabel.Text=$script:lastHeard
    $hasWake=$text -match '(?i)\b(cove|couve|couvi)\b'
    if($script:state -eq 'Idle' -and $hasWake){Begin-Listening}
    if($script:state -eq 'Listening'){
     if(-not $final){$script:listenUntil=[datetime]::Now.AddSeconds(12)}
     if($final){$question=[regex]::Replace($text,'(?i)^.*?\b(cove|couve|couvi)\b[ ,.!?]*','').Trim();if($question -and $question -notmatch '^(oi|ola)$'){Ask-Cove $question -FromVoice -Confidence $confidence}}
    }
   }
  }
  if($script:state -eq 'Listening' -and [datetime]::Now -gt $script:listenUntil){$script:state='Idle'}
  switch($script:state){
   'Listening'{$color='#087D69';$label='Ouvindo...'}
   'Thinking'{$color='#9A6915';$label='Pensando...'}
   'Transcribing'{$color='#31667A';$label='Entendendo sua fala...'}
   'Speaking'{$color='#7954BE';$label='Respondendo'}
   default{
    $color='#153D57'
    if($script:loginTask){$label='Conectando ChatGPT...'}
    elseif($script:muted){$label='Microfone pausado';$color='#4D5664'}
    elseif($script:listener -and $script:listener.Ready){$label='Diga Cove'}
    elseif($script:listener -and -not $script:lastError){$label='Preparando a escuta...'}
    else{$label='Microfone indisponivel'}
   }
  }
  $orb.Background=$color;$status.Text=$label;$orb.Opacity=0.72+0.28*[Math]::Abs([Math]::Sin($script:pulse))
  if($script:state -eq 'Listening' -and $script:listener){$glow.BlurRadius=16+20*$script:listener.Level}else{$glow.BlurRadius=16}
 }catch{$script:state='Idle';Add-Message 'Cove' 'Ocorreu um erro na escuta. Reinicie o Cove ou digite sua pergunta.'}
})
$window.Add_Closed({
 $timer.Stop();$script:quitting=$true
 if($script:cancel){$script:cancel.Cancel();$script:cancel.Dispose()}
 if($script:loginCancel){$script:loginCancel.Cancel();$script:loginCancel.Dispose()}
 if($script:listener){$script:listener.Dispose()}
 $transcriber.Dispose()
 try{$voiceEngine.Dispose()}catch{}
 $script:key='';$script:history=@();$chat.Close()
})
$window.Add_ContentRendered({if($SmokeTest){$chat.Show();'WINDOW_RENDERED_V3'|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'smoke-test.log')}})
$timer.Start()
if($SmokeTest){
 $smokeTimer=New-Object Windows.Threading.DispatcherTimer
 $smokeTimer.Interval=[TimeSpan]::FromSeconds(3)
 $smokeTimer.Add_Tick({
  $smokeTimer.Stop()
  foreach($entry in @(@{View=$window;File='preview-orb.png'},@{View=$chat;File='preview-chat.png'})){
   $view=$entry.View;$view.UpdateLayout()
   $image=New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$view.ActualWidth,[int]$view.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
   $image.Render($view)
   $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
   $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
   $stream=[IO.File]::Create((Join-Path $PSScriptRoot $entry.File))
   try{$encoder.Save($stream)}finally{$stream.Dispose()}
  }
  Show-Settings
  Show-CoveApplications
  $window.Close()
 });$smokeTimer.Start()
}
$window.ShowDialog()|Out-Null
