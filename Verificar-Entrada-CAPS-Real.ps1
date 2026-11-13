$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,WindowsBase,System.Security
Add-Type -Path @("$PSScriptRoot\CoveComputer.cs","$PSScriptRoot\CoveDiscord.cs","$PSScriptRoot\CoveMessaging.cs") -ReferencedAssemblies UIAutomationClient,UIAutomationTypes,WindowsBase,System.Security
[CoveApp.DiscordCall]::DiagnosticFile=Join-Path $PSScriptRoot 'cove-discord-diagnostico.log'
$cancel=New-Object Threading.CancellationTokenSource
$cancel.CancelAfter(90000)
try{[CoveApp.DiscordCall]::Join('', 'CAPS', 'geral', $cancel.Token).GetAwaiter().GetResult()}
finally{$cancel.Dispose()}