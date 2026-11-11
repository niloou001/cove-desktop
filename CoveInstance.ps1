function Open-CoveInstanceChannel([string]$Identity,[switch]$Listen,[switch]$DiscordSettings){
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$id=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Identity.ToLowerInvariant())))).Replace('-','').Substring(0,20)}finally{$sha.Dispose()}
 $prefix='Local\CoveDesktop.'+$id
 $show=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::AutoReset,($prefix+'.Show'))
 $hear=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::AutoReset,($prefix+'.Listen'))
 $reload=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::AutoReset,($prefix+'.Reload'))
 $settings=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::AutoReset,($prefix+'.DiscordSettings'))
 $created=$false
 $mutex=New-Object Threading.Mutex($true,($prefix+'.Instance'),[ref]$created)
 if(-not $created){if($DiscordSettings){$settings.Set()|Out-Null}elseif($Listen){$hear.Set()|Out-Null}else{$show.Set()|Out-Null}}
 return [pscustomobject]@{AlreadyRunning=(-not $created);Owned=$created;Mutex=$mutex;Show=$show;Listen=$hear;Reload=$reload;DiscordSettings=$settings}
}
function Close-CoveInstanceChannel($Channel){
 if(-not $Channel){return}
 if($Channel.Owned){try{$Channel.Mutex.ReleaseMutex()}catch{}}
 $Channel.Mutex.Dispose();$Channel.Show.Dispose();$Channel.Listen.Dispose();$Channel.Reload.Dispose();$Channel.DiscordSettings.Dispose()
}
