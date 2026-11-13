$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
. "$PSScriptRoot\CoveShortcuts.ps1"
$file=Join-Path $PSScriptRoot ('shortcuts-test-'+[guid]::NewGuid().ToString('N')+'.json')
try{
 $settings=Get-CoveShortcutSettings $file
 $ctrlShift=[Windows.Input.ModifierKeys]::Control -bor [Windows.Input.ModifierKeys]::Shift
 $ctrlAlt=[Windows.Input.ModifierKeys]::Control -bor [Windows.Input.ModifierKeys]::Alt
 if((Get-CoveShortcutAction $settings M $ctrlShift) -ne 'Microphone'){throw 'Default microphone shortcut failed'}
 $saved=Save-CoveShortcutSettings 'Ctrl+Alt+P' 'F8' $file
 $loaded=Get-CoveShortcutSettings $file
 if($loaded.Microphone -ne $saved.Microphone -or $loaded.ClearConversation -ne 'F8'){throw 'Settings did not persist'}
 if(Get-CoveShortcutAction $loaded M $ctrlShift){throw 'Previous key combination still active'}
 if((Get-CoveShortcutAction $loaded P $ctrlAlt) -ne 'Microphone'){throw 'Custom microphone combination failed'}
 if((Get-CoveShortcutAction $loaded F8 ([Windows.Input.ModifierKeys]::None)) -ne 'ClearConversation'){throw 'Custom clear combination failed'}
 $before=[IO.File]::ReadAllText($file);$rejected=$false
 try{Save-CoveShortcutSettings 'Ctrl+M' 'Ctrl+M' $file|Out-Null}catch{$rejected=$true}
 if(-not $rejected -or [IO.File]::ReadAllText($file) -cne $before){throw 'Duplicate bindings changed saved configuration'}
 $settings=Save-CoveShortcutSettings '' '' $file
 if((Get-CoveShortcutSettings $file).Microphone -or (Get-CoveShortcutSettings $file).ClearConversation){throw 'Disabled shortcuts not saved'}
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot\Cove-Voice.ps1",[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ($errors|Out-String)}
 $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Clear-CoveConversation'},$true)
 . ([scriptblock]::Create($node.Extent.Text))
 function Update-Capture {}
 $voiceEngine=[pscustomobject]@{};$voiceEngine|Add-Member ScriptMethod Stop {}
 $transcript=[pscustomobject]@{Text='Fixture conversation'};$transcript|Add-Member ScriptMethod Clear {$this.Text=''}
 $script:speechQueue=New-Object 'Collections.Generic.Queue[string]';$script:speechQueue.Enqueue('old speech')
 $script:history=@(@{role='user';content='old message'});$script:messageContext=[pscustomobject]@{Body='old draft'};$script:messageDialog=[pscustomobject]@{Stage='recipient'};$script:pendingMessageText='old confirmation'
 $script:discordTask=[pscustomobject]@{Busy=$true}
 if((Clear-CoveConversation) -or -not $transcript.Text){throw 'Busy action was interrupted or conversation unexpectedly erased'}
 $script:discordTask=$null
 if(-not (Clear-CoveConversation) -or $transcript.Text -or $script:history.Count -or $script:messageContext -or $script:messageDialog -or $script:pendingMessageText -or $script:speechQueue.Count){throw 'Conversation clear left stale message context'}
 'OK: custom keys, persistence, previous binding removed, duplicate rejection, disabled bindings, busy task preserved and conversation context cleared.'
}finally{if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}}
