$ErrorActionPreference='Stop'
. "$PSScriptRoot\CoveApps.ps1"
$root=Join-Path $PSScriptRoot ('games-test-'+[guid]::NewGuid().ToString('N'))
$steam=Join-Path $root 'Steam';$library=Join-Path $root 'Library';$epic=Join-Path $root 'Epic'
$original=$script:coveAppsCache
function Start-Process {param($FilePath,$ErrorAction) $script:gameLaunched=$FilePath}
try{
 foreach($folder in @("$steam\steamapps","$library\steamapps\common\Test Game",$epic,"$root\InstalledEpic")){[IO.Directory]::CreateDirectory($folder)|Out-Null}
 [IO.File]::WriteAllText("$steam\steamapps\libraryfolders.vdf",('"libraryfolders" { "1" { "path" "'+$library.Replace('\','\\')+'" } }'))
 [IO.File]::WriteAllText("$library\steamapps\appmanifest_12345.acf",'"AppState" { "appid" "12345" "name" "Test Game" "installdir" "Test Game" }')
 [IO.File]::WriteAllText("$library\steamapps\appmanifest_999.acf",'"AppState" { "appid" "999" "name" "Not installed" "installdir" "Missing" }')
 @{DisplayName='Epic Test';AppName='TestGame123';InstallLocation="$root\InstalledEpic";bIsIncompleteInstall=$false}|ConvertTo-Json|Set-Content "$epic\test.item"
 @{DisplayName='Unsafe Test';AppName='bad?extra=1';InstallLocation="$root\InstalledEpic"}|ConvertTo-Json|Set-Content "$epic\bad.item"
 $games=@(Get-CoveInstalledGames -SteamRoots @($steam) -EpicManifests $epic)
 if($games.Count -ne 2){throw ('Expected 2 installed games: '+($games|ConvertTo-Json -Compress))}
 $script:coveAppsCache=$games
 foreach($phrase in @('abra o jogo Test Game','Cove abre Test Game','jogar Test Game')){
  $r=Invoke-CoveAppRequest $phrase -DryRun
  if($r.AppName -cne 'Test Game' -or $r.Launched -or $script:gameLaunched){throw "Game recognition/dry run: $phrase"}
 }
 Invoke-CoveAppRequest 'abre Test Game'|Out-Null
 if($script:gameLaunched -cne 'steam://rungameid/12345'){throw 'Steam launch URI'}
 Invoke-CoveAppRequest 'abre Epic Test'|Out-Null
 if($script:gameLaunched -cne 'com.epicgames.launcher://apps/TestGame123?action=launch&silent=true'){throw 'Epic launch URI'}
 foreach($uri in @('powershell.exe','steam://rungameid/1 --anything','com.epicgames.launcher://apps/bad?extra=1')){if(Test-CoveGameUri $uri){throw 'Unsafe URI accepted'}}
 'OK: secondary Steam library discovery, installed-only manifests, Epic games, natural commands, dry run and launcher routing. Real launches stubbed.'
}finally{
 $script:coveAppsCache=$original
 $resolved=[IO.Path]::GetFullPath($root);$expected=[IO.Path]::GetFullPath($PSScriptRoot)+[IO.Path]::DirectorySeparatorChar
 if($resolved.StartsWith($expected,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -match '^games-test-[0-9a-f]{32}$' -and (Test-Path -LiteralPath $resolved)){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
