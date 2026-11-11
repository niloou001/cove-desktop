$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,UIAutomationClient,UIAutomationTypes
Add-Type -Path @("$PSScriptRoot\CoveComputer.cs","$PSScriptRoot\CoveDiscord.cs","$PSScriptRoot\CoveMessaging.cs","$PSScriptRoot\Verificar-WhatsApp-Web.cs") -ReferencedAssemblies PresentationFramework,PresentationCore,WindowsBase,UIAutomationClient,UIAutomationTypes,System.Xaml,System.Security
$result=[CoveTests.WhatsAppWebControls]::Run()
if($result -notlike 'OK:*'){throw $result}
$result
