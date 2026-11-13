$script:coveDiscordFile=Join-Path $PSScriptRoot 'cove-discord.json'
. (Join-Path $PSScriptRoot 'CoveDiscordLinks.ps1')
$script:discordDialog=$null
function ConvertTo-CoveDiscordDestination([string]$name){
 $name=$name.Trim().TrimEnd([char[]]',;.!?')
 $name=$name -replace '(?i)\s+(?:no|do|pelo|em)\s+(?:discord|dicord|discorde|disco|dc)\s*$',''
 $name=$name -replace '(?i)^(?:chamad[oa]|que se chama|(?:com\s+)?o nome(?: de)?|de nome)\s+',''
 return $name.Trim().Trim([char[]]'"''')
}
function Test-CoveDiscordActionRequest([string]$text){
 $words=ConvertTo-CoveAppName (ConvertTo-CoveRequestLanguage $text)
 if($words -match '^(nao|como|por que|o site|ele disse|me explica|explique|explica|saber|entender|se|caso)\b' -or $words -match '\bnao\s+(?:(?:quero|queria|pode|preciso)\s+)?(?:entrar|entra|entre|conectar|conecta|colocar|coloca|botar|bota)\b'){return $false}
 $domain=$words -match '\b(call|cal|cau|chamada|canal de voz|servidor|discord|dicord|discorde|dsicrod|dsicord|dc)\b'
 if(-not $domain -and $words -match '^(?:me )?(entra|entrar|entre|conecta|coloca|bota) (na|no) (?:a |o )?(geral|lounge)$'){$domain=$true}
 $action=$words -match '^(?:(?:me|nos) )?(entr\w*|conect\w*|coloc\w*|bot\w*|lev\w*|deix\w*|acess\w*|junt\w*|tent\w*|poe|ponha|vamos|bora|vai|ir|manda|mande|ajuda|ajude|ajudar|faz|faca|seria possivel)\b'
 if(-not $action -and $words -match '^(abre|abrir|abra|inicia|iniciar)\b.*\b(entrar|entra|entre|conectar|conecta|coloca|bota)\b'){$action=$true}
 return $domain -and $action
}
function Get-CoveDiscordFreeDestination([string]$text){
 $server='';$channel=''
 $serverEnd='(?=[,;]?\s+(?:e\s+)?(?:(?:entra|entrar|entre|me coloca|me bota)\s+)?(?:na|no|pra|para)\s+(?:call|chamada|canal)\b|\s+(?:por favor|pra mim|para mim)\b|[.!?]*$)'
 if($text -match ('(?i)\bservidor\s+(.+?)'+$serverEnd)){$server=$Matches[1].Trim().TrimEnd([char[]]',;.!?')}
 $channelEnd='(?=\s+(?:no|do|em|pro)\s+(?:servidor|discord|dc)\b|\s+(?:por favor|pra mim|para mim)\b|[.!?]*$)'
 if($text -match ('(?i)\b(?:call|chamada|canal(?: de voz)?)\s+(.+?)'+$channelEnd)){$channel=$Matches[1].Trim().TrimEnd([char[]]',;.!?')}
 if(-not $channel -and $text -match '(?i)^(?:me\s+)?(?:entra|entrar|entre|conecta|coloca|bota)\s+(?:na|no)\s+(?:a\s+|o\s+)?(geral|lounge)$'){$channel=$Matches[1]}
 if((ConvertTo-CoveAppName $channel) -match '^(ai|la|essa|uma|de voz|do discord|no discord|dc|no servidor .+|do servidor .+)$'){$channel=''}
 return [pscustomobject]@{Server=$server;Channel=$channel}
}
function Get-CoveDiscordRequest([string]$text,$Dialog=$script:discordDialog){
 $result=[pscustomobject]@{Handled=$false;Message='';Task=$null;NeedsConfirmation=$false;AppName='';AwaitReply=$false;NeedsCallLink=$false;NavigationMode='interface';NextDialog=$null;Action='';Server='';Channel='';Friend='';Url=''}
 $command=ConvertTo-CoveAppName $text
 if($Dialog -and [datetime]::Now -ge $Dialog.Until){$Dialog=$null}
 if($Dialog -and $command -match '^(cancelar|cancela|cancele|cancelar call|cancelar chamada|nao|deixa pra la|esquece)$'){
  $result.Handled=$true;$result.Message='Entrada na call cancelada.';return $result
 }
 if($command -match '^(nao|como|por que|o site|ele disse)\b'){return $result}
 if($text -match '(?i)^\s*(?:configurar|salvar) call(?: do discord)?\s+(.+?)\s+com link\s+(\S+)\s*$'){
  $result.Handled=$true;$result.Channel=$Matches[1].Trim();$link=$Matches[2]
  if($link -notmatch '^https://(?:www\.)?discord\.com/channels/(\d{15,22})/(\d{15,22})/?$'){$result.Message='Use o link do canal: https://discord.com/channels/servidor/canal. Convites de servidor nao identificam uma call.';return $result}
  $result.Url='discord://-/channels/'+$Matches[1]+'/'+$Matches[2];$result.Action='save'
  $result.Message='Call padrao salva. Para usa-la, diga entrar na call padrao.';return $result
 }
 if($Dialog -and $text -match '(?i)^\s*(?:pode ser|vai ser)\s+(.+)$'){$text=$Matches[1]}
 $text=ConvertTo-CoveRequestLanguage $text
 $text=$text -replace '(?i)(\b(?:na|uma|nessa|em|a)\s+)(?:cal|cau)\b','$1call'
 $text=$text -replace '(?i)(\b(?:do|no)\s+)(?:disco|dicord|discorde|dsicrod|dsicord|dc)\b','$1Discord'
 $command=ConvertTo-CoveAppName $text
 if($command -match '^(nao|como|por que|o site|ele disse)\b'){return $result}
 # Private voice calls are explicit actions, separate from guild destinations.
 $text=$text -replace '(?i)\b(liga[cç][aã]o|chamada)(?:\s+de voz)?\s+(?:no|pelo)\s+discord\s+(?:para|pra|pro|com)\s+','$1 para '
 $text=$text -replace '(?i)^(?:faz|faca|faça|fazer|realiza|realize)\s+(?:uma\s+)?(?:liga[cç][aã]o|chamada)(?:\s+de voz)?\s+(?:para|pra|pro|com)\s+','ligar para '
 $text=$text -replace '(?i)^(?:inicia|inicie|iniciar)\s+(?:uma\s+)?liga[cç][aã]o\s+(?:para|pra|pro|com)\s+','ligar para '
 $friend=''
 if($text -match '(?i)^(?:liga|ligar|ligue)\s+(?:para o|para a|para|pra|pro)\s+(.+?)(?:\s+no discord)?[.!?]*$'){$friend=$Matches[1]}
 elseif($text -match '(?i)^(?:chama|chame|chamar)\s+(.+?)\s+(?:no|em)\s+(?:privado|pv)(?:\s+do discord)?[.!?]*$'){$friend=$Matches[1]}
 elseif($text -match '(?i)^(?:chama|chame|chamar|liga|ligue|ligar)\s+(?:o\s+|a\s+)?(.+?)\s+no discord[.!?]*$'){$friend=$Matches[1]}
 elseif($text -match '(?i)^(?:entra|entre|entrar|inicia|inicie|iniciar|abre|abra)\s+(?:na |uma |a )?(?:call|chamada)\s+(?:privada\s+)?com\s+(.+?)(?:\s+(?:no|em)\s+(?:privado|pv|discord))?[.!?]*$'){$friend=$Matches[1]}
 elseif($Dialog -and $Dialog.Stage -eq 'friend'){
  if($command -match '^(abre|abra|abrir|digite|leia|listar|liste|pressione|focar|criar|excluir|qual|como|quem|quando|me explica)\b' -or $text.Length -gt 100){return $result}
  $friend=$text
 }
 if($friend){
  $friend=$friend -replace '(?i)\s+(?:no|pelo)\s+discord$',''
  $friend=ConvertTo-CoveDiscordDestination ($friend -replace '(?i)^(?:o meu amigo|a minha amiga|meu amigo|minha amiga|o amigo|a amiga|o|a)\s+','')
  $result.Handled=$true
  if((ConvertTo-CoveAppName $friend) -in @('alguem','um amigo','uma amiga','meu amigo','minha amiga')){
   $result.AwaitReply=$true;$result.Message='Qual amigo do Discord?';$result.NextDialog=[pscustomobject]@{Stage='friend';Server='';Channel='';Until=[datetime]::Now.AddSeconds(90)}
  }else{$result.Friend=$friend;$result.Action='private';$result.Message='Vou ligar por voz para '+$friend+' no privado do Discord.'}
  return $result
 }
 # Normalize conversational ways of asking to join, retaining destination names.
 $text=$text -replace '(?i)^(?:me\s+)?(?:coloca|coloque|colocasse|colocar|bota|bote|botasse|botar|leva|leve|levasse|levar|poe|põe|ponha)\s+(?:na|no|pra|para|em)\s+(?:(?:a|o|uma|um)\s+)?(?=(?:call|chamada|canal de voz)\b)','entrar na '
 $text=$text -replace '(?i)^(?:bora|vamos)\s+(?:pra|para|na)\s+(?:a\s+)?(?=(?:call|chamada)\b)','entrar na '
 if($text -match '(?i)^(?:me\s+)?(?:coloca|coloque|bota|bote|leva|leve)\s+(?:na|no)\s+(?!call\b|chamada\b|canal\b)(.+?\s+(?:no|do) servidor\s+.+)$'){$text='entrar na call '+$Matches[1]}
 $prefix='(?i)^\s*(?:me\s+)?(?:entra|entrar|entre|entrasse|conecta|conecte|conectar|vai|ir)\s+(?:na\s+|no\s+|em uma\s+|em\s+|nessa\s+|pra\s+|para\s+)?(?:call|chamada|canal de voz)'
 $server='';$channel='';$matched=$false
 if($Dialog -and $text -notmatch '(?i)^(?:me\s+)?(?:entra|entrar|entre|entrasse|vai|va|vá|abre|abra|conecta|conectar|coloca|bota)\b' -and $text -match '(?i)^(?:(?:no|o)\s+)?(?:servidor\s+)?(.+?)\s+(?:e\s+)?(?:na|no)\s+(?:(?:call|chamada|canal de voz)\s+)?(.+?)\s*$'){
  $matched=$true;$server=$Matches[1].Trim();$channel=$Matches[2].Trim()
 }elseif($text -match ('(?i)^\s*(?:vai|va|vá|entra|entre|entrar|abre|abra)\s+(?:no|o|pro|para o)\s+servidor\s+(.+?)\s+(?:e\s+)?(?:entra\s+|entrar\s+|entre\s+|me coloca\s+|me bota\s+)?(?:na|no)\s+(?:call|chamada|canal de voz)\s+(.+?)\s*$')){
  $matched=$true;$server=$Matches[1].Trim();$channel=$Matches[2].Trim()
 }elseif($text -match ($prefix+'(?:\s+(?:no|do) discord)?\s+(?:no|do|em um|em) servidor\s+(.+?)\s+(?:e\s+)?(?:na|no)\s+(?:call|chamada|canal de voz)\s+(.+?)\s*$')){
  $matched=$true;$server=$Matches[1].Trim();$channel=$Matches[2].Trim()
 }elseif($text -match ($prefix+'(?:\s+(?:no|do) discord)?\s+(?:no|do|em um|em) servidor\s+(.+?)\s*$')){
  $matched=$true;$server=$Matches[1].Trim()
 }elseif($text -match ($prefix+'\s+(.+?)\s+(?:no|do) servidor\s+(.+?)\s*$')){
  $matched=$true;$channel=$Matches[1].Trim();$server=$Matches[2].Trim()
 }elseif($text -match '(?i)^(?:vai|va|vá|entra|entre|entrar|abre|abra)\s+(?:no|o|pro|para o)\s+servidor\s+(.+?)\s*$'){
  $matched=$true;$server=$Matches[1].Trim()
 }elseif((ConvertTo-CoveAppName $text) -match '^(entra|entrar|entre) na call padrao$'){
  $result.Handled=$true
  try{
   $saved=Get-Content -LiteralPath $script:coveDiscordFile -Raw -ErrorAction Stop|ConvertFrom-Json
   $result.Channel=[string]$saved.Name;$result.Url=[string]$saved.Url;$result.Action='join'
   $result.Message='Vou abrir a call padrao '+$result.Channel+'.'
  }catch{$result.Message='Ainda nao ha uma call padrao salva. Diga entrar na call para escolher servidor e canal.'}
  return $result
 }elseif($text -match ($prefix+'(?:\s+(?:do|no) discord)?(?:\s+por favor)?[.!?]*\s*$')){
  $matched=$true
 }elseif($text -match ($prefix+'\s+(.+?)(?:\s+(?:no|do) discord)?\s*$')){
  $matched=$true;$channel=$Matches[1].Trim()
 }elseif(Test-CoveDiscordActionRequest $text){
  # A request to join must never fall through to a text-only AI explanation.
  # Recover supplied names independently of sentence order; ask only for gaps.
  $free=Get-CoveDiscordFreeDestination $text
  $server=$free.Server;$channel=$free.Channel;$matched=$true
 }elseif($Dialog){
  if($command -match '^(abre|abra|abrir|digite|leia|listar|liste|pressione|focar|criar|excluir|qual|como|quem|quando|me explica)\b' -or $text.Length -gt 100){return $result}
  $server=[string]$Dialog.Server;$channel=[string]$Dialog.Channel
  $text=$text -replace '(?i)^(?:me\s+)?(?:coloca|coloque|bota|bote|entra|entrar|entre|vai|conecta)\s+(?:na|no|em|pra)\s+',''
  if($Dialog.Stage -eq 'server'){$server=($text -replace '(?i)^\s*(?:[e\u00e9]\s+)?(?:(?:o|no|do)\s+)?(?:servidor\s+)?','').Trim()}
  elseif($Dialog.Stage -eq 'channel'){$channel=($text -replace '(?i)^\s*(?:[e\u00e9]\s+)?(?:(?:a|o|na|no)\s+)?(?:(?:call|chamada|canal(?: de voz)?)\s+)?','').Trim()}
  $matched=$true
 }
 if(-not $matched){return $result}
 $server=ConvertTo-CoveDiscordDestination $server
 $channel=ConvertTo-CoveDiscordDestination $channel
 # Recover independent slots even when a broad sentence pattern matched first.
 if(Test-CoveDiscordActionRequest $text){
  $free=Get-CoveDiscordFreeDestination $text
  if(-not $server -and $free.Server){$server=ConvertTo-CoveDiscordDestination $free.Server}
  if(-not $channel -and $free.Channel){$channel=ConvertTo-CoveDiscordDestination $free.Channel}
 }
 # A fuller follow-up may contain an action verb; retain slots already supplied.
 if($Dialog){
  if(-not $server){$server=[string]$Dialog.Server}
  if(-not $channel -and (-not $Dialog.Server -or (ConvertTo-CoveAppName $server) -eq (ConvertTo-CoveAppName $Dialog.Server))){$channel=[string]$Dialog.Channel}
 }
 $result.Handled=$true;$result.Server=$server;$result.Channel=$channel
 if(-not $server){
  $result.AwaitReply=$true;$result.Message='Em qual servidor do Discord?'
  $result.NextDialog=[pscustomobject]@{Stage='server';Server='';Channel=$channel;Until=[datetime]::Now.AddSeconds(90)}
 }elseif(-not $channel){
  $result.AwaitReply=$true;$result.Message='Qual e o nome da call no servidor '+$server+'?'
  $result.NextDialog=[pscustomobject]@{Stage='channel';Server=$server;Channel='';Until=[datetime]::Now.AddSeconds(90)}
 }else{
  $result.Action='join';$result.Message='Vou procurar a call '+$channel+' no servidor '+$server+'.'
 }
 return $result
}
function Invoke-CoveDiscordRequest([string]$text,[switch]$DryRun){
 $result=Get-CoveDiscordRequest $text
 if(-not $result.Handled -or $DryRun){return $result}
 $script:discordDialog=$result.NextDialog
 $result=Resolve-CoveDiscordLinkRequest $result
 if($result.Action -eq 'save'){
  [IO.File]::WriteAllText($script:coveDiscordFile,(@{Name=$result.Channel;Url=$result.Url}|ConvertTo-Json -Compress),[Text.Encoding]::UTF8)
 }elseif($result.Action -eq 'private'){
  [CoveApp.DiscordCall]::DiagnosticFile=Join-Path $PSScriptRoot 'cove-discord-diagnostico.log'
  $result.Task=[CoveApp.DiscordCall]::CallFriend($result.Friend,((Get-CoveDiscordLinks).Method -eq 'mouse'),$script:discordCancel.Token)
 }elseif($result.Action -eq 'join'){
  [CoveApp.DiscordCall]::DiagnosticFile=Join-Path $PSScriptRoot 'cove-discord-diagnostico.log'
  if($result.NavigationMode -eq 'mouse'){
   $result.Message='Vou mover o mouse para entrar na call '+$result.Channel+' no servidor '+$result.Server+'. Esc interrompe.'
   $result.Task=[CoveApp.DiscordCall]::JoinMouse($result.Url,$result.Server,$result.Channel,$script:discordCancel.Token)
  }else{$result.Task=[CoveApp.DiscordCall]::Join($result.Url,$result.Server,$result.Channel,$script:discordCancel.Token)}
 }
 return $result
}
