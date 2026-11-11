$script:coveDiscordLinksFile=Join-Path $PSScriptRoot 'cove-discord-links.json'
function Get-CoveDiscordLinks {
 if(Test-Path -LiteralPath $script:coveDiscordLinksFile){
  try{$data=Get-Content -LiteralPath $script:coveDiscordLinksFile -Raw|ConvertFrom-Json;return [pscustomobject]@{Method=if($data.Method -in @('mouse','interface','links')){[string]$data.Method}else{'mouse'};Channels=@($data.Channels|Where-Object{$_})}}catch{throw 'Nao consegui ler os links salvos do Discord.'}
 }
 return [pscustomobject]@{Method='mouse';Channels=@()}
}
function Save-CoveDiscordLinks($Data){
 [IO.File]::WriteAllText($script:coveDiscordLinksFile,($Data|ConvertTo-Json -Depth 5),[Text.Encoding]::UTF8)
}
function ConvertTo-CoveDiscordChannelUri([string]$Link){
 if($Link.Trim() -notmatch '^https://(?:www\.)?discord\.com/channels/(\d{15,22})/(\d{15,22})/?$'){throw 'Cole o link de um canal de voz: https://discord.com/channels/servidor/canal.'}
 return 'discord://-/channels/'+$Matches[1]+'/'+$Matches[2]
}
function Add-CoveDiscordLink([string]$Server,[string]$Channel,[string]$Link){
 $Server=$Server.Trim();$Channel=$Channel.Trim()
 if(-not $Server -or -not $Channel -or $Server.Length -gt 100 -or $Channel.Length -gt 100){throw 'Informe o nome do servidor e o nome da call.'}
 $uri=ConvertTo-CoveDiscordChannelUri $Link
 $data=Get-CoveDiscordLinks;$serverKey=ConvertTo-CoveAppName $Server;$channelKey=ConvertTo-CoveAppName $Channel
 $data.Channels=@($data.Channels|Where-Object{(ConvertTo-CoveAppName $_.Server) -ne $serverKey -or (ConvertTo-CoveAppName $_.Channel) -ne $channelKey})
 $data.Channels+=@([pscustomobject]@{Server=$Server;Channel=$Channel;Link=$Link.Trim();Url=$uri;Name=$Server+' / '+$Channel})
 $data.Method='links';Save-CoveDiscordLinks $data
}
function Find-CoveDiscordLink([string]$Server,[string]$Channel){
 $data=Get-CoveDiscordLinks
 return @($data.Channels|Where-Object{(ConvertTo-CoveAppName $_.Server) -eq (ConvertTo-CoveAppName $Server) -and (ConvertTo-CoveAppName $_.Channel) -eq (ConvertTo-CoveAppName $Channel)})|Select-Object -First 1
}
function Resolve-CoveDiscordLinkRequest($Request){
 if($Request.Action -ne 'join'){return $Request}
 $data=Get-CoveDiscordLinks
 $Request.NavigationMode=$data.Method
 if($Request.Url -or $data.Method -in @('mouse','interface')){return $Request}
 $saved=Find-CoveDiscordLink $Request.Server $Request.Channel
 if(-not $saved){
  $Request.Action='';$Request.NeedsCallLink=$true
  $Request.Message='Preciso do link da call '+$Request.Channel+' no servidor '+$Request.Server+' uma unica vez. Salve em Ajustes, Calls do Discord: links salvos.'
  return $Request
 }
 $Request.Url=ConvertTo-CoveDiscordChannelUri $saved.Link
 $Request.Message='Abrindo o link da call '+$Request.Channel+' no servidor '+$Request.Server+'.'
 return $Request
}
