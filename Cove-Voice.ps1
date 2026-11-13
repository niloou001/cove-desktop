param([switch]$SmokeTest,[switch]$ListenOnStart,[switch]$OpenDiscordSettings)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'CoveInstance.ps1')
. (Join-Path $PSScriptRoot 'CoveRuntime.ps1')
$script:buildId=Get-CoveBuildId $PSScriptRoot
$script:selfRestart=$false
$instanceChannel=$null
if(-not $SmokeTest){
 $instanceChannel=Open-CoveInstanceChannel -Identity $PSScriptRoot -Listen:$ListenOnStart -DiscordSettings:$OpenDiscordSettings
 if($instanceChannel.AlreadyRunning){Close-CoveInstanceChannel $instanceChannel;return}
}
. (Join-Path $PSScriptRoot 'CoveApps.ps1')
. (Join-Path $PSScriptRoot 'CoveIdentity.ps1')
. (Join-Path $PSScriptRoot 'CoveOnline.ps1')
. (Join-Path $PSScriptRoot 'CoveFiles.ps1')
. (Join-Path $PSScriptRoot 'CoveControl.ps1')
. (Join-Path $PSScriptRoot 'CoveDiscord.ps1')
. (Join-Path $PSScriptRoot 'CoveMessages.ps1')
. (Join-Path $PSScriptRoot 'CoveShortcuts.ps1')
. (Join-Path $PSScriptRoot 'CoveMessagePlanner.ps1')
. (Join-Path $PSScriptRoot 'CoveDiscordLinks.ps1')
. (Join-Path $PSScriptRoot 'CoveAppearance.ps1')
. (Join-Path $PSScriptRoot 'CoveAppPanel.ps1')
. (Join-Path $PSScriptRoot 'CoveConversation.ps1')
. (Join-Path $PSScriptRoot 'CoveDrafts.ps1')
Add-Type -Path @((Join-Path $PSScriptRoot 'CoveComputer.cs'),(Join-Path $PSScriptRoot 'CoveDiscord.cs'),(Join-Path $PSScriptRoot 'CoveMessaging.cs')) -ReferencedAssemblies UIAutomationClient,UIAutomationTypes,WindowsBase,System.Security
$script:discordTask=$null;$script:discordCancel=$null
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Speech,System.Security,System.Net.Http,System.Web.Extensions
Add-Type -Path (Join-Path $PSScriptRoot 'CoveOnline.cs') -ReferencedAssemblies System.Net.Http,System.Web.Extensions,System.Xml
trap { if($SmokeTest){Write-Output $_.Exception.Message;exit 1};try { [Windows.MessageBox]::Show($_.Exception.Message,'Cove: erro') | Out-Null } catch {}; exit 1 }
Add-Type -Path @((Join-Path $PSScriptRoot 'CoveCore.cs'),(Join-Path $PSScriptRoot 'CoveASR.cs')) -ReferencedAssemblies System.Net.Http,System.Web.Extensions
$transcriber=New-Object CoveApp.CoveTranscription($PSScriptRoot)
$script:transcribeTask=$null;$script:asrSetup=$null;$script:asrStatus=$null
Add-Type -Path (Join-Path $PSScriptRoot 'CoveChatGPT.cs') -ReferencedAssemblies System.Net.Http,System.Web.Extensions,System.Security
Add-Type -Path @((Join-Path $PSScriptRoot 'CoveVoice.cs'),(Join-Path $PSScriptRoot 'CoveNeural.cs')) -ReferencedAssemblies System.Web.Extensions
$audioFile=Join-Path $PSScriptRoot 'cove-audio.json'
$script:micId=-1;$script:voiceId='';$script:speechTask=$null;$script:vocabulary=''
$script:micMeter=$null;$script:micHint=$null;$script:lastHeard='';$script:voiceSetup=$null;$script:voiceHint=$null
if(Test-Path -LiteralPath $audioFile){try{$audioSettings=Get-Content -LiteralPath $audioFile -Raw|ConvertFrom-Json;$script:micId=[int]$audioSettings.Microphone;$script:voiceId=[string]$audioSettings.Voice;$script:vocabulary=[string]$audioSettings.Vocabulary}catch{}}
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
 catch{$script:account=$null;$script:lastAccountStartupError=$true}
}
$script:listener=$null; $script:task=$null; $script:cancel=$null
$script:history=@(); $script:state='Idle'; $script:muted=$false
$script:streamActive=$false;$script:streamHadText=$false;$script:suppressSpeech=$false;$script:streamBuffer='';$script:streamSpeechStarted=$false
$script:messagePlanPending=$false
$script:speechQueue=New-Object 'Collections.Generic.Queue[string]'
$script:warmTasks=@()
$script:listenUntil=[datetime]::MinValue; $script:cooldown=[datetime]::MinValue
$script:pendingQuestion=''; $script:lastError=''; $script:quitting=$false
$script:pendingAppName='';$script:pendingAppUntil=[datetime]::MinValue;$script:resumeListeningAt=[datetime]::MinValue;$script:listenAfterSpeech=$false
$script:key=$env:OPENAI_API_KEY
$keyFile=Join-Path $PSScriptRoot 'cove-key.dat'
if (-not $script:key -and (Test-Path -LiteralPath $keyFile)) {
 try { $raw=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($keyFile),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser); $script:key=[Text.Encoding]::UTF8.GetString($raw); [Array]::Clear($raw,0,$raw.Length) } catch {}
}
$window=New-Object Windows.Window
$window.Title='Cove';$window.Width=190;$window.Height=214
$window.WindowStyle='None';$window.ResizeMode='NoResize';$window.AllowsTransparency=$true
$window.Background='Transparent';$window.Topmost=$false;$window.ShowActivated=$false
$window.FontFamily='Segoe UI'
$window.Left=[Windows.SystemParameters]::WorkArea.Right-$window.Width-26
$window.Top=[Windows.SystemParameters]::WorkArea.Bottom-$window.Height-26
$theme=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Cove-Theme.xaml')))
$window.Resources.MergedDictionaries.Add($theme)
$script:appearance=[pscustomobject]@{File=(Join-Path $PSScriptRoot 'cove-appearance.json');Hex='';Palette=$null}
$script:appearance.Hex=Get-CoveAccent $script:appearance.File
$script:appearance.Palette=Set-CoveAccent $window $script:appearance.Hex
$panel=New-Object Windows.Controls.StackPanel
$orb=New-Object Windows.Controls.Button
$orb.Width=108;$orb.Height=108;$orb.Margin='16,16,16,8';$orb.Content='';$orb.Foreground='#EBF8FF';$orb.FontSize=14
$orb.Template=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Cove-Orb.xaml')))
$glow=New-Object Windows.Media.Effects.DropShadowEffect
$glow.Color=[Windows.Media.ColorConverter]::ConvertFromString('#64B6DA');$glow.ShadowDepth=0;$glow.BlurRadius=24;$glow.Opacity=0.28;$orb.Effect=$glow
$status=New-Object Windows.Controls.TextBlock
$status.Foreground='#D1E4E9';$status.TextAlignment='Center';$status.TextWrapping='Wrap';$status.Padding='8,5';$status.FontSize=10
$statusPill=New-Object Windows.Controls.Border
$statusPill.Background='#E0121D2A';$statusPill.BorderBrush='#344755';$statusPill.BorderThickness='1';$statusPill.CornerRadius='16';$statusPill.Margin='12,0,12,0';$statusPill.Padding='5,3';$statusPill.Child=$status
$openChat=New-Object Windows.Controls.Button
$openChat.Content='Conversar';$openChat.Background='Transparent';$openChat.BorderThickness='0';$openChat.Foreground='#A6B8CD';$openChat.Margin='22,4,22,0';$openChat.Padding='10,5';$openChat.FontSize=11
$panel.Children.Add($orb)|Out-Null;$panel.Children.Add($statusPill)|Out-Null;$panel.Children.Add($openChat)|Out-Null;$window.Content=$panel
$status.Add_MouseLeftButtonDown({$window.DragMove()})
$orb.ToolTip='Clique para falar. Arraste pelo texto. Botao direito: pausar ou sair.'
$chat=[Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Conversa com Cove" Width="560" Height="700" WindowStartupLocation="CenterScreen" WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True" Background="Transparent" Foreground="#E6EEF8" FontFamily="Segoe UI">
<Border CornerRadius="28" BorderBrush="#344453" BorderThickness="1" Padding="28"><Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#172635"/><GradientStop Color="#101722" Offset="0.5"/><GradientStop Color="#1D1B32" Offset="1"/></LinearGradientBrush></Border.Background><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<Grid x:Name="DragHeader" Background="Transparent" Margin="0,0,0,20"><StackPanel><TextBlock x:Name="AssistantTitle" Text="Cove" FontSize="30" FontWeight="Light" Foreground="#C9F3E8"/><TextBlock Text="Sua voz. Seu espaco." FontSize="12" Foreground="#91A6BE" Margin="0,4,0,0"/></StackPanel><StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top"><Button x:Name="Minimize" Content="&#x2212;" Width="32" Height="32" Padding="0" Background="Transparent" BorderThickness="0" ToolTip="Minimizar"/><Button x:Name="CloseChat" Content="&#x00D7;" Width="32" Height="32" Padding="0" Background="Transparent" BorderThickness="0" ToolTip="Fechar conversa"/></StackPanel></Grid>
<TextBox x:Name="Transcript" Visibility="Collapsed" IsReadOnly="True"/>
<Border Grid.Row="1" CornerRadius="20" Background="#80101925" BorderBrush="#273947" BorderThickness="1" Padding="12,16,12,0"><ScrollViewer x:Name="MessageScroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"><StackPanel x:Name="MessageList"/></ScrollViewer></Border>
<DockPanel Grid.Row="2" Margin="0,16,0,0"><Button x:Name="Send" Content="Enviar" DockPanel.Dock="Right" Background="#305D65" BorderBrush="#53878A" Padding="16,10"/><TextBox x:Name="Prompt" Margin="0,0,8,0" ToolTip="Escreva uma mensagem" MinHeight="44" VerticalContentAlignment="Center"/></DockPanel>
<StackPanel Grid.Row="3" Margin="0,14,0,0"><WrapPanel><Button x:Name="Configure" Content="Ajustes" Padding="11,7" Background="Transparent"/><Button x:Name="Mute" Content="Pausar microfone" Margin="8,0,0,0" Padding="11,7" Background="Transparent"/><Button x:Name="Clear" Content="Limpar" Margin="8,0,0,0" Padding="11,7" Background="Transparent"/><Button x:Name="DiscordSettings" Content="Discord e mouse" Margin="8,0,0,0" Padding="11,7" Background="Transparent"/><Button x:Name="Apps" Content="Apps e jogos" Margin="8,0,0,0" Padding="11,7" Background="Transparent"/></WrapPanel><TextBlock x:Name="Heard" Text="Diga Cove e espere ficar verde, ou clique na bolinha." TextWrapping="Wrap" Foreground="#91A6BE" FontSize="11" Margin="1,13,0,0"/></StackPanel>
</Grid></Border></Window>
'@)
$chat.Resources.MergedDictionaries.Add($theme)
$chat.FindName('AssistantTitle').Text=$script:assistantName
$chat.Topmost=$false
$chat.FindName('DragHeader').Add_MouseLeftButtonDown({param($sender,$eventArgs) if($eventArgs.OriginalSource -is [Windows.Controls.TextBlock] -or $eventArgs.OriginalSource -eq $sender){$chat.DragMove()}})
$chat.FindName('CloseChat').Add_Click({$chat.Hide()})
$chat.FindName('Minimize').Add_Click({$chat.WindowState='Minimized'})
$transcript=$chat.FindName('Transcript');$promptBox=$chat.FindName('Prompt')
$transcript.Add_TextChanged({Update-CoveConversation})
$sendButton=$chat.FindName('Send');$muteButton=$chat.FindName('Mute')
$heardLabel=$chat.FindName('Heard')
$heardLabel.Text='Diga '+$script:assistantName+' e espere ficar verde, ou clique na bolinha.'
$chat.Add_Closing({param($sender,$eventArgs) if(-not $script:quitting){$eventArgs.Cancel=$true;$chat.Hide()}})
function Add-Message([string]$who,[string]$text){$transcript.AppendText($who+': '+$text+"`r`n`r`n");$transcript.ScrollToEnd()}
function Update-Capture {if($script:listener){$script:listener.Paused=$script:muted -or $null -ne $script:loginTask -or $null -ne $script:discordTask -or $null -ne $script:task -or ($script:mouseTestProcess -and -not $script:mouseTestProcess.HasExited) -or $script:state -in @('Thinking','Speaking','Transcribing') -or [datetime]::Now -lt $script:cooldown;$script:listener.ListeningMode=$script:state -eq 'Listening'}}
function Restart-Listener {
 $transcriber.Stop();$script:transcribeTask=$null
 if($script:listener){$script:listener.Dispose();$script:listener=$null}
 $script:lastError='';$script:lastHeard=''
 if($script:state -in @('Listening','Transcribing')){$script:state='Idle'}
 if($sendButton){$sendButton.IsEnabled=-not ($script:task -or $script:discordTask -or $script:loginTask)}
 if(-not $SmokeTest -and $modelReady -and (Test-Path -LiteralPath (Join-Path $assets 'native\libvosk.dll'))){$script:listener=New-Object CoveApp.Listener((Join-Path $assets 'native'),(Join-Path $assets 'vosk-model-small-pt-0.3'),$script:micId,$script:assistantName);$script:listener.UseNeural=$transcriber.Installed;Update-Capture}
}
function Set-ConnectionMode([string]$value){[IO.File]::WriteAllText($modeFile,$value);$script:mode=$value;$script:history=@()}
function Start-ChatGPTConnection([string]$action){
 if($script:task -or $script:loginTask -or $script:discordTask -or $script:transcribeTask -or ($script:mouseTestProcess -and -not $script:mouseTestProcess.HasExited)){Add-Message 'Cove' 'Espere a operacao atual terminar.';return}
 if(-not $script:account){Add-Message 'Cove' 'A conexao protegida nao esta disponivel. Reinicie o Cove.';return}
 $script:loginCancel=New-Object Threading.CancellationTokenSource
 $script:loginKind=$action
 if($action -eq 'disconnect'){$script:loginTask=$script:account.Disconnect($script:loginCancel.Token)}
 else{$script:loginTask=$script:account.SignIn($script:loginCancel.Token);Add-Message 'Cove' 'Continue no navegador para entrar e autorizar seu plano ChatGPT. Nenhuma senha e digitada no Cove.'}
 $sendButton.IsEnabled=$false;Update-Capture
}
function Say([string]$text){
 $text=($text -replace 'https?://\S+','').Trim()
 if($script:voiceAvailable){try{$script:state='Speaking';Update-Capture;$script:speechTask=$voiceEngine.Speak($text,$script:voiceId);return}catch{Add-Message 'Cove' 'A voz selecionada nao esta disponivel. Escolha outra em Ajustes.'}}
 $script:state='Idle'
}
function Update-StreamSpeech([switch]$Finish){
 if(-not $script:streamActive -or -not $script:account){return}
 $delta=''
 while($script:account.TextDeltas.TryDequeue([ref]$delta)){
  $script:streamHadText=$true
  if(-not $script:suppressSpeech){$script:streamBuffer+=$delta}
 }
 if($script:suppressSpeech){$script:streamBuffer='';$script:speechQueue.Clear();return}
 if(Test-CoveUnverifiedSendClaim $script:streamBuffer){
  $script:blockedChatSendClaim=$true;$script:suppressSpeech=$true;$script:streamBuffer='';$script:speechQueue.Clear();$voiceEngine.Stop();return
 }
 while($script:streamBuffer){
  $limit=if($script:streamSpeechStarted){110}else{60}
  if(($script:streamBuffer -match '(?s)^(.{12,}?[.!?](?=\s|$))(.*)$') -and ($script:streamSpeechStarted -or $Matches[1].Length -le 70)){
   $script:speechQueue.Enqueue($Matches[1].Trim());$script:streamBuffer=$Matches[2].TrimStart();$script:streamSpeechStarted=$true
   continue
  }
  if($script:streamBuffer.Length -le $limit){break}
  $cut=$script:streamBuffer.LastIndexOf(' ', $(if($script:streamSpeechStarted){100}else{60}))
  if($cut -lt 20){break}
  $script:speechQueue.Enqueue($script:streamBuffer.Substring(0,$cut).Trim())
  $script:streamBuffer=$script:streamBuffer.Substring($cut).TrimStart()
  $script:streamSpeechStarted=$true
 }
 if($Finish -and $script:streamBuffer.Trim()){$script:speechQueue.Enqueue($script:streamBuffer.Trim());$script:streamBuffer=''}
}
function Start-CoveTranscription([byte[]]$pcm){
 if($script:transcribeTask -or $script:task -or $script:loginTask){return}
 $script:state='Transcribing';$script:listenUntil=[datetime]::MinValue;Update-Capture
 $heardLabel.Text='Estou entendendo sua frase...';$sendButton.IsEnabled=$false
 # A small relevant vocabulary avoids biasing every sentence toward 146 app names.
 $names=(@($script:vocabulary)+@($script:assistantName,'Cove','Discord','Spotify','Steam','Chrome','WhatsApp','Bloco de notas','CapCut','Roblox','Marvel Rivals','Visual Studio Code')) -join ', '
 if(Test-Path -LiteralPath $script:coveDiscordFile){try{$callHint=Get-Content -LiteralPath $script:coveDiscordFile -Raw|ConvertFrom-Json;$names=$script:vocabulary+', '+$callHint.Name+', '+$names}catch{}}
 if($script:discordDialog -and $script:discordDialog.Stage -eq 'channel'){$names=$script:vocabulary+', Geral, Lounge, Sala, cancelar'}
 $messageHint=Get-CoveMessageContext
 if($script:messageDialog -and $script:messageDialog.Recipient){$names=$script:messageDialog.Recipient+', Discord, WhatsApp, cancelar, '+$names}
 elseif($messageHint){$names=$messageHint.Recipient+', '+$messageHint.Platform+', '+$names}
 if($script:pendingMessageText){$names='Sim, nao, pode mandar, pode enviar, cancelar'}
 if($script:pendingAppName){$names='Sim, nao, pode abrir, cancelar'}
 $script:transcribeTask=$transcriber.Transcribe($pcm,$names)
}
function Show-Settings([switch]$Discord){
 $dialog=[Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Ajustes do Cove" Width="460" SizeToContent="Height" MaxHeight="760" WindowStartupLocation="CenterOwner" WindowStyle="None" AllowsTransparency="True" Background="Transparent" Foreground="#E6EEF8" FontFamily="Segoe UI" ResizeMode="NoResize"><Border CornerRadius="28" Background="#FF101B29" BorderBrush="#344453" BorderThickness="1" Padding="24"><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel><DockPanel x:Name="SettingsHeader" Background="Transparent" Margin="0,0,0,20"><Button x:Name="CloseSettings" Content="&#x00D7;" DockPanel.Dock="Right" Width="30" Height="30" Padding="0" Background="Transparent" BorderThickness="0" HorizontalAlignment="Right"/><TextBlock Text="Ajustes" FontSize="22" FontWeight="SemiBold"/></DockPanel>
<TextBlock x:Name="BuildInfo" Foreground="#91A6BE" FontSize="10" Margin="0,0,0,12"/>
<Expander Header="Atalhos de teclado" IsExpanded="True" Foreground="#D1E4E9" Margin="0,0,0,12"><StackPanel Margin="0,10,0,0">
<TextBlock Text="Funcionam com a janela do Cove em foco. Clique no campo e pressione a combinacao desejada. Delete remove o atalho; Esc cancela a captura." TextWrapping="Wrap" Foreground="#91A6BE" FontSize="12"/>
<TextBlock Text="Pausar ou retomar microfone" Margin="0,10,0,5"/><TextBox x:Name="MicrophoneShortcut" IsReadOnly="True" ToolTip="Clique e pressione as teclas"/>
<TextBlock Text="Limpar conversa" Margin="0,10,0,5"/><TextBox x:Name="ClearConversationShortcut" IsReadOnly="True" ToolTip="Clique e pressione as teclas"/>
<WrapPanel Margin="0,10,0,0"><Button x:Name="SaveShortcuts" Content="Salvar atalhos"/><Button x:Name="ResetShortcuts" Content="Restaurar padrao" Margin="8,0,0,0" Background="Transparent"/></WrapPanel>
<TextBlock x:Name="ShortcutStatus" TextWrapping="Wrap" Foreground="#91A6BE" FontSize="11" Margin="0,8,0,0"/>
</StackPanel></Expander>
<Expander x:Name="CallsExpander" Header="Calls do Discord e mouse" IsExpanded="True" Foreground="#D1E4E9" Margin="0,16,0,18"><StackPanel Margin="0,10,0,0">
<TextBlock Text="Escolha como entrar. Mouse move o ponteiro ate os alvos nos dois monitores. Esc ou mover o mouse interrompe. Links salvos sao uma alternativa opcional. Servidores: entre no servidor NOME e na call CANAL. Privado: liga para NOME no Discord." TextWrapping="Wrap" Foreground="#91A6BE" FontSize="12"/>
<ComboBox x:Name="DiscordMethod" Margin="0,10,0,10"/>
<TextBlock x:Name="MouseMonitorInfo" TextWrapping="Wrap" Foreground="#91A6BE" FontSize="11" Margin="0,0,0,8"/>
<Button x:Name="TestMouseMonitors" Content="Testar mouse nos monitores" Margin="0,0,0,6"/>
<TextBlock x:Name="MouseTestStatus" Text="O teste move e clica em uma janela de teste em cada monitor. Esc interrompe." TextWrapping="Wrap" Foreground="#91A6BE" FontSize="11" Margin="0,0,0,12"/>
<Expander Header="Links salvos (opcional)" Foreground="#91A6BE"><StackPanel>
<ListBox x:Name="SavedCalls" DisplayMemberPath="Name" Height="85" Background="#161E2B" Foreground="#E7EDF5" BorderBrush="#303B4C"/>
<TextBlock Text="Servidor" Foreground="#91A6BE" Margin="0,10,0,4"/><TextBox x:Name="CallServer" MaxLength="100"/>
<TextBlock Text="Nome da call" Foreground="#91A6BE" Margin="0,8,0,4"/><TextBox x:Name="CallChannel" MaxLength="100"/>
<TextBlock Text="Link do canal de voz" Foreground="#91A6BE" Margin="0,8,0,4"/><TextBox x:Name="CallLink" ToolTip="Botao direito no canal do Discord e Copiar link"/>
<Button x:Name="SaveCallLink" Content="Salvar canal" Margin="0,10,0,0" Background="#305D65" BorderBrush="#53878A"/>
<WrapPanel Margin="0,8,0,0"><Button x:Name="TestCallLink" Content="Entrar na selecionada" Padding="10,7"/><Button x:Name="RemoveCallLink" Content="Remover" Margin="8,0,0,0" Padding="10,7"/></WrapPanel>
<TextBlock x:Name="CallStatus" TextWrapping="Wrap" Foreground="#91A6BE" FontSize="11" Margin="0,8,0,0"/>
</StackPanel></Expander>
</StackPanel></Expander>
<TextBlock Text="Personalizar a Cove" FontSize="17" Margin="0,0,0,10"/>
<TextBlock Text="Nome exibido da assistente" Margin="0,0,0,5"/><TextBox x:Name="AssistantName" MaxLength="24"/>
<WrapPanel Margin="0,8,0,0"><Button x:Name="SaveAssistantName" Content="Salvar nome"/><Button x:Name="ResetAssistantName" Content="Restaurar Cove" Background="Transparent" Margin="8,0,0,0"/></WrapPanel>
<TextBlock x:Name="NameStatus" Text="Muda o nome na conversa, nas respostas e na ativacao por voz. Use o novo nome para chamar por voz." FontSize="11" Foreground="#91A6BE" TextWrapping="Wrap" Margin="0,6,0,14"/>
<Button x:Name="SavedDrafts" Content="Ver rascunhos preservados" Background="Transparent" Margin="0,0,0,12"/>
<Expander Header="Horario, temperatura e noticias" Foreground="#D1E4E9" Margin="0,0,0,14"><StackPanel Margin="0,8,0,0">
<TextBlock Text="Horario do Windows. Temperatura: Open-Meteo. Noticias: BBC News Brasil. Pesquisas abrem no Chrome." Foreground="#91A6BE" TextWrapping="Wrap" FontSize="12"/>
<TextBlock Text="Cidade e estado para temperatura" Margin="0,8,0,4"/><TextBox x:Name="WeatherCity" MaxLength="120" ToolTip="Exemplo: Curitiba, Parana"/>
<Button x:Name="SaveWeatherCity" Content="Salvar cidade" Margin="0,8,0,0"/><TextBlock x:Name="WeatherCityStatus" Foreground="#91A6BE" TextWrapping="Wrap" FontSize="11" Margin="0,6,0,0"/>
</StackPanel></Expander>
<Expander x:Name="ColorsExpander" Header="Cores e aparencia" IsExpanded="True" Foreground="#D1E4E9" Margin="0,0,0,20"><StackPanel Margin="0,10,0,0">
<TextBlock Text="Escolha a cor da bolinha e dos detalhes da conversa." Foreground="#91A6BE" FontSize="12" TextWrapping="Wrap" Margin="0,0,0,12"/>
<WrapPanel x:Name="AccentSwatches" Margin="0,0,0,12"/>
<DockPanel><Border x:Name="AccentPreview" DockPanel.Dock="Right" Width="42" Height="42" CornerRadius="14" Margin="10,0,0,0" BorderBrush="#60FFFFFF" BorderThickness="1"/><ComboBox x:Name="AccentList" ToolTip="Paleta de cores"/></DockPanel>
<DockPanel Margin="0,8,0,0"><Button x:Name="ChooseAccent" Content="Escolher cor" DockPanel.Dock="Right" Margin="8,0,0,0"/><TextBox x:Name="AccentHex" MaxLength="7" ToolTip="Cor #RRGGBB"/></DockPanel>
<Button x:Name="ApplyAccent" Content="Aplicar cor" Background="#305D65" BorderBrush="#53878A" Margin="0,8,0,0"/>
<TextBlock x:Name="AccentStatus" Foreground="#91A6BE" FontSize="11" TextWrapping="Wrap" Margin="0,6,0,0"/>
</StackPanel></Expander>
<TextBlock Text="Sua conta ChatGPT" FontSize="17"/>
<TextBlock x:Name="AccountStatus" Foreground="#91A6BE" Margin="0,8,0,12" TextWrapping="Wrap"/>
<Button x:Name="ConnectChatGPT" Content="Continuar com ChatGPT" Background="#F2F5F8" Foreground="#15202B" BorderBrush="#F2F5F8"/>
<TextBlock Text="Entre e autorize no navegador. A disponibilidade depende do seu plano e das permissoes da conta. Suas conversas do ChatGPT nao sao importadas." Foreground="#91A6BE" FontSize="12" TextWrapping="Wrap" Margin="0,12,0,0"/>
<WrapPanel Margin="0,10,0,0"><Button x:Name="DisconnectChatGPT" Content="Desconectar" Background="Transparent" Padding="10,7"/><Button x:Name="ManageUsage" Content="Gerenciar uso" Background="Transparent" Padding="10,7" Margin="8,0,0,0"/><Button x:Name="CancelLogin" Content="Cancelar login" Background="Transparent" Padding="10,7" Margin="8,0,0,0"/></WrapPanel>
<TextBlock Text="Voz" FontSize="17" Margin="0,24,0,10"/>
<TextBlock Text="Seis perfis locais. Luna e Caio sao mais ageis; Lia e a sugestao suave. Escolha uma opcao e ouca antes de aplicar." Foreground="#91A6BE" FontSize="12" TextWrapping="Wrap" Margin="0,0,0,10"/>
<ComboBox x:Name="VoiceList" DisplayMemberPath="Name"/>
<TextBlock x:Name="VoiceHint" TextWrapping="Wrap" Foreground="#91A6BE" FontSize="11" Margin="0,8,0,0"/>
<Button x:Name="TestVoice" Content="Ouvir esta voz" Margin="0,8,0,0" Background="Transparent"/>
<Button x:Name="PrepareVoices" Content="Preparar vozes locais" Margin="0,8,0,0" Background="Transparent"/>
<TextBlock Text="Microfone" FontSize="17" Margin="0,22,0,10"/>
<TextBlock x:Name="RecognitionStatus" Foreground="#91A6BE" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,8"/>
<Button x:Name="ImproveListening" Content="Preparar escuta aprimorada" Background="Transparent" Margin="0,0,0,10"/>
<ComboBox x:Name="MicList" DisplayMemberPath="Name"/>
<ProgressBar x:Name="MicMeter" Minimum="0" Maximum="100" Height="6" Margin="0,12,0,6" Foreground="#67D9BE" Background="#203247" BorderThickness="0"/>
<TextBlock x:Name="MicHint" Text="Fale e observe o nivel do microfone." Foreground="#91A6BE" FontSize="11" TextWrapping="Wrap"/>
<TextBlock Text="Palavras e nomes que voce usa" Foreground="#D1E4E9" FontSize="13" Margin="0,14,0,6"/>
<TextBox x:Name="Vocabulary" MaxLength="240" ToolTip="Nomes de pessoas, jogos ou canais, separados por virgula"/>
<TextBlock Text="Opcional: nomes de amigos, jogos e canais, separados por virgula. Isso ajuda a reconhecer palavras menos comuns." Foreground="#91A6BE" FontSize="11" TextWrapping="Wrap" Margin="0,6,0,0"/>
<Button x:Name="ApplyAudio" Content="Aplicar voz e microfone" Background="#305D65" BorderBrush="#53878A" Margin="0,12,0,0"/>
<TextBlock Text="Se o nivel nao mexer, escolha outro microfone e aplique. Depois diga o nome configurado, espere ficar verde e fale." Foreground="#91A6BE" FontSize="11" TextWrapping="Wrap" Margin="0,8,0,0"/>
<Expander Header="Usar chave da API (alternativa)" Margin="0,24,0,0" Foreground="#91A6BE"><StackPanel Margin="0,14,0,0"><TextBlock Text="A API tem faturamento separado. So sera usada se voce escolher Salvar e usar API." TextWrapping="Wrap" FontSize="12"/><PasswordBox x:Name="Key" Margin="0,14,0,12"/><Button x:Name="Save" Content="Salvar e usar API" Background="#305D65" BorderBrush="#53878A"/><Button x:Name="Forget" Content="Remover chave salva" Background="Transparent" BorderThickness="0" Margin="0,6,0,0"/></StackPanel></Expander>
</StackPanel></ScrollViewer></Border></Window>
'@)
 $dialog.Resources.MergedDictionaries.Add($theme)
 $dialog.Owner=$chat
 $dialog.FindName('BuildInfo').Text='Mouse em 2 monitores | versao '+$script:buildId
 $dialog.FindName('MicrophoneShortcut').Text=$script:shortcuts.Microphone
 $dialog.FindName('ClearConversationShortcut').Text=$script:shortcuts.ClearConversation
 $captureShortcut=[Windows.Input.KeyEventHandler]{param($sender,$eventArgs)
  $key=$eventArgs.Key;if($key -eq [Windows.Input.Key]::System){$key=$eventArgs.SystemKey}
  $eventArgs.Handled=$true
  if($key -in @([Windows.Input.Key]::LeftCtrl,[Windows.Input.Key]::RightCtrl,[Windows.Input.Key]::LeftAlt,[Windows.Input.Key]::RightAlt,[Windows.Input.Key]::LeftShift,[Windows.Input.Key]::RightShift,[Windows.Input.Key]::LWin,[Windows.Input.Key]::RWin)){return}
  if($key -eq [Windows.Input.Key]::Tab){$eventArgs.Handled=$false;return}
  if($key -eq [Windows.Input.Key]::Escape){$dialog.FindName('SaveShortcuts').Focus()|Out-Null;return}
  if($key -in @([Windows.Input.Key]::Delete,[Windows.Input.Key]::Back) -and [Windows.Input.Keyboard]::Modifiers -eq [Windows.Input.ModifierKeys]::None){$sender.Text='';return}
  try{$gesture=New-Object Windows.Input.KeyGesture($key,[Windows.Input.Keyboard]::Modifiers);$sender.Text=ConvertTo-CoveShortcut ((New-Object Windows.Input.KeyGestureConverter).ConvertToInvariantString($gesture));$dialog.FindName('ShortcutStatus').Text='Clique em Salvar atalhos para aplicar.'}catch{$dialog.FindName('ShortcutStatus').Text='Use Ctrl, Alt ou uma tecla de funcao, como F8.'}
 }
 $dialog.FindName('MicrophoneShortcut').Add_PreviewKeyDown($captureShortcut)
 $dialog.FindName('ClearConversationShortcut').Add_PreviewKeyDown($captureShortcut)
 $dialog.FindName('SaveShortcuts').Add_Click({try{
  $script:shortcuts=Save-CoveShortcutSettings $dialog.FindName('MicrophoneShortcut').Text $dialog.FindName('ClearConversationShortcut').Text
  Update-CoveShortcutLabels;$dialog.FindName('ShortcutStatus').Text='Atalhos salvos e aplicados.'
 }catch{$dialog.FindName('ShortcutStatus').Text=$_.Exception.GetBaseException().Message}})
 $dialog.FindName('ResetShortcuts').Add_Click({try{
  $script:shortcuts=Save-CoveShortcutSettings 'Ctrl+Shift+M' 'Ctrl+Shift+L'
  $dialog.FindName('MicrophoneShortcut').Text=$script:shortcuts.Microphone;$dialog.FindName('ClearConversationShortcut').Text=$script:shortcuts.ClearConversation
  Update-CoveShortcutLabels;$dialog.FindName('ShortcutStatus').Text='Atalhos padrao restaurados.'
 }catch{$dialog.FindName('ShortcutStatus').Text=$_.Exception.GetBaseException().Message}})
 $dialog.FindName('AssistantName').Text=$script:assistantName
 $dialog.FindName('SaveAssistantName').Add_Click({try{$saved=Set-CoveAssistantName $dialog.FindName('AssistantName').Text;$chat.FindName('AssistantTitle').Text=$saved;if($heardLabel){$heardLabel.Text='Diga '+$saved+' para conversar.'};Update-CoveConversation;$dialog.FindName('NameStatus').Text='Nome salvo. Use o novo nome para chamar por voz.'}catch{$dialog.FindName('NameStatus').Text=$_.Exception.Message}})
 $dialog.FindName('ResetAssistantName').Add_Click({try{$saved=Set-CoveAssistantName 'Cove';$dialog.FindName('AssistantName').Text=$saved;$chat.FindName('AssistantTitle').Text=$saved;if($heardLabel){$heardLabel.Text='Diga '+$saved+' para conversar.'};Update-CoveConversation;$dialog.FindName('NameStatus').Text='Nome Cove restaurado.'}catch{$dialog.FindName('NameStatus').Text=$_.Exception.Message}})
 $dialog.FindName('SavedDrafts').Add_Click({Show-CoveSavedDrafts})
 $dialog.FindName('WeatherCity').Text=Get-CoveWeatherCity
 $dialog.FindName('SaveWeatherCity').Add_Click({try{Set-CoveWeatherCity $dialog.FindName('WeatherCity').Text;$dialog.FindName('WeatherCityStatus').Text='Cidade salva.'}catch{$dialog.FindName('WeatherCityStatus').Text=$_.Exception.Message}})
 . (Join-Path $PSScriptRoot 'CoveSettingsExtras.ps1')
 if($Discord){$dialog.FindName('CallsExpander').IsExpanded=$true}
 $voiceList=$dialog.FindName('VoiceList');$micList=$dialog.FindName('MicList')
 $vocabularyBox=$dialog.FindName('Vocabulary');$vocabularyBox.Text=$script:vocabulary
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
 $voiceList.Add_SelectionChanged({if($voiceList.SelectedItem){$script:voiceHint.Text=$voiceList.SelectedItem.Description;if($voiceList.SelectedItem.Id.StartsWith('kokoro:') -and -not $voiceEngine.Installed){$script:voiceHint.Text+=' Clique em Preparar vozes locais para o download inicial.'}}})
 if($voiceList.SelectedItem){$script:voiceHint.Text=$voiceList.SelectedItem.Description}
 if(-not $voiceEngine.Installed){$script:voiceHint.Text+=' Primeiro uso: clique em Preparar vozes locais.'}
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
 $dialog.FindName('TestVoice').Add_Click({if($voiceList.SelectedItem){
  $script:voiceId=$voiceList.SelectedItem.Id
  $sample=switch($script:voiceId){
   'kokoro:luna'{'Oi! Eu sou a Luna. Vamos conversar? Me conta o que voce tem em mente hoje.'}
   'kokoro:lia'{'Oi, eu sou a Lia. Estou aqui com voce. Vamos fazer as coisas com calma, do seu jeito.'}
   'kokoro:caio'{'Opa, eu sou o Caio. Pode falar! Vamos resolver isso juntos, sem complicar.'}
   'kokoro:noah'{'Oi, eu sou o Noah. Pode contar comigo. Vamos pensar no proximo passo juntos.'}
   'kokoro:atlas'{'Ola. Estou a disposicao. Diga o que precisa e vamos organizar os proximos passos.'}
   default{'Oi. Estou aqui com voce. Podemos conversar com calma, no seu tempo.'}
  };Say $sample
 }})
 $dialog.FindName('ApplyAudio').Add_Click({
  try{
   if($script:task -or $script:loginTask -or $script:transcribeTask -or $script:discordTask -or ($script:mouseTestProcess -and -not $script:mouseTestProcess.HasExited)){$script:micHint.Text='Espere a operacao atual terminar antes de aplicar.';return}
   if($voiceList.SelectedItem){$script:voiceId=$voiceList.SelectedItem.Id}
   if($micList.SelectedItem){$script:micId=[int]$micList.SelectedItem.Id}
   $script:vocabulary=$vocabularyBox.Text.Trim()
   @{Voice=$script:voiceId;Microphone=$script:micId;PresetVersion=1;Vocabulary=$script:vocabulary}|ConvertTo-Json|Set-Content -LiteralPath $audioFile -Encoding UTF8
   $voiceEngine.Stop();$script:speechTask=$null;$script:speechQueue.Clear();$script:streamBuffer='';$script:suppressSpeech=$true;$script:state='Idle';Restart-Listener
   Update-CoveShortcutLabels;Update-Capture
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
   $settingsTimer.Stop();$dialog.UpdateLayout();$dialog.FindName('ColorsExpander').BringIntoView();$dialog.UpdateLayout()
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
 $question=$question.Trim();if(-not $question){return}
 $microphoneRequest=Get-CoveMicrophoneRequest $question
 if($microphoneRequest.Handled){
  Set-CoveMicrophonePaused $microphoneRequest.Paused
  $notice=if($script:muted){'Microfone pausado somente no Cove. Para retomar, use o botao ou seu atalho de teclado.'}else{'Microfone reativado no Cove.'}
  Add-Message 'Voce' $question;Add-Message 'Cove' $notice
  if(-not $script:task -and -not $script:discordTask -and -not $script:speechTask){Say $notice}
  Update-Capture;return
 }
 if($script:task -or $script:loginTask -or $script:transcribeTask -or $script:discordTask -or ($script:mouseTestProcess -and -not $script:mouseTestProcess.HasExited)){return}
 $script:speechQueue.Clear();$script:streamBuffer='';$script:streamActive=$false;$script:streamHadText=$false;$script:suppressSpeech=$false;$script:streamSpeechStarted=$false
 $script:messagePlanPending=$false
 $script:semanticRoutePending=$false
 $script:blockedChatSendClaim=$false
 if($script:account){$discard='';while($script:account.TextDeltas.TryDequeue([ref]$discard)){}}
 $displayQuestion=$question;$confirmed=$false
 if($script:pendingMessageText -and [datetime]::Now -lt $script:pendingMessageUntil){
  $reply=ConvertTo-CoveAppName $question
  if($reply -in @('sim','isso','isso mesmo','pode','pode mandar','pode enviar','manda','envia','confirmo')){$question=$script:pendingMessageText;$confirmed=$true}
  elseif($reply -in @('nao','cancela','cancelar','deixa pra la')){$script:pendingMessageText='';$script:listenAfterSpeech=$false;Add-Message 'Voce' $displayQuestion;Add-Message 'Cove' 'Envio cancelado.';Say 'Envio cancelado.';return}
 }
 $script:pendingMessageText=''
 if($script:pendingAppName -and [datetime]::Now -lt $script:pendingAppUntil){
  $reply=ConvertTo-CoveAppName $question
  if($reply -in @('sim','isso','isso mesmo','sim pode abrir','pode abrir','confirmo','confirma')){$question='abra '+$script:pendingAppName;$confirmed=$true}
  elseif($reply -in @('nao','cancela','cancelar','nao obrigado','nao abre','nao pode cancelar')){
   $script:pendingAppName='';$script:listenAfterSpeech=$false;$script:resumeListeningAt=[datetime]::MinValue
   Add-Message 'Voce' $displayQuestion;Add-Message 'Cove' 'Cancelado. Nao vou abrir o aplicativo.';Say 'Cancelado.';return
  }
 }
 $script:pendingAppName='';$script:listenAfterSpeech=$false;$script:resumeListeningAt=[datetime]::MinValue
 $messageStatus=Get-CoveMessageStatusRequest $question
 if($messageStatus.Handled){Write-CoveActionTrace 'message-status' 'handled';Add-Message 'Voce' $displayQuestion;Add-Message 'Cove' $messageStatus.Message;Add-CoveHistoryEntry 'user' $displayQuestion;Add-CoveHistoryEntry 'assistant' $messageStatus.Message;Say $messageStatus.Message;Update-Capture;return}
 $messagePreview=Invoke-CoveMessageRequest $question -DryRun
 $unparsedMessage=(-not $messagePreview.Handled) -and (Test-CoveUnparsedMessageIntent $question)
 $discordPreview=if($messagePreview.Handled){$messagePreview}elseif($unparsedMessage){[pscustomobject]@{Handled=$false}}else{Invoke-CoveDiscordRequest $question -DryRun}
 $controlPreview=if($discordPreview.Handled){$discordPreview}elseif($unparsedMessage){[pscustomobject]@{Handled=$false}}else{Invoke-CoveComputerRequest $question -DryRun}
 Write-CoveActionTrace $(if($messagePreview.Handled){'local-message'}elseif($unparsedMessage){'planned-message'}elseif($discordPreview.Handled){'discord'}else{'other'}) 'recognized'
 if($controlPreview.Handled -and $FromVoice -and $Confidence -lt 0.72 -and -not $confirmed){
  if($messagePreview.Handled){Add-Message 'Voce' $displayQuestion;Request-CoveMessageConfirmation $question;return}
  if($discordPreview.Handled){$script:listenAfterSpeech=$true}
  if($messagePreview.Handled){Set-CoveMessageState $messagePreview 'failed' 'Nao entendi o pedido com clareza. Nada foi enviado.'}
  Add-Message 'Voce' $displayQuestion;Say 'Nao entendi esse comando com clareza. Repita ou digite o pedido.';Update-Capture;return
 }
 if($discordPreview.Handled){
  # Release the brief foreground hint before activating another application.
  if($script:foregroundPulse){$script:foregroundPulse.Stop()};if($chat){$chat.Topmost=$false}
  $script:discordCancel=New-Object Threading.CancellationTokenSource
  try{$localAction=if($messagePreview.Handled){Invoke-CoveMessageRequest $question -DryRun:$SmokeTest}else{Invoke-CoveDiscordRequest $question -DryRun:$SmokeTest}}catch{if($messagePreview.Handled){Set-CoveMessageState $messagePreview 'failed' $_.Exception.GetBaseException().Message};$script:discordCancel.Dispose();$script:discordCancel=$null;Add-Message 'Cove' $_.Exception.GetBaseException().Message;return}
  if(-not $localAction.Task){$script:discordCancel.Dispose();$script:discordCancel=$null}
 }else{$localAction=if($unparsedMessage){[pscustomobject]@{Handled=$false}}elseif($controlPreview.Handled){Invoke-CoveComputerRequest $question -DryRun:$SmokeTest}else{Invoke-CoveFileRequest $question -DryRun:$SmokeTest}}
 if(-not $localAction.Handled -and -not $unparsedMessage){$localAction=Invoke-CoveOnlineRequest $question -DryRun:$SmokeTest}
 if(-not $localAction.Handled -and -not $unparsedMessage){$localAction=Invoke-CoveAppRequest $question -DryRun:$SmokeTest -RequireConfirmation:$false}
 if($localAction.Handled){
  $voiceEngine.Stop();$script:speechTask=$null;$script:listenUntil=[datetime]::MinValue;$script:state='Idle'
  if($localAction.NeedsConfirmation){$script:pendingAppName=$localAction.AppName;$script:pendingAppUntil=[datetime]::Now.AddSeconds(90);$script:listenAfterSpeech=$true}
  if($localAction.AwaitReply){$script:listenAfterSpeech=$true}
  if($localAction.NeedsCallLink){$script:pendingLinkTarget=[pscustomobject]@{Server=$localAction.Server;Channel=$localAction.Channel}}
  Add-Message 'Voce' $displayQuestion;Add-Message 'Cove' $localAction.Message
  Add-CoveHistoryEntry 'user' $question
  if(-not $localAction.Task){$historyResult=if($localAction.LocalOnly){'Consulta local de arquivo ou pasta concluida. O conteudo permanece somente no computador.'}else{$localAction.Message};Add-CoveHistoryEntry 'assistant' $historyResult}
  if($messagePreview.Handled){Set-CoveMessageState $localAction $(if($localAction.Task){'running'}else{'awaiting-data'}) $localAction.Message}
  if($localAction.Task){$script:localTaskIsMessage=$messagePreview.Handled;$script:discordTask=$localAction.Task;$script:state='Thinking';$sendButton.IsEnabled=$false;Update-Capture;return}
  Say $localAction.Message
  if($script:listenAfterSpeech -and $script:state -ne 'Speaking'){$script:resumeListeningAt=[datetime]::Now.AddMilliseconds(400);$script:listenAfterSpeech=$false}
  Update-Capture;return
 }
 $messageIntent=Test-CoveUnparsedMessageIntent $question
 if($messageIntent -and $FromVoice -and $Confidence -lt 0.72 -and -not $confirmed){Add-Message 'Voce' $displayQuestion;Request-CoveMessageConfirmation $question;return}
 if($script:mode -eq 'chatgpt' -and (-not $script:account -or -not $script:account.Connected)){$script:state='Idle';$chat.Show();Add-Message 'Cove' 'Entre em Ajustes > Continuar com ChatGPT para conectar sua conta.';Show-Settings;return}
 if($script:mode -eq 'api' -and -not $script:key){$script:state='Idle';$chat.Show();Add-Message 'Cove' 'Cadastre uma chave em Ajustes ou escolha Continuar com ChatGPT.';Show-Settings;return}
 try{
  $voiceEngine.Stop();$script:speechTask=$null
  $script:state='Thinking';$script:listenUntil=[datetime]::MinValue;Update-Capture
  Add-Message 'Voce' $question;$script:pendingQuestion=$question
  $messages=@($script:history)+@(@{role='user';content=$question})
  $body=@{model='gpt-4.1-mini';instructions='Voce e NOME_CONFIGURADO_COVE, um assistente de voz amigavel. Converse em portugues brasileiro natural, sem markdown. Responda ao pedido diretamente: nao pergunte se pode fazer, explicar ou continuar algo que o usuario ja pediu. Para detalhes secundarios, escolha uma opcao razoavel e siga. Pergunte apenas por dados indispensaveis ausentes, destino ambiguo ou fala realmente incerta. Aproveite o contexto sem pedir os mesmos dados outra vez. Comece pela informacao util, sem preambulos. Seja breve em pedidos simples e desenvolva com exemplos e detalhes quando a complexidade ou o pedido exigir; nao corte explicacoes para parecer rapido. Use o contexto recente e os resultados locais registrados na conversa. Nao obrigue a pessoa a repetir contato, aplicativo ou mensagem que ja informou. Nao repita avisos genericos de falta de confirmacao; descreva o resultado local conhecido, sem inventar sucesso. Use o nome configurado ao se apresentar. Voce e a conversa de um aplicativo independente. O Cove encontra apps e jogos no menu Iniciar, atalhos, bibliotecas instaladas Steam e Epic e executaveis cadastrados, e pode abri-los com abre NOME. Tambem envia mensagens privadas no WhatsApp Desktop, WhatsApp Web no Chrome e Discord por pedidos locais: mande mensagem para CONTATO no APLICATIVO dizendo TEXTO. Pode receber o texto, contato e aplicativo numa frase; se faltar algo, pergunta apenas esse dado. Nunca afirme envio ou entrega por escrever uma resposta; o envio usa a interface local e informa o resultado. Para entrar em calls, aceita servidor e canal numa frase e procura nas listas do Discord. Pergunta apenas nomes ausentes. Tambem inicia chamadas privadas por voz com liga para NOME no Discord ou entra na call com NOME. A pessoa precisa atender; nao prometa conexao antes de confirmar. A call padrao pode ser salva com configurar call NOME com link LINK-DO-CANAL. Essa automacao usa a interface do Discord Desktop e informa quando nao consegue confirmar a conexao. Esses comandos sao tratados pelo aplicativo, fora desta conversa. Horario e data usam o relogio do Windows; noticias recentes usam BBC News Brasil; temperatura usa Open-Meteo, com cidade configuravel nos Ajustes. Pedidos de pesquisar abrem uma busca no Chrome. Nao invente dados atuais quando nao forem retornados por esses comandos locais. Aceite pedidos em linguagem natural. Nao exija uma frase exata, nao apresente roteiro de comandos nem mande a pessoa repetir uma sequencia fixa. Se faltar um destino, pergunte apenas essa informacao. Os comandos locais de apps e calls sao reconhecidos pelo aplicativo; nao afirme que executou uma acao so por escrever a resposta. O aplicativo tambem aceita comandos locais: liste os discos; listar pasta Documentos; abrir pasta Downloads; leia arquivo seguido de um caminho local completo. Pode listar e abrir pastas em qualquer disco permitido pelo Windows e ler arquivos txt, md, csv, json e log. O aplicativo tambem controla mouse, teclado e janelas e pode criar, editar, mover e excluir arquivos por comandos locais explicitos. Diga comandos do computador para conhecer a sintaxe. Primeiro use focar janela e o titulo do aplicativo antes de digitar, clicar ou enviar teclas. Edicoes de texto preservam uma copia e exclusoes de arquivos usam a Lixeira. O acesso usa as permissoes da conta Windows. O conteudo lido nesses comandos fica local e nao e enviado a esta conversa. Voce nao executa acoes pelo texto da resposta nem ve arquivos ou tela. Nao finja executar acoes. Quando nao souber, diga com clareza.'.Replace('NOME_CONFIGURADO_COVE',$script:assistantName);input=$messages;max_output_tokens=1400;store=$false}|ConvertTo-Json -Depth 12 -Compress
  $script:cancel=New-Object Threading.CancellationTokenSource
  $script:messagePlanPending=$messageIntent
  if($messageIntent){Set-CoveMessageState $null 'planning'}
  if($messageIntent){$body=@{model='gpt-4.1-mini';instructions=(Get-CoveMessagePlannerInstructions);input=@(@{role='user';content=(Get-CoveMessagePlannerInput $question)});max_output_tokens=700;store=$false}|ConvertTo-Json -Depth 8 -Compress}
  elseif(-not (Test-CoveDirectConversation $question)){$body=New-CoveSemanticRequest $body $question;$script:semanticRoutePending=$true}
  if($script:mode -eq 'chatgpt'){$script:streamActive=-not ($messageIntent -or $script:semanticRoutePending);$script:task=$script:account.Ask($body,$script:cancel.Token)}else{$script:task=[CoveApp.Brain]::Ask($script:key,$body,$script:cancel.Token)}
  $sendButton.IsEnabled=$false
 }catch{if($messageIntent){Set-CoveMessageState $null 'failed' 'Nao foi possivel interpretar o pedido. Nada foi enviado.'};$script:state='Idle';Add-Message 'Cove' 'Nao foi possivel iniciar a pergunta. Confira a configuracao.';Update-Capture}
}
function Show-CoveDiscordSettings {
 Show-CoveConversation
 Show-Settings -Discord
}
function Show-CoveConversation {
 $chat.WindowState='Normal';$chat.ShowActivated=$true;$chat.ShowInTaskbar=$true
 $area=[Windows.SystemParameters]::WorkArea
 $chat.WindowStartupLocation='Manual'
 $chat.Left=$area.Left+[Math]::Max(0,($area.Width-$chat.Width)/2)
 $chat.Top=$area.Top+[Math]::Max(0,($area.Height-$chat.Height)/2)
 $chat.Show();$chat.Topmost=$true
 $chat.Activate()|Out-Null
 if($script:foregroundPulse){$script:foregroundPulse.Stop()}
 $script:foregroundPulse=New-Object Windows.Threading.DispatcherTimer
 $script:foregroundPulse.Interval=[TimeSpan]::FromSeconds(12)
 $script:foregroundPulse.Add_Tick({$script:foregroundPulse.Stop();$chat.Topmost=$false})
 $script:foregroundPulse.Start()
 $promptBox.Focus()|Out-Null
}
function Request-CoveReload([switch]$SelfRestart){
 try{Save-CoveReloadState $PSScriptRoot $transcript.Text @($script:history) -MessageSession (Get-CoveMessageSession)}catch{}
 $script:selfRestart=[bool]$SelfRestart
 $window.Close()
}
function Begin-Listening([switch]$FromWake) {
 if($script:task -or $script:transcribeTask -or $script:discordTask -or ($script:mouseTestProcess -and -not $script:mouseTestProcess.HasExited)){return}
 if(-not $script:listener -or -not $script:listener.Ready){$chat.Show();Add-Message 'Cove' 'A escuta ainda nao esta disponivel. Voce pode digitar sua pergunta aqui.';return}
 if($script:muted){return}
 $voiceEngine.Stop();$script:speechTask=$null
 $script:listener.ReplayWakeAudio=[bool]$FromWake
 $script:state='Listening';$script:listenUntil=[datetime]::Now.AddSeconds(12);$script:cooldown=[datetime]::MinValue;Update-Capture
}
function Show-CoveOnCall([switch]$Listen){
 $window.WindowState='Normal';$window.Show()
 $window.Topmost=$true;$window.Topmost=$false;$window.Activate()|Out-Null
 if($Listen){
  if($script:muted){Show-CoveConversation;return}
  if($script:listener -and $script:listener.Ready){Begin-Listening}
  else{$script:resumeListeningAt=[datetime]::Now.AddMilliseconds(500)}
 }
}
function Set-CoveMicrophonePaused([bool]$Paused) {
 $script:muted=$Paused;$script:listenUntil=[datetime]::MinValue
 $script:resumeListeningAt=[datetime]::MinValue;$script:listenAfterSpeech=$false
 if($script:muted -and $script:transcribeTask){$transcriber.Stop();$script:transcribeTask=$null;$script:state='Idle';$sendButton.IsEnabled=$true}
 if($script:state -eq 'Listening'){$script:state='Idle'}
 if($script:muted){$muteButton.Content='Retomar microfone'}else{$muteButton.Content='Pausar microfone'}
 Update-CoveShortcutLabels
 Update-Capture
}
function Toggle-Microphone {Set-CoveMicrophonePaused (-not $script:muted)}
function Update-CoveShortcutLabels {
 $microphoneHint=if($script:shortcuts -and $script:shortcuts.Microphone){' ('+$script:shortcuts.Microphone+')'}else{''}
 $clearHint=if($script:shortcuts -and $script:shortcuts.ClearConversation){' ('+$script:shortcuts.ClearConversation+')'}else{''}
 $muteButton.ToolTip='Pausar ou retomar somente a escuta do Cove'+$microphoneHint
 if($chat){$chat.FindName('Clear').ToolTip='Limpar conversa'+$clearHint}
 if($heardLabel){$heardLabel.Text=if($script:muted){'Microfone pausado no Cove. Use Retomar microfone'+$microphoneHint+'.'}else{'Diga '+$script:assistantName+' para conversar.'}}
}
function Clear-CoveConversation {
 if($script:task -or $script:discordTask -or $script:transcribeTask){return $false}
 $voiceEngine.Stop();$script:speechTask=$null;$script:speechQueue.Clear();$script:streamBuffer='';$script:state='Idle'
 $script:history=@();$script:messageDialog=$null;$script:messageContext=$null;$script:lastMessageState=$null
 $script:onlineCityUntil=[datetime]::MinValue;$script:pendingLinkTarget=$null
 $script:streamActive=$false;$script:streamHadText=$false;$script:suppressSpeech=$true
 $script:discordDialog=$null;$script:lastConversationalAnswer=$null;$script:pendingMessageText='';$script:pendingAppName='';$script:pendingQuestion=''
 $script:listenAfterSpeech=$false;$script:resumeListeningAt=[datetime]::MinValue
 $transcript.Clear();Update-Capture
 return $true
}
$script:shortcuts=Get-CoveShortcutSettings
Update-CoveShortcutLabels
$microphoneKeyHandler=[Windows.Input.KeyEventHandler]{param($sender,$eventArgs)
 $key=$eventArgs.Key;if($key -eq [Windows.Input.Key]::System){$key=$eventArgs.SystemKey}
 $action=Get-CoveShortcutAction $script:shortcuts $key ([Windows.Input.Keyboard]::Modifiers)
 if(-not $action){return};$eventArgs.Handled=$true;if($eventArgs.IsRepeat){return}
 if($action -eq 'Microphone'){Toggle-Microphone}elseif(-not (Clear-CoveConversation)){$heardLabel.Text='Aguarde a tarefa terminar para limpar a conversa.'}
}
$chat.Add_PreviewKeyDown($microphoneKeyHandler);$window.Add_PreviewKeyDown($microphoneKeyHandler)
$openChat.Add_Click({Show-CoveConversation})
$orb.Add_Click({if($script:state -eq 'Speaking'){$script:suppressSpeech=$true;$script:speechQueue.Clear();$script:streamBuffer='';$voiceEngine.Stop();$script:speechTask=$null;$script:state='Idle';$script:cooldown=[datetime]::Now.AddMilliseconds(450)}elseif($script:state -eq 'Transcribing'){$transcriber.Stop();$script:transcribeTask=$null;$script:state='Idle';$sendButton.IsEnabled=$true;Begin-Listening}else{Begin-Listening}})
$sendButton.Add_Click({$q=$promptBox.Text;$promptBox.Clear();Ask-Cove $q})
$promptBox.Add_KeyDown({param($sender,$eventArgs) if($eventArgs.Key -eq 'Return' -and $sendButton.IsEnabled){$q=$promptBox.Text;$promptBox.Clear();Ask-Cove $q;$eventArgs.Handled=$true}})
$chat.FindName('Configure').Add_Click({Show-Settings})
$chat.FindName('Apps').Add_Click({Show-CoveApplications})
$chat.FindName('DiscordSettings').Add_Click({Show-CoveDiscordSettings})
$muteButton.Add_Click({Toggle-Microphone})
$chat.FindName('Clear').Add_Click({$null=Clear-CoveConversation})
$menu=New-Object Windows.Controls.ContextMenu
foreach($label in @('Pausar / retomar microfone','Conversa','Discord e mouse','Reiniciar / atualizar','Sair')){$item=New-Object Windows.Controls.MenuItem;$item.Header=$label;$menu.Items.Add($item)|Out-Null}
$menu.Items[0].Add_Click({Toggle-Microphone});$menu.Items[1].Add_Click({$chat.Show()});$menu.Items[2].Add_Click({Show-CoveDiscordSettings});$menu.Items[3].Add_Click({Request-CoveReload -SelfRestart});$menu.Items[4].Add_Click({$window.Close()});$orb.ContextMenu=$menu
$assets=Join-Path $PSScriptRoot 'assets'
$modelReady=(Test-Path -LiteralPath (Join-Path $assets 'vosk-model-small-pt-0.3\final.mdl')) -or (Test-Path -LiteralPath (Join-Path $assets 'vosk-model-small-pt-0.3\am\final.mdl'))
if(-not $SmokeTest -and (Test-Path -LiteralPath (Join-Path $assets 'native\libvosk.dll')) -and $modelReady){
 Restart-Listener
}elseif(-not $SmokeTest){Add-Message 'Cove' 'Para ativar o microfone local, execute Preparar-Cove.cmd. Enquanto isso, voce pode digitar.'}
if(-not $SmokeTest){$script:warmTasks=@($voiceEngine.WarmUp(),$transcriber.WarmUp())}
if(-not $SmokeTest){$restored=Read-CoveReloadState $PSScriptRoot;if($restored){$transcript.Text=[string]$restored.Transcript;$script:history=@($restored.History|Select-Object -Last 16);Restore-CoveMessageSession $restored.MessageSession}}
Add-Message 'Cove' 'Oi! Diga meu nome ou escreva aqui. Estou por perto.'
if($script:mode -eq 'chatgpt' -and (-not $script:account -or -not $script:account.Connected)){Add-Message 'Cove' 'Para conectar sua conta, abra Ajustes e escolha Continuar com ChatGPT.'}
if($script:lastAccountStartupError){Add-Message 'Cove' 'Nao consegui abrir a conexao protegida da conta neste inicio. Seus dados foram mantidos. Confira a conexao em Ajustes.'}
$script:pulse=0
# Reuse frozen brushes and update visual properties only when they change.
$script:orbBrushes=@{}
$clearConversationButton=$chat.FindName('Clear')
$timer=New-Object Windows.Threading.DispatcherTimer
$timer.Interval=[TimeSpan]::FromMilliseconds(80)
$timer.Add_Tick({
 $script:pulse+=0.16
 try{
  if($instanceChannel){
   if($instanceChannel.Reload.WaitOne(0)){Request-CoveReload;return}
   if($instanceChannel.DiscordSettings.WaitOne(0)){Show-CoveDiscordSettings}
   if($instanceChannel.Listen.WaitOne(0)){Show-CoveOnCall -Listen}
   elseif($instanceChannel.Show.WaitOne(0)){Show-CoveConversation}
  }
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
     $question=[regex]::Replace($spokenText,('(?i)^\s*(?:oi[, ]+)?'+$script:assistantWakePattern+'[ ,.!?:]*'),'').Trim()
     if($question){$certainty=1.0;if($recognized.uncertain){$certainty=0.6};Ask-Cove $question -FromVoice -Confidence $certainty}
     else{Begin-Listening}
    }else{$heardLabel.Text='Nao identifiquei uma frase. Clique na bolinha para tentar de novo.'}
   }catch{if(-not $finishedTranscription.IsCanceled){Add-Message 'Cove' $_.Exception.GetBaseException().Message;$heardLabel.Text='Nao consegui entender. Clique na bolinha para repetir.'}}
  }
  if($script:voiceSetup -and $script:voiceSetup.HasExited){
   if($script:voiceSetup.ExitCode -eq 0 -and $voiceEngine.Installed){$setupMessage='As seis vozes estao prontas. Escolha uma voz e clique em Ouvir esta voz.'}else{$setupMessage='A preparacao das vozes falhou. Abra Preparar-Vozes.cmd para ver a mensagem e tentar novamente.'}
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
  if($script:discordTask -and $script:discordTask.IsCompleted){
   try{$discordAnswer=$script:discordTask.GetAwaiter().GetResult();if([string]::IsNullOrWhiteSpace($discordAnswer)){throw 'O controlador terminou sem informar o resultado. Confira a conversa antes de repetir o envio.'};if($script:localTaskIsMessage){Set-CoveMessageState $script:lastMessageState $(if($discordAnswer -like 'Mensagem enviada para *'){'sent'}else{'observed'}) $discordAnswer};Add-CoveHistoryEntry 'assistant' $discordAnswer;Add-Message 'Cove' $discordAnswer;Say $discordAnswer}
   catch{$script:state='Idle';$discordError=$_.Exception.GetBaseException().Message;if([string]::IsNullOrWhiteSpace($discordError)){$discordError='O controle do aplicativo falhou antes de concluir a acao.'};if($script:localTaskIsMessage){Set-CoveMessageState $script:lastMessageState 'failed' $discordError};Add-CoveHistoryEntry 'assistant' ('Resultado local: '+$discordError);Add-Message 'Cove' $discordError;Say $discordError}
   finally{$script:discordTask=$null;$script:localTaskIsMessage=$false;if($script:discordCancel){$script:discordCancel.Dispose();$script:discordCancel=$null};$sendButton.IsEnabled=$true}
  }
  if($script:streamActive){Update-StreamSpeech}
  if($script:task -and $script:task.IsCompleted){
   try{
    $answer=$script:task.GetAwaiter().GetResult()
    if($script:semanticRoutePending){$semantic=ConvertFrom-CoveSemanticResponse $answer;$answer=$semantic.Text;$script:messagePlanPending=$semantic.IsMessage}
    if($script:messagePlanPending){
     if($script:foregroundPulse){$script:foregroundPulse.Stop()};if($chat){$chat.Topmost=$false}
     $localPlan=Invoke-CoveMessagePlanResponse $answer -OriginalRequest $script:pendingQuestion -DryRun:$SmokeTest
     Add-CoveHistoryEntry 'user' $script:pendingQuestion
     if(-not $localPlan.Task){Add-CoveHistoryEntry 'assistant' $localPlan.Message}
     Set-CoveMessageState $localPlan $(if($localPlan.Task){'running'}else{'awaiting-data'}) $localPlan.Message
     Write-CoveActionTrace 'planned-message' $(if($localPlan.Task){'controller-started'}else{'awaiting-data'})
     Add-Message 'Cove' $localPlan.Message
     if($localPlan.Task){$script:localTaskIsMessage=$true;$script:discordTask=$localPlan.Task;$script:state='Thinking';$sendButton.IsEnabled=$false}
     else{if($script:discordCancel){$script:discordCancel.Dispose();$script:discordCancel=$null};$script:listenAfterSpeech=$localPlan.AwaitReply;Say $localPlan.Message}
    }else{
    if(Test-CoveUnverifiedSendClaim $answer){$answer=Get-CoveUnverifiedSendNotice;$script:blockedChatSendClaim=$true}
    if(-not $script:blockedChatSendClaim){$script:lastConversationalAnswer=[pscustomobject]@{Text=$answer;Until=[datetime]::Now.AddMinutes(20)}}
    $script:history=@($script:history)+@(@{role='user';content=$script:pendingQuestion},@{role='assistant';content=$answer})
    if($script:history.Count -gt 24){$script:history=@($script:history|Select-Object -Last 24)}
    Add-Message 'Cove' $answer
    if($script:blockedChatSendClaim){$script:speechQueue.Clear();$script:streamBuffer='';Say $answer}
    elseif($script:streamActive){Update-StreamSpeech -Finish;if(-not $script:streamHadText -and -not $script:suppressSpeech){$script:speechQueue.Enqueue($answer)}}else{Say $answer}
    }
   }catch{if($script:messagePlanPending){Set-CoveMessageState $script:lastMessageState 'failed' $_.Exception.GetBaseException().Message};$script:state='Idle';$script:speechQueue.Clear();$script:suppressSpeech=$true;$voiceEngine.Stop();$script:speechTask=$null;Add-Message 'Cove' $_.Exception.GetBaseException().Message;$chat.Show()}
   finally{$script:task=$null;$script:messagePlanPending=$false;$script:streamActive=$false;if(-not $script:speechTask -and -not $script:discordTask){$script:state='Idle'};if($script:cancel){$script:cancel.Dispose();$script:cancel=$null};$sendButton.IsEnabled=-not [bool]$script:discordTask}
  }
  if($script:speechTask -and $script:speechTask.IsCompleted){
   try{$script:speechTask.GetAwaiter().GetResult()|Out-Null}catch{if(-not $script:speechTask.IsCanceled){$voiceError=$_.Exception.GetBaseException().Message;Add-Message 'Cove' $voiceError;if($script:voiceHint){$script:voiceHint.Text=$voiceError}}}
   $script:speechTask=$null;if($script:state -eq 'Speaking'){$script:state=if($script:task){'Thinking'}else{'Idle'};$script:cooldown=[datetime]::Now.AddMilliseconds(450)}
   if($script:listenAfterSpeech){$followDelay=if($script:discordDialog -or $script:messageDialog -or $script:pendingMessageText){350}else{1000};$script:resumeListeningAt=[datetime]::Now.AddMilliseconds($followDelay);$script:listenAfterSpeech=$false}
  }
  if(-not $script:speechTask -and $script:speechQueue.Count -gt 0 -and -not $script:suppressSpeech){Say ($script:speechQueue.Dequeue())}
  if($script:warmTasks.Count){
   $remainingWarm=@();foreach($warm in $script:warmTasks){if($warm.IsCompleted){try{$warm.GetAwaiter().GetResult()|Out-Null}catch{}}else{$remainingWarm+=@($warm)}};$script:warmTasks=$remainingWarm
  }
  if($script:resumeListeningAt -ne [datetime]::MinValue -and [datetime]::Now -ge $script:resumeListeningAt){
   if($script:listener -and -not $script:listener.Ready -and -not $script:lastError){$script:resumeListeningAt=[datetime]::Now.AddMilliseconds(500)}
   else{$script:resumeListeningAt=[datetime]::MinValue;Begin-Listening}
  }
  if($script:pendingAppName -and [datetime]::Now -gt $script:pendingAppUntil){$script:pendingAppName=''}
  if($script:discordDialog -and [datetime]::Now -ge $script:discordDialog.Until){$script:discordDialog=$null}
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
    if($ev -eq 'WAKE'){$script:lastHeard=('Nome reconhecido: '+$script:assistantName);$status.ToolTip='Nome reconhecido. Pode fazer sua pergunta.';$heardLabel.Text='Estou ouvindo. Pode fazer sua pergunta.';Begin-Listening -FromWake;continue}
    $text='';$final=$false;$confidence=1.0
    if($ev.StartsWith('FINAL:')){
     $recognition=$ev.Substring(6)|ConvertFrom-Json;$text=$recognition.text;$final=$true
     if($recognition.result){$confidence=[double](($recognition.result|Measure-Object -Property conf -Average).Average)}
    }
    elseif($ev.StartsWith('PARTIAL:')){$text=($ev.Substring(8)|ConvertFrom-Json).partial}
    if(-not $text){continue}
    $script:lastHeard='Ouvi: '+$text;$status.ToolTip=$script:lastHeard;$heardLabel.Text=$script:lastHeard
    $hasWake=$text -match ('(?i)'+$script:assistantWakePattern)
    if($script:state -eq 'Idle' -and $hasWake){Begin-Listening}
    if($script:state -eq 'Listening'){
     if(-not $final){$script:listenUntil=[datetime]::Now.AddSeconds(12)}
     if($final){$question=[regex]::Replace($text,('(?i)^.*?'+$script:assistantWakePattern+'[ ,.!?]*'),'').Trim();if($question -and $question -notmatch '^(oi|ola)$'){Ask-Cove $question -FromVoice -Confidence $confidence}}
    }
   }
  }
  if($script:state -eq 'Listening' -and [datetime]::Now -gt $script:listenUntil){$script:state='Idle'}
  switch($script:state){
   'Listening'{$color='#176C66';$label='Ouvindo...'}
   'Thinking'{$color='#485A92';$label='Pensando...'}
   'Transcribing'{$color='#31667A';$label='Entendendo sua fala...'}
   'Speaking'{$color='#6051A0';$label='Respondendo'}
   default{
    $color='#345F95'
    if($script:loginTask){$label='Conectando ChatGPT...'}
    elseif($script:muted){$label='Microfone pausado';$color='#4D5664'}
    elseif($script:listener -and $script:listener.Ready){$label='Diga '+$script:assistantName}
    elseif($script:listener -and -not $script:lastError){$label='Preparando a escuta...'}
    else{$label='Microfone indisponivel'}
   }
  }
  if(-not $script:muted){$color=switch($script:state){'Listening'{$script:appearance.Palette.Listening};'Thinking'{$script:appearance.Palette.Thinking};'Transcribing'{$script:appearance.Palette.Thinking};'Speaking'{$script:appearance.Palette.Speaking};default{$script:appearance.Palette.Idle}}}
  if(-not $script:orbBrushes.ContainsKey($color)){
   $brush=New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($color))
   $brush.Freeze();$script:orbBrushes[$color]=$brush
  }
  if($orb.Background -ne $script:orbBrushes[$color]){$orb.Background=$script:orbBrushes[$color]}
  if($status.Text -ne $label){$status.Text=$label}
  $canClear=-not ($script:task -or $script:discordTask -or $script:transcribeTask)
  if($clearConversationButton.IsEnabled -ne $canClear){$clearConversationButton.IsEnabled=$canClear}
  $animationMode=if($script:muted){'Paused'}elseif($script:state -in @('Thinking','Transcribing')){'Thinking'}else{$script:state}
  if($orb.Tag -ne $animationMode){$orb.Tag=$animationMode}
  $targetBlur=24
  if($script:state -eq 'Listening' -and $script:listener){$targetBlur=24+12*$script:listener.Level}
  # Smooth microphone jitter and avoid invalidating the effect for tiny changes.
  $smoothBlur=$glow.BlurRadius+0.35*($targetBlur-$glow.BlurRadius)
  if([Math]::Abs($smoothBlur-$glow.BlurRadius) -ge 0.15){$glow.BlurRadius=$smoothBlur}
  $glowColor=$script:orbBrushes[$color].Color
  if($glow.Color -ne $glowColor){$glow.Color=$glowColor}
 }catch{$script:state='Idle';Add-Message 'Cove' 'Ocorreu um erro na escuta. Reinicie o Cove ou digite sua pergunta.'}
})
$window.Add_Closed({
 $timer.Stop();$script:quitting=$true
 if($script:mouseTestTimer){$script:mouseTestTimer.Stop()}
 if($script:mouseTestProcess){try{if(-not $script:mouseTestProcess.HasExited){$script:mouseTestProcess.Kill();$script:mouseTestProcess.WaitForExit(2000)|Out-Null}}catch{}finally{$script:mouseTestProcess.Dispose();$script:mouseTestProcess=$null}}
 if($script:discordCancel){$script:discordCancel.Cancel()}
 if($script:cancel){$script:cancel.Cancel();$script:cancel.Dispose()}
 if($script:loginCancel){$script:loginCancel.Cancel();$script:loginCancel.Dispose()}
 if($script:listener){$script:listener.Dispose()}
 $transcriber.Dispose()
 try{$voiceEngine.Dispose()}catch{}
 if($script:account){try{$script:account.Dispose()}catch{}}
 $script:key='';$script:history=@();$chat.Close()
 if(-not $SmokeTest){try{$runtimeFile=Join-Path $PSScriptRoot 'cove-runtime.json';$runtime=Get-Content -LiteralPath $runtimeFile -Raw|ConvertFrom-Json;if($runtime.Pid -eq $PID){Remove-Item -LiteralPath $runtimeFile}}catch{}}
 Close-CoveInstanceChannel $instanceChannel
 if($script:selfRestart){Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'CoveLauncher.ps1')+'" -ShowDiscord') -WindowStyle Hidden}
})
$window.Add_ContentRendered({if($SmokeTest){Show-CoveConversation;'WINDOW_RENDERED_V3'|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'smoke-test.log')}else{Write-CoveRuntime $PSScriptRoot $script:buildId;if($OpenDiscordSettings){Show-CoveDiscordSettings}elseif($ListenOnStart){Show-CoveOnCall -Listen}else{Show-CoveConversation}}})
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
