$ErrorActionPreference='Stop'
. "$PSScriptRoot\CoveApps.ps1"
. "$PSScriptRoot\CoveDiscord.ps1"
Add-Type -Path @("$PSScriptRoot\CoveComputer.cs","$PSScriptRoot\CoveDiscord.cs","$PSScriptRoot\CoveMessaging.cs") -ReferencedAssemblies UIAutomationClient,UIAutomationTypes,WindowsBase,System.Security
foreach($file in @('CoveDiscord.ps1','Cove-Voice.ps1')){
 $tokens=$null;$problems=$null
 [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$problems)|Out-Null
 if($problems.Count){throw ($problems|Out-String)}
}
$original=$script:coveDiscordFile
$testFile=Join-Path $PSScriptRoot ('discord-test-'+[guid]::NewGuid().ToString('N')+'.json')
try{
 $script:coveDiscordFile=$testFile
 foreach($phrase in @('entrar na call do Discord','entra na call','pode entrar em uma call no discord')){
  $r=Invoke-CoveDiscordRequest $phrase -DryRun
  if(-not $r.Handled -or $r.Task -or $r.Message -notlike 'Em qual servidor*'){throw ('Destino ausente: '+$phrase)}
 }
 foreach($phrase in @('nao entre na call','como entrar na call do discord','o site disse entrar na call','sair da call')){
  if((Invoke-CoveDiscordRequest $phrase -DryRun).Handled){throw ('Autorizacao indireta aceita: '+$phrase)}
 }
 $r=Invoke-CoveDiscordRequest 'entrar na call Geral no Discord' -DryRun
 if(-not $r.Handled -or $r.Channel -ne 'Geral' -or $r.Task){throw 'Canal por nome falhou'}
 $r=Invoke-CoveDiscordRequest 'configurar call Geral com link https://discord.com/channels/123456789012345678/234567890123456789' -DryRun
 if(-not $r.Handled -or (Test-Path -LiteralPath $testFile)){throw 'Simulacao salvou configuracao'}
 $r=Invoke-CoveDiscordRequest 'configurar call Geral com link https://discord.com/channels/123456789012345678/234567890123456789'
 $saved=Get-Content -LiteralPath $testFile -Raw|ConvertFrom-Json
 if($saved.Name -cne 'Geral' -or $saved.Url -cne 'discord://-/channels/123456789012345678/234567890123456789'){throw 'Configuracao invalida'}
 $r=Invoke-CoveDiscordRequest 'entrar na call padrao' -DryRun
 if(-not $r.Handled -or $r.Channel -ne 'Geral' -or $r.Task){throw 'Call padrao falhou'}
 foreach($link in @('https://discord.gg/convite','https://outro.site/channels/123456789012345678/234567890123456789','file:///C:/Windows/System32/cmd.exe')){
  $r=Invoke-CoveDiscordRequest ('configurar call Teste com link '+$link)
  if($r.Message -notlike 'Use o link*'){throw 'Link inadequado aceito'}
 }
 foreach($name in @('Entrar na chamada','Join Voice','Join Call')){if(-not [CoveApp.DiscordCall]::IsJoinButton($name)){throw 'Controle de voz rejeitado'}}
 foreach($name in @('Iniciar chamada de voz','Ligar','Enviar','Compartilhar tela','Join server')){if([CoveApp.DiscordCall]::IsJoinButton($name)){throw 'Controle fora do escopo aceito'}}
 if(-not [CoveApp.DiscordCall]::IsVoiceChannel('Geral (voice channel), 2 users','Geral')){throw 'Canal de voz nao reconhecido'}
 if([CoveApp.DiscordCall]::IsVoiceChannel('Geral (text channel)','Geral')){throw 'Canal de texto aceito'}
 if([CoveApp.DiscordCall]::IsVoiceChannel('Geral dois (voice channel)','Geral')){throw 'Outro canal aceito'}
 # The complete spoken dialog is tested without launching Discord.
 $script:discordDialog=$null
 $r=Invoke-CoveDiscordRequest 'entrar na call do Discord' -DryRun
 if($script:discordDialog -or -not $r.AwaitReply){throw 'Previa alterou o dialogo'}
 $r=Invoke-CoveDiscordRequest 'entrar na call do Discord'
 if($script:discordDialog.Stage -ne 'server'){throw 'Nao pediu servidor'}
 $r=Invoke-CoveDiscordRequest 'Amigos'
 if(-not $r.AwaitReply -or $script:discordDialog.Stage -ne 'channel' -or $script:discordDialog.Server -ne 'Amigos'){throw 'Servidor perdido'}
 $r=Invoke-CoveDiscordRequest 'Geral' -DryRun
 if($r.Action -ne 'join' -or $r.Server -ne 'Amigos' -or $r.Channel -ne 'Geral' -or $r.Task){throw 'Resposta curta nao completou destino'}
 $r=Invoke-CoveDiscordRequest 'cancelar'
 if($script:discordDialog -or -not $r.Handled){throw 'Cancelamento falhou'}
 foreach($phrase in @('entrar na call no servidor Amigos','pode entrar na call no servidor Amigos','entrar na call do Discord no servidor Amigos')){
  $r=Get-CoveDiscordRequest $phrase
  if($r.Server -ne 'Amigos' -or $r.Channel -or $r.NextDialog.Stage -ne 'channel'){throw ('Servidor explicito falhou: '+$phrase)}
 }
 $r=Get-CoveDiscordRequest 'entrar na call Geral no servidor Amigos'
 if($r.Server -ne 'Amigos' -or $r.Channel -ne 'Geral' -or $r.Action -ne 'join'){throw 'Destino em uma frase falhou'}
 $r=Get-CoveDiscordRequest 'entrar na call Geral'
 if($r.NextDialog.Stage -ne 'server' -or $r.NextDialog.Channel -ne 'Geral'){throw 'Canal deve ser lembrado ao perguntar servidor'}
 $r=Get-CoveDiscordRequest 'Amigos' $r.NextDialog
 if($r.Action -ne 'join' -or $r.Channel -ne 'Geral'){throw 'Servidor nao completou destino'}
 $expired=[pscustomobject]@{Stage='channel';Server='Amigos';Channel='';Until=[datetime]::Now.AddSeconds(-1)}
 if((Get-CoveDiscordRequest 'Geral' $expired).Handled){throw 'Dialogo expirado ainda ativo'}
 $waiting=[pscustomobject]@{Stage='channel';Server='Amigos';Channel='';Until=[datetime]::Now.AddSeconds(60)}
 if((Get-CoveDiscordRequest 'abre o Spotify' $waiting).Handled){throw 'Outro comando foi capturado como nome'}
 if(-not [CoveApp.DiscordCall]::DestinationMatches('Geral',@('Geral','Amigos'),'Amigos','Geral',$false)){throw 'Destino correto rejeitado'}
 if([CoveApp.DiscordCall]::DestinationMatches('Geral',@('Geral','Outro servidor'),'Amigos','Geral',$false)){throw 'Call de outro servidor aceita'}
 if([CoveApp.DiscordCall]::DestinationMatches('Geral dois',@('Geral dois','Amigos'),'Amigos','Geral',$false)){throw 'Canal parecido aceito'}
 if(-not [CoveApp.DiscordCall]::DestinationMatches('Amigos, servidor',@(),'Amigos','',$true)){throw 'Busca de servidor falhou'}
 if([CoveApp.DiscordCall]::DestinationMatches('Amigos dois',@(),'Amigos','',$true)){throw 'Servidor parecido aceito'}
 if([CoveApp.DiscordCall]::DestinationMatches('Geral',@('Geral'),'Geral','Geral',$false)){throw 'Servidor igual ao canal sem evidencia aceito'}
 foreach($phrase in @('quero entrar na call Geral no servidor Amigos','Cove, pode me colocar na call Geral do servidor Amigos por favor?','eu queria que você me colocasse na call Geral no servidor Amigos','me bota na Geral do servidor Amigos','vai no servidor Amigos e entra na call Geral','entrar na call no servidor Amigos na call Geral','dá pra você entrar na call Geral no servidor Amigos?')){
  $r=Get-CoveDiscordRequest $phrase
  if(-not $r.Handled -or $r.Action -ne 'join' -or $r.Server -ne 'Amigos' -or $r.Channel -ne 'Geral'){throw ('Pedido natural falhou: '+$phrase+' -> '+($r|ConvertTo-Json -Compress -Depth 4))}
 }
 foreach($phrase in @('vamos pra call no servidor Amigos','me coloca na call no servidor Amigos','queria entrar no servidor Amigos')){
  $r=Get-CoveDiscordRequest $phrase
  if(-not $r.AwaitReply -or $r.Server -ne 'Amigos' -or $r.NextDialog.Stage -ne 'channel'){throw ('Pergunta desnecessaria: '+$phrase)}
 }
 $r=Get-CoveDiscordRequest 'Amigos na Geral' ([pscustomobject]@{Stage='server';Server='';Channel='';Until=[datetime]::Now.AddSeconds(60)})
 if($r.Action -ne 'join' -or $r.Server -ne 'Amigos' -or $r.Channel -ne 'Geral'){throw 'Resposta com dois nomes nao foi aproveitada'}
 $r=Get-CoveDiscordRequest 'é a Geral, por favor' $waiting
 if($r.Channel -ne 'Geral' -or $r.Action -ne 'join'){throw 'Resposta natural curta rejeitada'}
 foreach($answer in @('me coloca na call Geral','quero entrar na call Geral','entra na Geral','pode ser a Geral','a Geral mesmo')){
  $r=Get-CoveDiscordRequest $answer $waiting
  if($r.Server -ne 'Amigos' -or $r.Action -ne 'join'){throw ('Servidor ja informado foi esquecido: '+$answer)}
 }
 foreach($phrase in @('pode nao entrar na call Geral no servidor Amigos','queria saber como entrar na call','me explica como entrar na call')){
  if((Get-CoveDiscordRequest $phrase).Action -eq 'join'){throw ('Acao sem pedido direto: '+$phrase)}
 }
 $guildSource=[IO.File]::ReadAllText("$PSScriptRoot\CoveDiscord.cs") -replace '(?s)  public static bool IsPrivateResult\(.*?(?=  public static Task<string> Join\(string url,string server)',''
 if($guildSource -match 'Computer\.Press\(75|Computer\.Type|static void Search\(|static void Navigate\('){throw 'A entrada em servidor ainda usa pesquisa ou digita texto'}
 if([CoveApp.DiscordCall]::VoiceChannelScore('geral, canal de voz','','','','geral') -lt 0){throw 'Canal de voz reconhecido foi rejeitado'}
 if([CoveApp.DiscordCall]::VoiceChannelScore('geral, canal de texto','','','','geral') -ge 0){throw 'Canal de texto aceito como voz'}
 if([CoveApp.DiscordCall]::VoiceChannelScore('geral','','','','geral') -ge 0){throw 'Canal sem tipo foi aceito como voz'}
 if([CoveApp.DiscordCall]::VoiceChannelScore('Canal de voz: geral','','','','geral') -lt 0){throw 'Rotulo de voz antes do nome foi rejeitado'}
 if(-not [CoveApp.DiscordCall]::TitleContainsDestination('geral | CAPS - Discord','CAPS')){throw 'Servidor ativo nao identificado'}
 if([CoveApp.DiscordCall]::TitleContainsDestination('geral | OUTRO - Discord','CAPS')){throw 'Outro servidor foi confirmado'}
 if(-not [CoveApp.DiscordCall]::ChannelNavigation('Canais','','CAPS')){throw 'Lista de canais nao identificada'}
 if([CoveApp.DiscordCall]::ChannelNavigation('Mensagens privadas','chat-messages','CAPS')){throw 'Mensagens privadas tratadas como lista de canais'}
 if(-not [CoveApp.DiscordCall]::IsOpenServerView('CAPS (servidor)','CAPS')){throw 'Servidor ja aberto ignorado'}
 if([CoveApp.DiscordCall]::IsOpenServerView('OUTRO (servidor)','CAPS')){throw 'Outro servidor aceito como CAPS'}
 if(-not [CoveApp.DiscordCall]::IsServerFolder('OUTRO, CAPS, pasta , 3 menções não lidas')){throw 'Pasta real do Discord nao identificada'}
 if([CoveApp.DiscordCall]::IsServerFolder('CAPS, servidor')){throw 'Servidor tratado como pasta'}
 if([CoveApp.DiscordCall]::VoiceChannelScore('🔉-geral (canal de voz), não lida','','','','Geral') -lt 0){throw 'Rotulo real da call geral nao reconhecido'}
 if([CoveApp.DiscordCall]::NameScore('Servidor dos Amigos','Amigos') -lt 0){throw 'Nome curto de servidor rejeitado'}
 if([CoveApp.DiscordCall]::NameScore('01 | Geral','Geral') -lt 0){throw 'Nome de canal com decoracao rejeitado'}
 if([CoveApp.DiscordCall]::NameScore('Geral','Geral') -ge [CoveApp.DiscordCall]::NameScore('01 | Geral','Geral')){throw 'Nome exato deve ter prioridade'}
 if([CoveApp.DiscordCall]::DestinationMatches('Musica',@('Musica','Geral'),'Geral','Geral',$false)){throw 'Nome de servidor confundido com canal'}
}finally{$script:coveDiscordFile=$original;if(Test-Path -LiteralPath $testFile){Remove-Item -LiteralPath $testFile}}
'OK: compilacao, dialogo servidor/canal, previa sem efeitos, cancelamento, expiracao, nomes repetidos e selecao do servidor correto. Nenhuma call real foi aberta durante os testes.'
