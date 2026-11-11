$ErrorActionPreference='Stop'
Add-Type -Path @("$PSScriptRoot\CoveComputer.cs","$PSScriptRoot\CoveDiscord.cs","$PSScriptRoot\CoveMessaging.cs","$PSScriptRoot\Verificar-Envio-Seguro.cs") -ReferencedAssemblies UIAutomationClient,UIAutomationTypes,WindowsBase,System.Security
[CoveTests.MessageWorkflow]::Run()
