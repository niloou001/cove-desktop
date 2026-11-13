param([switch]$CloseStartupError)
$ErrorActionPreference='Stop'
Add-Type -Path "$PSScriptRoot\CoveRuntimeWindows.cs"
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
foreach($proc in Get-Process powershell){
 foreach($handle in [CoveApp.RuntimeWindows]::Handles($proc.Id,'Cove')){
  "PID: $($proc.Id)"
  $element=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$handle)
  $labels=@($element.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|ForEach-Object{$_.Current.Name})
  $labels
  if($CloseStartupError -and $labels -contains 'Nao foi possivel abrir a conexao ChatGPT protegida. Confira as permissoes da pasta Cove.'){
   [CoveApp.RuntimeWindows]::CloseCove($proc.Id)
  }
 }
}
