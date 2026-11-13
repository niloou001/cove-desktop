$ErrorActionPreference='Stop'
. "$PSScriptRoot\CoveApps.ps1"
. "$PSScriptRoot\CoveShortcuts.ps1"
foreach($phrase in @('pause o microfone','pausa o microfone do Cove','desative meu mic','pare de me ouvir','nao me escute agora','Cove, pode pausar o microfone por favor')){
 $request=Get-CoveMicrophoneRequest $phrase
 if(-not $request.Handled -or -not $request.Paused){throw "Pause not recognized: $phrase"}
}
foreach($phrase in @('retomar microfone','ative o microfone do Cove','volte a me ouvir','me escutar de novo')){
 $request=Get-CoveMicrophoneRequest $phrase
 if(-not $request.Handled -or $request.Paused){throw "Resume not recognized: $phrase"}
}
foreach($phrase in @('como pausar o microfone','nao pause o microfone','mande mensagem para Ester dizendo pause o microfone','se eu pausar o microfone')){if((Get-CoveMicrophoneRequest $phrase).Handled){throw "Non-command interpreted: $phrase"}}
$tokens=$null;$issues=$null;$ast=[Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot\Cove-Voice.ps1",[ref]$tokens,[ref]$issues)
if($issues.Count){throw ($issues|Out-String)}
foreach($name in @('Ask-Cove','Set-CoveMicrophonePaused','Toggle-Microphone','Update-Capture','Update-CoveShortcutLabels')){
 $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
 . ([scriptblock]::Create($node.Extent.Text))
}
function Add-Message {param($Who,$Text)}
function Say {param($Text)}
$muteButton=[pscustomobject]@{Content='';ToolTip=''};$heardLabel=[pscustomobject]@{Text=''};$sendButton=[pscustomobject]@{IsEnabled=$true}
$script:assistantName='Cove';$script:muted=$false;$script:state='Listening';$script:cooldown=[datetime]::MinValue
$script:listener=[pscustomobject]@{Paused=$false;ListeningMode=$true}
$script:task=[pscustomobject]@{Busy=$true}
Ask-Cove 'pause o microfone'
if(-not $script:muted -or -not $script:listener.Paused -or $script:state -ne 'Idle'){throw 'Pause must work locally even while another task is busy'}
Ask-Cove 'pause o microfone'
if(-not $script:muted){throw 'Repeated pause toggled the microphone back on'}
$script:task=$null
Ask-Cove 'retome o microfone'
if($script:muted -or $script:listener.Paused){throw 'Local resume failed'}
Toggle-Microphone
if(-not $script:muted){throw 'Button/keyboard toggle failed'}
'OK: natural pause/resume, negation, message text exclusion, busy task, idempotent pause and local listener state. No Windows audio changes or model calls.'
