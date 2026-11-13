$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,WindowsBase
Add-Type -Path @("$PSScriptRoot\CoveComputer.cs","$PSScriptRoot\CoveDiscord.cs","$PSScriptRoot\CoveMessaging.cs") -ReferencedAssemblies UIAutomationClient,UIAutomationTypes,WindowsBase,System.Security
$flags=[Reflection.BindingFlags]'Static,NonPublic'
$type=[CoveApp.DiscordCall]
$root=$type.GetMethod('Root',$flags).Invoke($null,@())
if(-not $root){'No accessible Discord window';exit 0}
$argsList=[object[]]@($root,$null)
$field=$type.GetMethod('PickerField',$flags).Invoke($null,$argsList)
$picker=$argsList[1]
if(-not $picker){'No open quick switch picker';exit 0}
foreach($item in $picker.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)){
 $c=$item.Current
 if($c.IsOffscreen -or $c.ControlType -eq [Windows.Automation.ControlType]::Edit -or $c.ControlType -eq [Windows.Automation.ControlType]::ComboBox){continue}
 if($c.Name -match '(?i)biel|user|usu.rio|direct message|mensagem direta|server|servidor'){
  $c.ControlType.ProgrammaticName+' | '+$c.Name+' | '+$c.AutomationId+' | '+$c.HelpText+' | '+$c.ItemType+' | '+$c.BoundingRectangle
 }
}
