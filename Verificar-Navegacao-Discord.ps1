$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,UIAutomationClient,UIAutomationTypes
Add-Type -Path @("$PSScriptRoot\CoveComputer.cs","$PSScriptRoot\CoveDiscord.cs","$PSScriptRoot\CoveMessaging.cs","$PSScriptRoot\Verificar-Navegacao-Discord.cs") -ReferencedAssemblies PresentationFramework,PresentationCore,WindowsBase,UIAutomationClient,UIAutomationTypes,System.Xaml,System.Security
foreach($mode in @(@($false,$false),@($true,$false),@($false,$true))){
 $result=[CoveTests.DiscordNavigation]::Run($mode[0],$mode[1])
 if($result -notlike 'OK:*'){throw $result}
 $result
}
$result=[CoveTests.DiscordNavigation]::Run($false,$true,$true)
if($result -notlike 'OK:*'){throw $result}
$result
$result=[CoveTests.DiscordNavigation]::Run($false,$true,$true,$true)
if($result -notlike 'OK:*'){throw $result}
$result
$result=[CoveTests.DiscordNavigation]::Run($true,$false,$false,$false,$true)
if($result -notlike 'OK:*'){throw $result}
$result
