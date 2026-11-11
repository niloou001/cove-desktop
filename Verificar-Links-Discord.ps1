$ErrorActionPreference='Stop'
. "$PSScriptRoot\CoveApps.ps1"
. "$PSScriptRoot\CoveDiscord.ps1"
$savedFile=$script:coveDiscordLinksFile
$testFile=Join-Path $PSScriptRoot ('links-test-'+[guid]::NewGuid().ToString('N')+'.json')
try{
 $script:coveDiscordLinksFile=$testFile
 Save-CoveDiscordLinks ([pscustomobject]@{Method='links';Channels=@()})
 $request=Resolve-CoveDiscordLinkRequest (Get-CoveDiscordRequest 'entre na call Geral no servidor CAPS')
 if(-not $request.NeedsCallLink -or $request.Action -or $request.Task){throw 'Missing link incorrectly attempted automation'}
 Add-CoveDiscordLink 'CAPS' 'Geral' 'https://discord.com/channels/123456789012345678/234567890123456789'
 Add-CoveDiscordLink 'CAPS' 'Gameplay' 'https://discord.com/channels/123456789012345678/345678901234567890'
 Add-CoveDiscordLink 'Outro' 'Geral' 'https://discord.com/channels/456789012345678901/567890123456789012'
 $data=Get-CoveDiscordLinks
 if($data.Channels.Count -ne 3 -or $data.Method -ne 'links'){throw 'Multiple destinations not saved'}
 $request=Resolve-CoveDiscordLinkRequest (Get-CoveDiscordRequest 'Cove entre no servidor chamado CAPS e entra na call geral')
 if($request.Action -ne 'join' -or $request.NeedsCallLink -or $request.Url -cne 'discord://-/channels/123456789012345678/234567890123456789'){throw 'Wrong server or channel link resolved'}
 $other=Find-CoveDiscordLink 'Outro' 'Geral'
 if($other.Url -cne 'discord://-/channels/456789012345678901/567890123456789012'){throw 'Same channel name in another server confused'}
 Add-CoveDiscordLink 'caps' 'geral' 'https://discord.com/channels/123456789012345678/678901234567890123'
 if((Get-CoveDiscordLinks).Channels.Count -ne 3){throw 'Updating a saved link created a duplicate'}
 foreach($bad in @('https://discord.gg/invite','file:///C:/Windows/System32/cmd.exe','https://discord.com.evil/channels/123456789012345678/234567890123456789')){
  $failed=$false;try{ConvertTo-CoveDiscordChannelUri $bad|Out-Null}catch{$failed=$true};if(-not $failed){throw 'Invalid link accepted'}
 }
 $data=Get-CoveDiscordLinks;$data.Method='interface';Save-CoveDiscordLinks $data
 $request=Resolve-CoveDiscordLinkRequest (Get-CoveDiscordRequest 'entre na call Nova no servidor CAPS')
 if($request.Action -ne 'join' -or $request.Url -or $request.NeedsCallLink){throw 'Optional interface mode lost'}
}finally{$script:coveDiscordLinksFile=$savedFile;if(Test-Path -LiteralPath $testFile){Remove-Item -LiteralPath $testFile}}
'OK: saved links, separate servers/channels, update, link validation, missing link and alternative mode. No Discord call opened.'
