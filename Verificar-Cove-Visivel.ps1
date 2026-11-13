$ErrorActionPreference='Stop'
Add-Type -Path "$PSScriptRoot\CoveRuntimeWindows.cs"
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,WindowsBase
Add-Type 'using System;using System.Runtime.InteropServices;public static class CoveVisibilityCheck{[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();}'
$until=[datetime]::UtcNow.AddSeconds(20)
do{
 $runtime=$null
 try{$runtime=Get-Content -LiteralPath "$PSScriptRoot\cove-runtime.json" -Raw|ConvertFrom-Json}catch{}
 if($runtime){
  $handles=[CoveApp.RuntimeWindows]::Handles($runtime.Pid,'Conversa com Cove')
  foreach($handle in $handles){
   $element=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$handle)
   if(-not $element.Current.IsOffscreen -and -not $element.Current.BoundingRectangle.IsEmpty){
    'Conversa visivel: True'
    'Posicao: '+$element.Current.BoundingRectangle
    'Em primeiro plano: '+([CoveVisibilityCheck]::GetForegroundWindow().ToInt64() -eq $handle)
    $windowPattern=$null
    if($element.TryGetCurrentPattern([Windows.Automation.WindowPattern]::Pattern,[ref]$windowPattern)){'Acima das outras janelas: '+$windowPattern.Current.IsTopmost}
    exit 0
   }
  }
 }
 Start-Sleep -Milliseconds 250
}while([datetime]::UtcNow -lt $until)
throw 'A conversa do Cove nao foi encontrada visivel.'
