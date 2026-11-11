param([switch]$Conversation)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\CoveRuntime.ps1"
$build=Get-CoveBuildId $PSScriptRoot
$record=Get-Content "$PSScriptRoot\cove-runtime.json" -Raw|ConvertFrom-Json
'Arquivos: '+$build
'Em execucao: '+$record.Build
'Atualizada: '+($build -ceq $record.Build)
if(-not $Conversation){return}
Add-Type -Path "$PSScriptRoot\CoveRuntimeWindows.cs"
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
try{
 $process=[Diagnostics.Process]::GetProcessById($record.Pid)
 if($process.StartTime.ToUniversalTime().Ticks -ne $record.StartTicks -or $record.Root -ne $PSScriptRoot){throw 'Identidade de processo desatualizada.'}
 $handles=[CoveApp.RuntimeWindows]::Handles($record.Pid,'Conversa com Cove')
 'Janelas Cove acessiveis: '+$handles.Length
 foreach($handle in $handles){
  $root=[Windows.Automation.AutomationElement]::FromHandle($handle)
  $field=$root.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'Transcript')))
  if($field){$value=$null;if($field.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern,[ref]$value)){$pairs=[regex]::Matches($value.Current.Value,'(?ms)^Voce: .*?(?=^Voce: |\z)');if($pairs.Count){$last=$pairs[$pairs.Count-1].Value;$last.Substring([Math]::Max(0,$last.Length-2000))}}}
 }
}catch{'Leitura indisponivel: '+$_.Exception.GetBaseException().Message}
