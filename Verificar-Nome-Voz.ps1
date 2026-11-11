$ErrorActionPreference='Stop'
. "$PSScriptRoot\CoveApps.ps1"
. "$PSScriptRoot\CoveIdentity.ps1"
Add-Type -Path @("$PSScriptRoot\CoveCore.cs","$PSScriptRoot\CoveASR.cs") -ReferencedAssemblies System.Net.Http,System.Web.Extensions
$script:assistantName='Luma';$script:assistantWakePattern=Get-CoveWakePattern 'Luma'
if(-not [CoveApp.Listener]::WakeMatches('oi luma','Luma') -or [CoveApp.Listener]::WakeMatches('iluminacao','Luma') -or [CoveApp.Listener]::WakeMatches('oi cove','Luma')){throw 'Custom wake boundaries'}
if(-not [CoveApp.Listener]::WakeMatches('ola marcia','Marcia') -or -not [CoveApp.Listener]::WakeMatches('oi jarvis','J.A.R.V.I.S')){throw 'Wake aliases'}
if(-not [CoveApp.Listener]::WakeMatches('jarbas','Jarvis')){throw 'Portuguese model pronunciation alias missing'}
if((ConvertTo-CoveRequestLanguage 'Luma, abra o Discord') -cne 'abra o Discord'){throw 'Renamed command prefix'}
$source=[IO.File]::ReadAllText("$PSScriptRoot\Cove-Voice.ps1");$tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw ($errors|Out-String)}
if($source -match '\$hasWake=\$text -match ''\(\?i\)\\b\(cove\|'){throw 'Hardcoded wake still active'}
'OK: custom wake name, whole-word boundary, old name rejected after rename, aliases, command prefix and syntax. No microphone used.'
