param([switch]$Live)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\CoveApps.ps1"
. "$PSScriptRoot\CoveOnline.ps1"
Add-Type -Path "$PSScriptRoot\CoveOnline.cs" -ReferencedAssemblies System.Net.Http,System.Web.Extensions,System.Xml
$script:coveOnlineFile=Join-Path $PSScriptRoot ('online-test-'+[guid]::NewGuid().ToString('N')+'.json')
$script:launched=@()
function Get-CoveChromePath {return 'C:\fixture\chrome.exe'}
function Start-Process {param($FilePath,$ArgumentList,$ErrorAction) $script:launched+=@([pscustomobject]@{Path=$FilePath;Url=$ArgumentList})}
try{
 foreach($phrase in @('Cove que horas sao','qual o horario agora','que dia e hoje','noticias de hoje','me fale as ultimas noticias')){if(-not (Invoke-CoveOnlineRequest $phrase -DryRun).Handled){throw "Not handled: $phrase"}}
 $r=Invoke-CoveOnlineRequest 'que horas sao' -DryRun
 if($r.Task -or $r.Message -notlike ('*'+(Get-Date -Format 'HH:mm')+'*')){throw 'Clock must use Windows without network'}
 foreach($phrase in @('pesquise sobre C# e C++ no Chrome','faz uma pesquisa sobre cafe','procura na internet aves brasileiras')){
  $r=Invoke-CoveOnlineRequest $phrase -DryRun
  if($r.Kind -ne 'search' -or $r.Url -notlike 'https://www.google.com/search?q=*' -or $script:launched.Count){throw "Unsafe preview $phrase"}
 }
 $query='cafe & x="teste" $(nao-executar)'
 $r=Invoke-CoveOnlineRequest ('pesquise '+$query)
 if($script:launched.Count -ne 1 -or [uri]::UnescapeDataString(($script:launched[0].Url -split '\?q=',2)[1]) -cne $query){throw 'Query encoding/launch failed'}
 foreach($phrase in @('nao pesquise joao','como pesquisar algo','explique temperatura','o que e temperatura')){if((Get-CoveOnlineRequest $phrase).Handled){throw "Indirect request $phrase"}}
 $r=Invoke-CoveOnlineRequest 'qual a temperatura agora' -DryRun
 if(-not $r.AwaitReply -or $r.Task -or (Test-Path $script:coveOnlineFile)){throw 'Missing location'}
 Invoke-CoveOnlineRequest 'minha cidade e Curitiba, Parana'|Out-Null
 $r=Invoke-CoveOnlineRequest 'quantos graus esta' -DryRun
 if($r.City -cne 'Curitiba, Parana' -or $r.Task){throw 'Saved city not used'}
 $r=Invoke-CoveOnlineRequest 'qual a temperatura em Recife agora' -DryRun
 if($r.City -cne 'Recife'){throw 'Explicit city not used'}
 $now=[datetime]::UtcNow;$stamp=$now.ToString('yyyy-MM-ddTHH:mm')
 $weather='{"current":{"temperature_2m":23.5,"time":"'+$stamp+'"},"utc_offset_seconds":0}'
 if([CoveApp.Online]::FormatWeather('Teste',$weather) -notlike '*23,5*'){throw 'Weather parsing'}
 $bad=$weather.Replace($stamp,$now.AddDays(-1).ToString('yyyy-MM-ddTHH:mm'));$rejected=$false
 try{[CoveApp.Online]::FormatWeather('Teste',$bad)|Out-Null}catch{$rejected=$true}
 if(-not $rejected){throw 'Stale weather accepted'}
 $date=$now.ToString('r',[Globalization.CultureInfo]::InvariantCulture);$old=$now.AddDays(-4).ToString('r',[Globalization.CultureInfo]::InvariantCulture)
 $xml='<rss><channel><item><title>Manchete teste</title><link>https://www.bbc.com/portuguese/articles/teste</link><pubDate>'+$date+'</pubDate></item><item><title>Antiga</title><link>https://www.bbc.com/antiga</link><pubDate>'+$old+'</pubDate></item><item><title>Externa</title><link>https://example.com/</link><pubDate>'+$date+'</pubDate></item></channel></rss>'
 $news=[CoveApp.Online]::FormatNews($xml,$now)
 if($news -notlike '*Manchete teste*' -or $news -like '*Antiga*' -or $news -like '*Externa*' -or $news -notlike '*https://www.bbc.com*'){throw 'News dates/source/links'}
 'OK: Windows clock, city preference, explicit city, Chrome launch stub, query encoding, dry-run without effects, current weather parsing, stale weather rejection, news dates and source links.'
 if($Live){
  $watch=[Diagnostics.Stopwatch]::StartNew();[CoveApp.Online]::Weather('Curitiba, Parana',[Threading.CancellationToken]::None).GetAwaiter().GetResult();'Weather elapsed ms: '+$watch.ElapsedMilliseconds
  $watch.Restart();[CoveApp.Online]::News([Threading.CancellationToken]::None).GetAwaiter().GetResult();'News elapsed ms: '+$watch.ElapsedMilliseconds
 }
}finally{if(Test-Path -LiteralPath $script:coveOnlineFile){Remove-Item -LiteralPath $script:coveOnlineFile}}
