$ErrorActionPreference='Stop'
Add-Type -Path @("$PSScriptRoot\CoveComputer.cs","$PSScriptRoot\CoveDiscord.cs","$PSScriptRoot\CoveMessaging.cs") -ReferencedAssemblies UIAutomationClient,UIAutomationTypes,WindowsBase,System.Security
Add-Type -AssemblyName PresentationFramework,PresentationCore
$source=[IO.File]::ReadAllText("$PSScriptRoot\CoveDrafts.ps1");$begin=$source.IndexOf('<Window ');$end=$source.IndexOf("'@)",$begin)
$view=[Windows.Markup.XamlReader]::Parse($source.Substring($begin,$end-$begin))
if(-not $view.FindName('DraftList') -or -not $view.FindName('DraftText').IsReadOnly -or -not $view.FindName('CopyDraft')){throw 'Draft recovery UI missing'}
$view.Close()
$root=Join-Path $PSScriptRoot ('draft-test-'+[guid]::NewGuid().ToString('N'));[CoveApp.Messaging]::DraftDirectory=$root
try{
 try{[Security.Cryptography.ProtectedData]::Protect([byte[]]@(1,2,3),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)|Out-Null}catch{if($_.Exception.GetBaseException() -is [Security.Cryptography.CryptographicException]){'OK: recovery UI parsed. Protected draft roundtrip NOT verified: Windows user profile DPAPI unavailable.';return};throw}
 [CoveApp.Messaging]::BackupDraft('Discord','Fixture contact','Fixture private draft')
 $files=@(Get-ChildItem -LiteralPath $root -Filter '*.dat' -File)
 if($files.Count -ne 1 -or [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($files[0].FullName)).Contains('Fixture private draft')){throw 'Draft not encrypted'}
 $saved=@([CoveApp.Messaging]::ReadSavedDrafts())
 if($saved.Count -ne 1 -or $saved[0].Text -cne 'Fixture private draft' -or $saved[0].Recipient -cne 'Fixture contact'){throw 'Draft recovery roundtrip'}
 'OK: draft encrypted before replacement, binary recovery roundtrip and recovery UI. Test data only.'
}finally{
 if(Test-Path -LiteralPath $root){foreach($file in Get-ChildItem -LiteralPath $root -File){Remove-Item -LiteralPath $file.FullName};Remove-Item -LiteralPath $root}
}
