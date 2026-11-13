$ErrorActionPreference='Stop'
. "$PSScriptRoot\CoveApps.ps1"
. "$PSScriptRoot\CoveMessages.ps1"
. "$PSScriptRoot\CoveMessagePlanner.ps1"
$script:history=@();$script:messageContext=$null
foreach($dialog in @($null,[pscustomobject]@{Stage='recipient';Recipient='';Platform='Discord';Body='texto anterior';Until=[datetime]::Now.AddMinutes(10)})){
 $parsed=Get-CoveMessageRequest 'mensagem para Bielvin dizendo oi' $dialog
 if($parsed.Recipient -cne 'Bielvin' -or $parsed.Body -cne 'oi'){throw 'Whole sentence became recipient instead of splitting at dizendo'}
}
if((Resolve-CoveContactName 'Biel vim') -cne 'Bielvin'){throw 'Saved contact alias not applied'}
$request=Get-CoveMessageRequest 'mande mensagem para Biel vim no Discord dizendo Oi!'
if($request.Recipient -cne 'Bielvin' -or $request.Body -cne 'Oi!'){throw 'Alias did not reach the message recipient'}
$literal=Get-CoveMessageRequest 'mande mensagem para Ester no Discord dizendo "Biel vim"'
if($literal.Body -cne 'Biel vim'){throw 'Contact alias altered literal message text'}
$script:messageContext=[pscustomobject]@{Recipient='Bielvin';Platform='Discord';Body='Vou atrasar';Until=[datetime]::Now.AddMinutes(20)}
foreach($phrase in @('avisa o Bielvin pelo Discord que vou atrasar','da um toque nele que chego mais tarde','escreve para Bielvin no Discord: cheguei','continua com o recado para ele')){
 $body=New-CoveSemanticRequest '{"instructions":"","input":[],"max_output_tokens":400}' $phrase|ConvertFrom-Json
 $inputData=$body.input[0].content|ConvertFrom-Json
 if($inputData.request -cne $phrase -or $inputData.pendingMessage.recipient -cne 'Bielvin'){throw 'Semantic request lost current phrase or context'}
}
$decoded=ConvertFrom-CoveSemanticResponse '{"kind":"message","recipient":"Bielvin","platform":"Discord","body":"Vou atrasar","answer":""}'
$resolved=ConvertFrom-CoveMessagePlan $decoded.Text -OriginalRequest 'da um toque nele que vou atrasar'
if(-not $decoded.IsMessage -or $resolved.Action -cne 'send' -or $resolved.Recipient -cne 'Bielvin'){throw 'Semantic message did not reach local send route'}
$chat=ConvertFrom-CoveSemanticResponse '{"kind":"conversation","recipient":"","platform":"","body":"","answer":"Ola!"}'
if($chat.IsMessage -or $chat.Text -cne 'Ola!'){throw 'Conversation treated as a send'}
$failed=$false;try{ConvertFrom-CoveSemanticResponse '{"kind":"execute","recipient":"Bielvin","platform":"Discord","body":"oi","answer":""}'}catch{$failed=$true}
if(-not $failed){throw 'Invalid semantic action accepted'}
'OK: saved contact aliases, literal text preserved, natural request context, semantic message routing, conversation separation and invalid response rejection. No real model call or send.'
