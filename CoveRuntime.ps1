function Get-CoveBuildId([string]$Root){
 $files=@('Cove-Voice.ps1','CoveRuntime.ps1','CoveInstance.ps1','CoveCore.cs','CoveASR.cs','CoveChatGPT.cs','CoveVoice.cs','CoveNeural.cs','CoveComputer.cs','CoveDiscord.cs','CoveApps.ps1','CoveGames.ps1','CoveMessages.ps1','CoveMessagePlanner.ps1','CoveMessaging.cs','CoveConversation.ps1','CoveDrafts.ps1','CoveOnline.ps1','CoveOnline.cs','CoveFiles.ps1','CoveControl.ps1','CoveDiscord.ps1','CoveDiscordLinks.ps1','CoveAppearance.ps1','CoveIdentity.ps1','CoveSettingsExtras.ps1','CoveAppPanel.ps1','Cove-Orb.xaml','Cove-Theme.xaml','cove_asr.py','cove_neural.py')
 $stream=New-Object IO.MemoryStream;$hash=[Security.Cryptography.SHA256]::Create()
 try{
  foreach($name in $files){$bytes=[Text.Encoding]::UTF8.GetBytes($name+"`n");$stream.Write($bytes,0,$bytes.Length);$bytes=[IO.File]::ReadAllBytes((Join-Path $Root $name));$stream.Write($bytes,0,$bytes.Length)}
  $stream.Position=0
  return ([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-','').Substring(0,12)
 }finally{$stream.Dispose();$hash.Dispose()}
}
function Get-CoveChannelPrefix([string]$Root){
 $hash=[Security.Cryptography.SHA256]::Create()
 try{$id=([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Root.ToLowerInvariant())))).Replace('-','').Substring(0,20)}finally{$hash.Dispose()}
 return 'Local\CoveDesktop.'+$id
}
function Test-CoveInstanceRunning([string]$Root){
 $mutex=$null;$owned=$false
 try{
  try{$mutex=[Threading.Mutex]::OpenExisting((Get-CoveChannelPrefix $Root)+'.Instance')}catch [Threading.WaitHandleCannotBeOpenedException]{return $false}
  try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
  return -not $owned
 }finally{if($mutex){if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}}
}
function Save-CoveReloadState([string]$Root,[string]$Transcript,[object[]]$History=@()){
 Add-Type -AssemblyName System.Security
 $raw=[Text.Encoding]::UTF8.GetBytes((@{Root=$Root;Transcript=$Transcript;History=@($History)}|ConvertTo-Json -Depth 10 -Compress))
 try{[IO.File]::WriteAllBytes((Join-Path $Root '.cove-reload-session.dat'),[Security.Cryptography.ProtectedData]::Protect($raw,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser))}finally{[Array]::Clear($raw,0,$raw.Length)}
}
function Read-CoveReloadState([string]$Root){
 $file=Join-Path $Root '.cove-reload-session.dat'
 if(-not (Test-Path -LiteralPath $file)){return $null}
 Add-Type -AssemblyName System.Security
 $raw=$null
 try{
  $raw=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($file),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  $data=[Text.Encoding]::UTF8.GetString($raw)|ConvertFrom-Json
  if($data.Root -ne $Root){return $null}
  Remove-Item -LiteralPath $file
  return $data
 }catch{return $null}finally{if($raw){[Array]::Clear($raw,0,$raw.Length)}}
}
function Write-CoveRuntime([string]$Root,[string]$Build){
 $process=[Diagnostics.Process]::GetCurrentProcess()
 try{$data=@{Pid=$process.Id;StartTicks=$process.StartTime.ToUniversalTime().Ticks;Root=$Root;Build=$Build;Features=@('discord-settings','mouse-two-monitors');Updated=[datetime]::UtcNow.ToString('o')};[IO.File]::WriteAllText((Join-Path $Root 'cove-runtime.json'),($data|ConvertTo-Json -Depth 4),[Text.Encoding]::UTF8)}finally{$process.Dispose()}
}
