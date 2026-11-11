$script:messageDialog=$null
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
function ConvertTo-CoveMessageBody([string]$Text){
 $text=$Text.Trim()
 if($text -match '^(?:"([\s\S]+)"|''([\s\S]+)'')$'){return $text.Substring(1,$text.Length-2)}
 $text=$text -replace '(?i)^(?:que|q)\s+',''
 if((ConvertTo-CoveAppName $text) -in @('gosto dela','gosta dela','gosto dele','gosta dele','eu gosto dela','eu gosto dele')){return 'Eu gosto de voce.'}
 return $text
}
function Get-CoveMessageRequest([string]$Text,$Dialog=$script:messageDialog){
 $r=[pscustomobject]@{Handled=$false;Message='';Task=$null;AwaitReply=$false;NextDialog=$null;Recipient='';Body='';Platform='';Action=''}
 $original=$Text.Trim();$text=ConvertTo-CoveMessageLanguage $Text
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
 if($key -match '^(nao|como|me explica|explique|o site|ele disse)\b'){return $r}
 $context=Get-CoveMessageContext
 if($Dialog -and $Dialog.Stage -ne 'planned'){$context=[pscustomobject]@{Recipient=$Dialog.Recipient;Platform=$Dialog.Platform;Body=$Dialog.Body}}
 $header='';$body='';$matched=$false
 $endMarker='COVE_END_SENTINEL';$continuation=ConvertTo-CoveMessageLanguage ($original+' '+$endMarker);$continuation=$continuation.Substring(0,$continuation.LastIndexOf($endMarker)).TrimEnd()
 if($continuation -match '(?i)^(?:manda|mande|envia|envie)\s+(?:isso|essa resposta|essa mensagem|esse texto|esse recado|o texto|a resposta)(?:\s+(?:para|pra|pro)\s+(.+?))?(?:\s+(?:no|pelo)\s+(discord|(?:whats\s?app|whatsap|whatssap)(?:\s+web)?))?[.!?]*$'){
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
  if($header -match '(?i)\b(?:(?:whats\s?app|whatsap|whatssap)(?:\s+web)?|zap|discordd?|discorde)\b'){$app=$Matches[0];$r.Platform=Get-CoveMessagePlatform $app;$header=$header -replace '(?i)(?:\b(?:no|na|pelo|pela|via|do)\s+)?\b(?:(?:whats\s?app|whatsap|whatssap)(?:\s+web)?|zap|discordd?|discorde)\b',''}
  if(-not $r.Platform -and $body -match '(?i)\s+(?:no|pelo|via)\s+((?:whats\s?app|whatsap|whatssap)(?:\s+web)?|zap|discordd?)\s*$'){$app=$Matches[1];$r.Platform=Get-CoveMessagePlatform $app;$body=$body -replace '(?i)\s+(?:no|pelo|via)\s+(?:(?:whats\s?app|whatsap|whatssap)(?:\s+web)?|zap|discordd?)\s*$',''}
  $r.Recipient=($header -replace '(?i)^\s*(?:para|pra|pro)\s+(?:(?:o|a)\s+)?(?:(?:(?:meu|minha)\s+)?(?:contato|amigo|amiga)\s+(?:chamad[oa]\s+)?)?','').Trim().Trim([char[]]',; ')
  $r.Body=if($body){ConvertTo-CoveMessageBody $body}else{''}
 }elseif($Dialog){
  if($key -match '^(abre|abra|entre|entra|liga|ligue|pesquisa|pesquise|que horas|qual|quem)\b'){return $r}
  $matched=$true;$r.Platform=[string]$Dialog.Platform;$r.Recipient=[string]$Dialog.Recipient;$r.Body=[string]$Dialog.Body
  switch($Dialog.Stage){'platform'{if($key -match '\b(discord|discordd|discorde)\b'){$r.Platform='Discord'}elseif($key -match '\b(whatsapp|whats app|whatsap|whatssap|zap)\b'){$r.Platform=Get-CoveMessagePlatform $text}} 'recipient'{$r.Recipient=$text.Trim()} 'body'{$r.Body=ConvertTo-CoveMessageBody $original}}
 }
 if(-not $matched){return $r};$r.Handled=$true
 if((ConvertTo-CoveAppName $r.Recipient) -in @('ela','ele','mesmo contato','mesma pessoa')){$r.Recipient=if($context){$context.Recipient}else{''}}
 if(-not $r.Platform -and $context -and (ConvertTo-CoveAppName $r.Recipient) -eq (ConvertTo-CoveAppName $context.Recipient)){$r.Platform=$context.Platform}
 if(-not $r.Recipient){$stage='recipient';$r.Message='Para qual contato?'}
 elseif(-not $r.Body){$stage='body';$r.Message='Qual mensagem devo mandar para '+$r.Recipient+'?'}
 elseif(-not $r.Platform){$stage='platform';$r.Message='Mando para '+$r.Recipient+' no WhatsApp, WhatsApp Web ou Discord?'}
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
  }else{$r.Task=[CoveApp.Messaging]::SendWhatsApp($r.Recipient,$r.Body,$script:discordCancel.Token)}
  $script:messageContext=[pscustomobject]@{Recipient=$r.Recipient;Platform=$r.Platform;Body=$r.Body;Until=[datetime]::Now.AddMinutes(20)}
 }
 return $r
}
