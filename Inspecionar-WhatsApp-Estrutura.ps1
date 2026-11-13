$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,WindowsBase
Add-Type -Path @("$PSScriptRoot\CoveComputer.cs","$PSScriptRoot\CoveDiscord.cs","$PSScriptRoot\CoveMessaging.cs") -ReferencedAssemblies UIAutomationClient,UIAutomationTypes,WindowsBase,System.Security
$flags=[Reflection.BindingFlags]'Static,NonPublic'
$root=[CoveApp.Messaging].GetMethod('WebRoot',$flags).Invoke($null,@())
if(-not $root){'No WhatsApp root';return}
$doc=[CoveApp.Messaging].GetMethod('WebDocument',$flags).Invoke($null,@($root))
if(-not $doc){'No document';return}
$all=$doc.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
foreach($el in $all){
 $c=$el.Current
 if($c.IsOffscreen){continue}
 if($c.ControlType -eq [Windows.Automation.ControlType]::Edit -or ($c.IsKeyboardFocusable -and $c.ControlType -ne [Windows.Automation.ControlType]::Button)){
  $label=$c.Name
  if($label -notmatch '^(Digite|Type|Escreva|Pesquisar|Search|Nova conversa|New chat)'){$label='[label omitted]'}
  'Input: '+$c.ControlType.ProgrammaticName+' '+$label+' Bounds='+$c.BoundingRectangle
 }
}
'Picker found: '+($null -ne [CoveApp.Messaging].GetMethod('WebContactPanel',$flags).Invoke($null,@($root)))
'Composer found: '+($null -ne [CoveApp.Messaging].GetMethod('WebComposer',$flags).Invoke($null,@($root)))
