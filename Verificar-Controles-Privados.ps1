$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,UIAutomationClient,UIAutomationTypes
Add-Type -Path @("$PSScriptRoot\CoveComputer.cs","$PSScriptRoot\CoveDiscord.cs","$PSScriptRoot\CoveMessaging.cs","$PSScriptRoot\Verificar-Controles-Privados.cs") -ReferencedAssemblies PresentationFramework,PresentationCore,WindowsBase,UIAutomationClient,UIAutomationTypes,System.Xaml,System.Security
$result=[CoveTests.PrivateControls]::Run()
if($result -notlike 'OK:*'){throw $result}
$result
