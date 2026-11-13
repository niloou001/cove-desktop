$ErrorActionPreference='Stop'
. "$PSScriptRoot\CoveApps.ps1"
. "$PSScriptRoot\CoveMessages.ps1"
. "$PSScriptRoot\CoveMessagePlanner.ps1"
$script:messageDialog=$null;$script:messageContext=$null;$script:discordDialog=$null
foreach($phrase in @('oi','qual a diferenca entre RAM e SSD','me explica como funciona um motor','como voce esta','resuma a historia do Brasil')){
 if(-not (Test-CoveDirectConversation $phrase)){throw "Conversation delayed: $phrase"}
}
foreach($phrase in @('avisa a Ester que cheguei','da um toque nele','qual mensagem voce enviou','como enviar uma mensagem','tenta novamente por favor','escreva para Ester dizendo oi')){
 if(Test-CoveDirectConversation $phrase){throw "Action bypassed semantic route: $phrase"}
}
$script:messageDialog=[pscustomobject]@{Stage='recipient';Recipient='';Platform='Discord';Body='oi';Until=[datetime]::Now.AddMinutes(10)}
if(Test-CoveDirectConversation 'oi'){throw 'Pending message lost its context'}
$body=New-CoveSemanticRequest '{"instructions":"PRESERVE_DETAILS","input":[],"max_output_tokens":400}' 'avisa ela que cheguei'|ConvertFrom-Json
if($body.instructions -notlike '*PRESERVE_DETAILS*' -or $body.instructions -notlike '*SOMENTE JSON*'){throw 'Conversational quality or semantic format instructions lost'}
'OK: direct conversation, ambiguous actions, pending recipient and preserved instructions. No network, audio or sends.'