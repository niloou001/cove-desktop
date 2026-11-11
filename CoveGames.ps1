function Get-CoveSteamRoots {
 $paths=@()
 foreach($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')){try{$data=Get-ItemProperty -LiteralPath $key -ErrorAction Stop;foreach($value in @($data.SteamPath,$data.InstallPath)){if($value){$paths+=@($value)}}}catch{}}
 if(${env:ProgramFiles(x86)}){$paths+=@(Join-Path ${env:ProgramFiles(x86)} 'Steam')}
 return @($paths|Select-Object -Unique)
}
function Get-CoveInstalledGames {
 param([string[]]$SteamRoots=(Get-CoveSteamRoots),[string]$EpicManifests=(Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'))
 $libraries=@($SteamRoots)
 foreach($root in $SteamRoots){
  $file=Join-Path $root 'steamapps\libraryfolders.vdf'
  if(Test-Path -LiteralPath $file){foreach($match in [regex]::Matches([IO.File]::ReadAllText($file),'"path"\s+"([^"\r\n]+)"')){$libraries+=@($match.Groups[1].Value.Replace('\\','\'))}}
 }
 $seen=@{}
 foreach($library in @($libraries|Select-Object -Unique)){
  if(-not [IO.Path]::IsPathRooted($library)){continue};$apps=Join-Path $library 'steamapps'
  if(-not (Test-Path -LiteralPath $apps -PathType Container)){continue}
  foreach($file in @(Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue)){
   try{
    $text=[IO.File]::ReadAllText($file.FullName)
    if($text -notmatch '"appid"\s+"(\d+)"'){continue};$id=$Matches[1]
    if($text -notmatch '"name"\s+"([^"\r\n]+)"'){continue};$name=$Matches[1]
    if($text -notmatch '"installdir"\s+"([^"\r\n]+)"'){continue};$folder=$Matches[1]
    $common=[IO.Path]::GetFullPath((Join-Path $apps 'common'))+[IO.Path]::DirectorySeparatorChar;$installed=[IO.Path]::GetFullPath((Join-Path $common $folder))
    if(-not $installed.StartsWith($common,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $installed -PathType Container) -or $seen.ContainsKey('steam:'+ $id)){continue}
    $seen['steam:'+ $id]=$true
    [pscustomobject]@{Name=$name;Aliases=@((ConvertTo-CoveAppName $name));Path='';Arguments=@();Custom=$false;LaunchUri=('steam://rungameid/'+$id);Source='Steam'}
   }catch{}
  }
 }
 if(Test-Path -LiteralPath $EpicManifests -PathType Container){foreach($file in @(Get-ChildItem -LiteralPath $EpicManifests -Filter '*.item' -File -ErrorAction SilentlyContinue)){
  try{
   $item=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json
   if(-not $item.DisplayName -or -not $item.InstallLocation -or $item.bIsIncompleteInstall -or $item.AppName -notmatch '^[A-Za-z0-9_-]+$' -or -not (Test-Path -LiteralPath $item.InstallLocation -PathType Container)){continue}
   if($item.MainGameAppName -and $item.MainGameAppName -ne $item.AppName){continue}
   $identity=[string]$item.AppName
   if($item.CatalogNamespace -match '^[A-Za-z0-9_-]+$' -and $item.CatalogItemId -match '^[A-Za-z0-9_-]+$'){$identity=$item.CatalogNamespace+'%3A'+$item.CatalogItemId+'%3A'+$item.AppName}
   [pscustomobject]@{Name=[string]$item.DisplayName;Aliases=@((ConvertTo-CoveAppName $item.DisplayName));Path='';Arguments=@();Custom=$false;LaunchUri=('com.epicgames.launcher://apps/'+$identity+'?action=launch&silent=true');Source='Epic Games'}
  }catch{}
 }}
}
function Test-CoveGameUri([string]$Uri){return $Uri -match '^steam://rungameid/\d+$' -or $Uri -match '^com\.epicgames\.launcher://apps/[A-Za-z0-9_-]+(?:%3A[A-Za-z0-9_-]+%3A[A-Za-z0-9_-]+)?\?action=launch&silent=true$'}
