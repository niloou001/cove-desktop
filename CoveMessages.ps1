$script:messageDialog=$null
function Resolve-CoveContactName([string]$Name){
 $file=Join-Path $PSScriptRoot 'cove-contact-aliases.json'
 if(Test-Path -LiteralPath $file){try{
  $aliases=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json;$key=ConvertTo-CoveAppName $Name
  foreach($entry in $aliases.PSObject.Properties){if((ConvertTo-CoveAppName $entry.Name) -eq $key -and $entry.Value -is [string] -and $entry.Value.Length -le 100){return $entry.Value}}
 }catch{}}
 return $Name
}
function Get-CoveMessagePlatform([string]$Text){
 if($Text -match '(?i)discord'){return 'Discord'}
 if($Text -match '(?i)\bweb\b'){return 'WhatsApp Web'}
 return 'WhatsApp'
}
function ConvertTo-CoveMessageLanguage([string]$Text){
 for($i=0;$i -lt 3;$i++){$Text=ConvertTo-CoveRequestLanguage $Text;$Text=$Text -replace '(?i)^(?:agora|entao|então|beleza|ok)[, :]+',''}
 return $Text
}
function Get-CoveMessageContext {
 if($script:messageContext -and [datetime]::Now -lt $script:messageContext.Until){return $script:messageContext}
 return $null
}
function Get-CoveExplicitMessagePlatform([string]$Text){
 $key=ConvertTo-CoveAppName $Text
 if($key -match '^nao e (?:no |pelo )?.+? (?:e sim |mas sim |e no |mas no )(.+)$'){
  $key=$Matches[1]
  if($key -match '^(?:no |pelo )?(?:web|ueb|chrome|navegador)$'){return 'WhatsApp Web'}
  if($key -match '^(?:no |pelo )?desktop$'){return 'WhatsApp'}
 }
 if($key -match '\bdiscordd?\b'){return 'Discord'}
 if($key -match '\b(whats ?app?|whatssapp?|zap)\b'){
  if($key -match '\b(desktop|aplicativo instalado|app instalado)\b'){return 'WhatsApp'}
  if($key -match '\b(web|ueb|we b|eb|chrome|navegador|site)\b'){return 'WhatsApp Web'}
  return 'WhatsApp'
 }
 return ''
}
function ConvertTo-CoveMessageBody([string]$Text){
 $text=$Text.Trim()
 if($text -match '^(?:"([\s\S]+)"|''([\s\S]+)'')$'){return $text.Substring(1,$text.Length-2)}
 $text=$text -replace '(?i)^(?:que|q)\s+',''
 if((ConvertTo-CoveAppName $text) -in @('gosto dela','gosta dela','gosto dele','gosta dele','eu gosto dela','eu gosto dele')){return 'Eu gosto de voce.'}
 return $text
}
function ConvertTo-CoveMessageNavigation([string]$Text){
 # Preserve the complete message, including final punctuation, while removing
 # conversational prefixes. Only a leading, explicit navigation/send pair counts.
 $marker='COVE_NAV_END_SENTINEL'
 $command=ConvertTo-CoveMessageLanguage ($Text+' '+$marker)
 $command=$command.Substring(0,$command.LastIndexOf($marker)).TrimEnd()
 if($command -match '(?is)^(?:entra|entre|entrar|abre|abra|abrir|acessa|acesse|acessar|v[aá]|vai)\s+(?:no|na|o|a)\s+((?:whats\s?app|whatsap|whatssapp?)(?:\s+web)?|discordd?)\s*[,;]?\s+(?:e\s+)?(?:me\s+)?(?:mande|manda|mandar|envie|envia|enviar)\s+(?:(?:uma|a)\s+)?(?:(?:mensagem|msg|recado)\s+)?(.+)$'){
  return 'mande mensagem no '+$Matches[1]+' '+$Matches[2]
 }
 return $Text
}
function Get-CoveMessageRequest([string]$Text,$Dialog=$script:messageDialog){
 $r=[pscustomobject]@{Handled=$false;Message='';Task=$null;AwaitReply=$false;NextDialog=$null;Recipient='';Body='';Platform='';Action=''}
 $original=(ConvertTo-CoveMessageNavigation $Text).Trim();$text=ConvertTo-CoveMessageLanguage $original
 # A new message is a new controller action, even after an earlier send/error.
 $original=$original -replace '(?i)^(manda|mande|envia|envie|mandar|enviar)\s+(?:mais\s+uma|outra)\s+(?=mensagem|msg|recado)','$1 uma '
 $text=ConvertTo-CoveMessageLanguage $original
 # A complete request can start with the noun, without a send verb.
 if($text -match '(?i)^(?:mensagem|msg|recado)\s+(?:para|pra|pro)\b'){$original='mande '+$original;$text='mande '+$text}
 if($text -match '(?i)^(?:mande|manda|mandar|envie|envia|enviar)\s+(?:(?:a|uma)\s+mensagem\s+)?("[^"]+"|''[^'']+'')\s+((?:para|pra|pro)\s+.+)$'){$original='mande mensagem '+$Matches[2]+' dizendo '+$Matches[1];$text=$original}
 elseif($text -match '(?i)^(?:mande|manda|mandar|envie|envia|enviar)\s+(?:um\s+|uma\s+)?(oi|ola|olá|bom dia|boa tarde|boa noite)\s+((?:para|pra|pro)\s+.+)$'){$original='mande mensagem '+$Matches[2]+' dizendo "'+$Matches[1]+'"';$text=$original}
 # Normalize only the command prefix. Message punctuation and trailing words are literal.
 $keyword=[regex]::Match($original,'(?i)\b(?:mensagem|msg|mensagen|menssagem|menssagen)\b')
 if(-not $keyword.Success){$keyword=[regex]::Match($original,'(?i)\b(?:mande|manda|mandar|envie|envia|enviar|diga|fala|fale)\b')}
 if($keyword.Success){
  $separator=[regex]::Match($original.Substring($keyword.Index+$keyword.Length),'(?i)\s+(?:(?:e\s+)?(?:diga|diz|fala|fale)|dizendo|falando|avisando|com (?:o )?texto|com (?:a )?mensagem)\s+|:\s*|(?<=discord)\s+(?:que|q)\s+|(?<=whatsapp)\s+(?:que|q)\s+')
  if($separator.Success){$cut=$keyword.Index+$keyword.Length+$separator.Index+$separator.Length;$prefix=$original.Substring(0,$cut);$suffix=$original.Substring($cut);$text=(ConvertTo-CoveMessageLanguage ($prefix+'COVE_MESSAGE_BODY_SENTINEL')).Replace('COVE_MESSAGE_BODY_SENTINEL',$suffix)}
 }
 # These replacements touch the action prefix only, retaining the message itself.
 $text=$text -replace '(?i)^(?:me\s+)?(?:manda|mande|mandar|envia|envie|enviar)\s+(?=(?:para|pra|pro)\b)','mande mensagem '
 if($text -match '(?i)^(?:diga|fala|fale)\s+((?:para|pra|pro)\s+.+?\s+(?:no|pelo)\s+(?:discord|whatsapp(?:\s+web)?))\s+(?:que|q)\s+(.+)$'){$text='mande mensagem '+$Matches[1]+' dizendo '+$Matches[2]}
 $key=ConvertTo-CoveAppName $text
 if($Dialog -and [datetime]::Now -ge $Dialog.Until){$Dialog=$null}
 if($Dialog -and $key -in @('cancelar','cancela','nao','esquece','deixa pra la')){$r.Handled=$true;$r.Message='Envio cancelado.';return $r}
 $context=Get-CoveMessageContext
 if($Dialog -and $Dialog.Stage -ne 'planned'){$context=[pscustomobject]@{Recipient=$Dialog.Recipient;Platform=$Dialog.Platform;Body=$Dialog.Body}}
 $correction=$key -match '^(?:(?:voce|vc) (?:entendeu|entendeu tudo|ouviu) errado|eu disse|eu falei|o contato (?:e|se chama)|(?:nao[, ]+)?(?:e|era) (?:no|pelo|para o|pra o)|nao e (?:no|pelo|para))\b'
 $correctedName=''
 if($context -and $original -match '(?is)^(?:n[aã]o[, ]+)?(?:(?:o\s+)?(?:nome|contato)(?:\s+correto)?\s+[eé]|[eé]|eu quis dizer|eu disse|eu falei|corrige para|corrija para|o certo [eé]|troca o (?:nome|contato) para)\s+(.+?)(?:[,;]?\s+(?:pode\s+)?(?:manda|mande|envia|envie)(?:\s+(?:de novo|novamente))?)?[.!?]*$'){
  $candidate=$Matches[1].Trim()
  if($candidate -notmatch '(?i)^(?:no|pelo|na|para|pra|pro)\b|\b(?:resultado|envio|mensagem|discord|whatsapp)\b'){$correctedName=$candidate;$correction=$true}
 }
 if($context -and $original -match '(?is)^n[aã]o\s+[eé]\s+.+?[,;]?\s+[eé]\s+(.+?)[.!?]*$'){
  $candidate=$Matches[1].Trim()
  if($candidate -notmatch '(?i)^(?:no|pelo|na|para|pra|pro)\b|\b(?:resultado|envio|mensagem|discord|whatsapp)\b'){$correctedName=$candidate;$correction=$true}
 }
 if($context -and (-not $Dialog -or $Dialog.Stage -ne 'platform') -and $key -match '^(?:(?:no|na|pelo|pela|via) )?(?:whats ?app?|whatssapp?)(?: (?:web|ueb|we b|eb|desktop|do chrome|no chrome|pelo chrome))?$'){$correction=$true}
 if($key -match '^(nao|como|me explica|explique|o site|ele disse)\b' -and -not $correction){return $r}
 $header='';$body='';$matched=$false;$correctionOnly=$false
 $endMarker='COVE_END_SENTINEL';$continuation=ConvertTo-CoveMessageLanguage ($original+' '+$endMarker);$continuation=$continuation.Substring(0,$continuation.LastIndexOf($endMarker)).TrimEnd()
 if($context -and $key -match '^(?:(?:tenta|tente) (?:mandar |enviar )?(?:de novo|novamente)|(?:manda|mande|envia|envie|reenvia|reenvie)(?: a mensagem| a mesma mensagem| isso)? (?:de novo|novamente))$'){
  $matched=$true;$r.Recipient=$context.Recipient;$r.Platform=$context.Platform;$r.Body=$context.Body
 }elseif($correction -and $context){
  $matched=$true;$correctionOnly=$true;$r.Recipient=[string]$context.Recipient;$r.Platform=[string]$context.Platform;$r.Body=[string]$context.Body
  if($correctedName){$r.Recipient=$correctedName}
  $head=([regex]::Split($continuation,'(?i)\s+(?:dizendo|falando|avisando)\s+|:',2))[0]
  $explicit=Get-CoveExplicitMessagePlatform $head
  if($explicit){if($explicit -ne 'WhatsApp' -or $r.Platform -ne 'WhatsApp Web' -or $head -match '(?i)\bdesktop\b'){$r.Platform=$explicit}}
  if($continuation -match '(?i)\b(?:contato\s+(?:chamad[oa]|que se chama)|contato\s+(?:e|é|se chama)|para\s+(?:o\s+)?contato)\s+(.+?)(?=\s+(?:no|pelo|via|do)\s+(?:whats|chrome|discord)|[,.;!?]|$)'){$r.Recipient=$Matches[1].Trim()}
  if($r.Body -match '(?i)^(?:voce|você|vc)\s+entendeu|^(?:nao|não)\s+[eé]\s+(?:no|para)|^eu\s+(?:disse|falei)'){$r.Body=''}
  if($continuation -match '(?is)\b(?:dizendo|falando|avisando)\s+(.+)$'){$r.Body=ConvertTo-CoveMessageBody $Matches[1]}
  # The correction continues the user's send request when a concrete value changes.
  if($r.Recipient -cne $context.Recipient -or $r.Platform -cne $context.Platform -or $r.Body -cne $context.Body){$correctionOnly=$false}
 }elseif($Dialog -and $Dialog.Stage -eq 'confirm' -and $key -in @('sim','pode','pode enviar','pode mandar','manda','envia','confirmo')){
  $matched=$true;$r.Recipient=$Dialog.Recipient;$r.Platform=$Dialog.Platform;$r.Body=$Dialog.Body
 }elseif($continuation -match '(?i)^(?:manda|mande|envia|envie)\s+(?:isso|essa resposta|essa mensagem|esse texto|esse recado|o texto|a resposta)(?:\s+(?:para|pra|pro)\s+(.+?))?(?:\s+(?:no|pelo)\s+(discord|(?:whats\s?app|whatsap|whatssap)(?:\s+web)?))?[.!?]*$'){
  $matched=$true;$r.Recipient=$Matches[1];$app=$Matches[2];$r.Platform=if($app){Get-CoveMessagePlatform $app}else{''}
  if($context){if(-not $r.Recipient){$r.Recipient=$context.Recipient};if(-not $r.Platform){$r.Platform=$context.Platform};$r.Body=$context.Body}
  if($script:lastConversationalAnswer -and [datetime]::Now -lt $script:lastConversationalAnswer.Until -and (-not $context -or -not $context.Until -or $script:lastConversationalAnswer.Until -gt $context.Until)){$r.Body=$script:lastConversationalAnswer.Text}
 }elseif($continuation -match '(?i)^(?:manda|mande|mandar|envia|envie|enviar|diga|diz|dizer|fala|fale|falar)\s+(?:(?:tambem|também)\s+)?(?:(?:para|pra|pro)\s+(?:ela|ele|o mesmo contato|a mesma pessoa)\s+)?(?:dizendo|falando|que|q)\s+(.+)$'){
  $matched=$true;$r.Body=ConvertTo-CoveMessageBody $Matches[1]
  if($context){$r.Recipient=$context.Recipient;$r.Platform=$context.Platform}
 }elseif($context -and $continuation -match '(?i)^(?:manda|mande|envia|envie|reenvia|reenvie)\s+(?:a\s+)?mesma mensagem\s+(?:para|pra|pro)\s+(.+?)(?:\s+(?:no|pelo)\s+(discord|(?:whats\s?app|whatsap|whatssap)(?:\s+web)?))?[.!?]*$'){
  $matched=$true;$r.Recipient=$Matches[1].Trim();$r.Body=$context.Body;$r.Platform=if($Matches[2]){Get-CoveMessagePlatform $Matches[2]}else{$context.Platform}
 }elseif($text -match '(?i)^(?:mande|manda|mandar|envie|envia|enviar)\s+(?:uma\s+|a\s+)?(?:mensagem|msg|mensagen|menssagem|menssagen|dm)\s+(?:(?:privada|direta)\s+)?(.+)$'){
  $rest=$Matches[1];$matched=$true
  if($rest -match '(?i)^(.+?)\s+(?:(?:e\s+)?(?:diga|diz|fala|fale)|dizendo|falando|avisando|com (?:o )?texto|com (?:a )?mensagem)\s+(.+)$'){$header=$Matches[1];$body=$Matches[2]}
  elseif($rest -match '(?i)^(.+?\s+(?:no|pelo)\s+(?:discord|whatsapp(?:\s+web)?))\s+(?:que|q)\s+(.+)$'){$header=$Matches[1];$body=$Matches[2]}
  elseif($rest -match '^(.+?)\s*:\s*(.+)$'){$header=$Matches[1];$body=$Matches[2]}
  else{$header=$rest}
  $explicit=Get-CoveExplicitMessagePlatform $header
  if($header -match '(?i)\b(?:(?:whats\s?app|whatsap|whatssap)(?:\s+web)?|zap|discordd?|discorde)\b'){$app=$Matches[0];$r.Platform=Get-CoveMessagePlatform $app;$header=$header -replace '(?i)(?:\b(?:no|na|pelo|pela|via|do)\s+)?\b(?:(?:whats\s?app|whatsap|whatssap)(?:\s+web)?|zap|discordd?|discorde)\b',''}
  if(-not $r.Platform -and $body -match '(?i)\s+(?:no|pelo|via)\s+((?:whats\s?app|whatsap|whatssap)(?:\s+web)?|zap|discordd?)\s*$'){$app=$Matches[1];$r.Platform=Get-CoveMessagePlatform $app;$body=$body -replace '(?i)\s+(?:no|pelo|via)\s+(?:(?:whats\s?app|whatsap|whatssap)(?:\s+web)?|zap|discordd?)\s*$',''}
  if($explicit){$r.Platform=$explicit}
  $header=$header -replace '(?i)\s+(?:e\s+)?(?:web|ueb|we\s+b|eb|desktop)(?:\s+(?:do|no|pelo)\s+chrome)?\b','' -replace '(?i)\s+(?:do|no|pelo)\s+(?:chrome|navegador)\b',''
  $r.Recipient=($header -replace '(?i)^\s*(?:para|pra|pro)\s+(?:(?:o|a|um|uma)\s+)?(?:(?:(?:meu|minha)\s+)?(?:contato|amigo|amiga)\s+(?:chamad[oa]\s+)?)?','').Trim().Trim([char[]]',; ')
  $r.Body=if($body){ConvertTo-CoveMessageBody $body}else{''}
 }elseif($Dialog){
  if($key -match '^(abre|abra|entre|entra|liga|ligue|pesquisa|pesquise|que horas|qual|quem)\b'){return $r}
  $matched=$true;$r.Platform=[string]$Dialog.Platform;$r.Recipient=[string]$Dialog.Recipient;$r.Body=[string]$Dialog.Body
  switch($Dialog.Stage){'platform'{if($key -match '\b(discord|discordd|discorde)\b'){$r.Platform='Discord'}elseif($key -match '\b(whatsapp|whats app|whatsap|whatssap|zap)\b'){$r.Platform=Get-CoveMessagePlatform $text}} 'recipient'{
   if($original -match '(?is)^(.+?)\s+(?:dizendo|falando|avisando)\s+(.+)$'){$r.Recipient=$Matches[1].Trim();$r.Body=ConvertTo-CoveMessageBody $Matches[2]}
   elseif($key -match '\b(?:mensagem|msg|recado|envie|mande|avisa|avisar)\b'){return [pscustomobject]@{Handled=$false;Message='';Task=$null;AwaitReply=$false;NextDialog=$null;Recipient='';Body='';Platform='';Action=''}}
   else{$r.Recipient=$text.Trim()}
  } 'body'{$r.Body=ConvertTo-CoveMessageBody $original}}
 }
 if(-not $matched){return $r};$r.Handled=$true
 $r.Recipient=Resolve-CoveContactName $r.Recipient
 $r.Recipient=($r.Recipient -replace '(?i)\s+(?:e\s+)?(?:web|ueb|we\s+b|eb)\s+(?:do|no|pelo)\s+chrome\s*$','').Trim()
 if($r.Platform -eq 'WhatsApp' -and $context -and $context.Platform -eq 'WhatsApp Web' -and $text -notmatch '(?i)\bdesktop\b'){$r.Platform='WhatsApp Web'}
 if((ConvertTo-CoveAppName $r.Recipient) -in @('ela','ele','mesmo contato','mesma pessoa')){$r.Recipient=if($context){$context.Recipient}else{''}}
 if(-not $r.Platform -and $context -and (ConvertTo-CoveAppName $r.Recipient) -eq (ConvertTo-CoveAppName $context.Recipient)){$r.Platform=$context.Platform}
 if(-not $r.Recipient){$stage='recipient';$r.Message='Para qual contato?'}
 elseif(-not $r.Body){$stage='body';$r.Message='Qual mensagem devo mandar para '+$r.Recipient+'?'}
 elseif(-not $r.Platform){$stage='platform';$r.Message='Mando para '+$r.Recipient+' no WhatsApp, WhatsApp Web ou Discord?'}
 elseif($correctionOnly){$stage='confirm';$r.Message='Corrigido: '+$r.Recipient+' no '+$r.Platform+'. Posso enviar esta mensagem: '+$r.Body+'?'}
 else{
  if($r.Recipient.Length -gt 100 -or $r.Body.Length -gt 2000){$r.Message='Use um contato de ate 100 caracteres e uma mensagem de ate 2000 caracteres.';return $r}
  $r.Action='send';$r.Message='Vou mandar para '+$r.Recipient+' no '+$r.Platform+': '+$r.Body;return $r
 }
 $r.AwaitReply=$true;$r.NextDialog=[pscustomobject]@{Stage=$stage;Recipient=$r.Recipient;Body=$r.Body;Platform=$r.Platform;Until=[datetime]::Now.AddMinutes(10)}
 return $r
}
function Invoke-CoveMessageRequest([string]$Text,[switch]$DryRun){
 $r=Get-CoveMessageRequest $Text
 return Invoke-CoveResolvedMessageRequest $r -DryRun:$DryRun
}
function Invoke-CoveResolvedMessageRequest($r,[switch]$DryRun){
 if(-not $r.Handled -or $DryRun){return $r}
 $script:discordDialog=$null
 $script:messageDialog=$r.NextDialog
 if($r.Action -eq 'send'){
  [CoveApp.Messaging]::DraftDirectory=Join-Path $PSScriptRoot '.cove-drafts'
  if($r.Platform -eq 'Discord'){
   [CoveApp.DiscordCall]::DiagnosticFile=Join-Path $PSScriptRoot 'cove-discord-diagnostico.log'
   $r.Task=[CoveApp.DiscordCall]::SendFriendMessage($r.Recipient,$r.Body,((Get-CoveDiscordLinks).Method -eq 'mouse'),$script:discordCancel.Token)
  }
  elseif($r.Platform -eq 'WhatsApp Web'){
   $chrome=Get-CoveChromePath
   if(-not $chrome){$r.Message='Nao encontrei o Chrome para abrir o WhatsApp Web.';return $r}
   $r.Task=[CoveApp.Messaging]::SendWhatsAppWeb($r.Recipient,$r.Body,$chrome,$script:discordCancel.Token)
  }elseif($r.Platform -eq 'WhatsApp'){$r.Task=[CoveApp.Messaging]::SendWhatsApp($r.Recipient,$r.Body,$script:discordCancel.Token)}
  else{throw 'Nao identifiquei o aplicativo de destino. Nada foi enviado.'}
  $script:messageContext=[pscustomobject]@{Recipient=$r.Recipient;Platform=$r.Platform;Body=$r.Body;Until=[datetime]::Now.AddMinutes(20)}
 }
 return $r
}
