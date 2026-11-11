$script:coveAppsFile=Join-Path $PSScriptRoot 'cove-apps.json'
$script:coveAppsCache=$null
. (Join-Path $PSScriptRoot 'CoveGames.ps1')
function ConvertTo-CoveAppName([string]$text){
 $normalized=$text.Normalize([Text.NormalizationForm]::FormD)
 $builder=New-Object Text.StringBuilder
 foreach($character in $normalized.ToCharArray()){if([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne [Globalization.UnicodeCategory]::NonSpacingMark){[void]$builder.Append($character)}}
 return ([regex]::Replace($builder.ToString().ToLowerInvariant(),'[^a-z0-9 ]',' ') -replace '\s+',' ').Trim()
}
function ConvertTo-CoveRequestLanguage([string]$text){
 $text=$text.Trim().TrimEnd([char[]]'.!?')
 for($i=0;$i -lt 4;$i++){
  if($script:assistantWakePattern){$text=$text -replace ('(?i)^(?:(?:oi|ola|olá)\s+)?'+$script:assistantWakePattern+'[, :]+'),''}
  $text=$text -replace '(?i)^(?:(?:oi|ola|olá)\s+)?(?:cove|couve|couvi)[, :]+',''
  $text=$text -replace '(?i)^(?:mano|cara|olha|entao|então|ei|por favor|faz favor|por gentileza)[, :]+',''
  $text=$text -replace '(?i)^(?:(?:voce|você|vc|ce|cê)\s+)?(?:pode|poderia|consegue|conseguiria|tem como|da pra|dá pra|da para|dá para)\s+',''
  $text=$text -replace '(?i)^(?:eu\s+)?(?:quero|queria|gostaria|preciso)\s+(?:(?:que\s+(?:(?:voce|você|vc)\s+)?)|de\s+)?',''
  $text=$text -replace '(?i)^(?:voce|você|vc)\s+(?=(?:me\s+)?(?:entra|entrar|entre|abra|abre|abrir|coloca|coloque|colocasse|colocar|bota|bote|botar|inicia|inicie)\b)',''
  $text=$text -replace '(?i)^((?:me\s+)?(?:entra|entrar|entre|abra|abre|abrir|coloca|coloque|bota|bote|inicia|inicie))\s+(?:pra mim|para mim)\s+','$1 '
  $text=($text -replace '(?i)[, ]+(?:por favor|por gentileza|pra mim|para mim|agora|ai|aí)[.!? ]*$','').Trim()
 }
 return $text
}
function Get-CoveAppRequest([string]$text){
 $text=ConvertTo-CoveRequestLanguage $text
 if($text -match '(?i)^\s*(?:abra|abre|abrir|inicie)\s+"?([a-z]:\\[^"\r\n]+\.(?:exe|lnk))"?\s*$'){
  return [pscustomobject]@{Kind='open';Target=$Matches[1];DirectPath=$Matches[1]}
 }
 $text=ConvertTo-CoveAppName $text
 $text=$text -replace '^(?:joga|jogar|jogue)\s+','abre '
 $text=$text -replace '^(abre|abra|abrir|inicie|inicia|iniciar)\s+(?:(?:o|a)\s+)?(?:jogo|game)\s+','$1 '
 $text=$text -replace '^(oi |ola )?(cove|couve|couvi) ',' '
 $text=$text.Trim()
 if($text -match '^(atualizar|atualize|atualiza) (?:a )?(?:lista de )?(jogos|apps|aplicativos)$'){return [pscustomobject]@{Kind='refresh';Target=''}}
 $text=$text -replace '^(mano|cara|olha|entao|ei) ',' '
 $text=$text.Trim()
 if($text -match '^(quais (apps|aplicativos|programas)( voce)? (pode|consegue) abrir|liste (os )?(apps|aplicativos)|mostrar aplicativos)$'){return [pscustomobject]@{Kind='list';Target=''}}
 $text=$text -replace '^(por favor |faz favor )',''
 $text=$text -replace '^(voce )?(pode|poderia|consegue|conseguiria) (por favor|por gentileza) ','$1$2 '
 $prefix='^(?:(?:(?:voce )?(?:pode|consegue|poderia|conseguiria)|tem como|da para|da pra) |(?:eu )?(?:quero|queria|gostaria) que (?:voce )?|(?:eu )?(?:quero|queria|gostaria de) )?(?:me )?(?:abra|abre|abrir|abrisse|inicie|inicia|iniciar|usar|use|rodar|rode|executa|execute|executar|liga|ligar|bota|botar|coloca|coloque)(?: (?:pra mim|para mim))?(?: (?:o|a|os|as|meu|minha))?(?: (?:app|aplicativo|programa))? (.+)$'
 if($text -notmatch $prefix){return $null}
 $target=$Matches[1]
 for($i=0;$i -lt 3;$i++){$target=$target -replace ' (por favor|por gentileza|pra mim|para mim|agora|ai)$',''}
 $target=$target.Trim()
 if(-not $target){return $null}
 return [pscustomobject]@{Kind='open';Target=$target}
}
function Get-CoveNameDistance([string]$a,[string]$b){
 $previous=New-Object int[] ($b.Length+1)
 for($j=0;$j -le $b.Length;$j++){$previous[$j]=$j}
 for($i=1;$i -le $a.Length;$i++){
  $current=New-Object int[] ($b.Length+1);$current[0]=$i
  for($j=1;$j -le $b.Length;$j++){
   $cost=1;if($a[$i-1] -eq $b[$j-1]){$cost=0}
   $current[$j]=[Math]::Min([Math]::Min($current[$j-1]+1,$previous[$j]+1),$previous[$j-1]+$cost)
  };$previous=$current
 };return $previous[$b.Length]
}
function Get-CoveAppSuggestion([string]$target,[object[]]$apps){
 # Approximate names are suggestions only; never launch them automatically.
 if($target.Length -lt 4 -or $target.Length -gt 35 -or $target -match '\b(e|depois|com|argumentos|execute|apague)\b'){return $null}
 $candidates=@()
 foreach($app in $apps){
  $best=100
  foreach($alias in $app.Aliases){$distance=Get-CoveNameDistance ($target -replace ' ','') ($alias -replace ' ','');if($distance -lt $best){$best=$distance}}
  if($best -le 2){$candidates+=@([pscustomobject]@{App=$app;Distance=$best})}
 }
 $ranked=@($candidates|Sort-Object Distance)
 if($ranked.Count -eq 1 -or ($ranked.Count -gt 1 -and $ranked[0].Distance -lt $ranked[1].Distance)){return $ranked[0].App}
 return $null
}
function Get-CoveApplications {
 if($null -ne $script:coveAppsCache){return @($script:coveAppsCache)}
 $items=New-Object 'Collections.Generic.List[object]'
 $definitions=@(
  @{Name='Discord';Aliases=@('discord','discorde','disco','disco rd');Files=@('Discord.lnk');Path=(Join-Path $env:LOCALAPPDATA 'Discord\Update.exe');Arguments=@('--processStart','Discord.exe')},
  @{Name='Spotify';Aliases=@('spotify','spotfy','spot fai');Files=@('Spotify.lnk');Path=(Join-Path $env:APPDATA 'Spotify\Spotify.exe')},
  @{Name='Steam';Aliases=@('steam','stim');Files=@('Steam.lnk')},
  @{Name='Chrome';Aliases=@('chrome','google chrome','google','crome');Files=@('Google Chrome.lnk');AppPath='chrome.exe'},
  @{Name='Edge';Aliases=@('edge','microsoft edge','edgi');Files=@('Microsoft Edge.lnk');AppPath='msedge.exe'},
  @{Name='Firefox';Aliases=@('firefox','mozilla firefox');Files=@('Firefox.lnk');AppPath='firefox.exe'},
  @{Name='WhatsApp';Aliases=@('whatsapp','whats app','zap');Files=@('WhatsApp.lnk')},
  @{Name='Telegram';Aliases=@('telegram','telegrama');Files=@('Telegram.lnk')},
  @{Name='Visual Studio Code';Aliases=@('visual studio code','vs code','vscode','code');Files=@('Visual Studio Code.lnk');Path=(Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe')},
  @{Name='Bloco de notas';Aliases=@('bloco de notas','notepad');Files=@();Path=(Join-Path $env:WINDIR 'System32\notepad.exe')},
  @{Name='Calculadora';Aliases=@('calculadora','calc');Files=@();Path=(Join-Path $env:WINDIR 'System32\calc.exe')},
  @{Name='Explorador de arquivos';Aliases=@('explorador','explorador de arquivos','explorer','arquivos');Files=@();Path=(Join-Path $env:WINDIR 'explorer.exe')}
 )
 $shortcuts=@()
 foreach($folder in @([Environment]::GetFolderPath('StartMenu'),[Environment]::GetFolderPath('CommonStartMenu'))){if($folder -and (Test-Path -LiteralPath $folder)){$shortcuts+=@(Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -Recurse -File -ErrorAction SilentlyContinue)}}
 foreach($definition in $definitions){
  $path='';$arguments=@()
  $shortcut=$shortcuts|Where-Object{$definition.Files -contains $_.Name}|Select-Object -First 1
  if($definition.Path -and (Test-Path -LiteralPath $definition.Path -PathType Leaf)){$path=$definition.Path;if($definition.Arguments){$arguments=$definition.Arguments}}
  elseif($shortcut){$path=$shortcut.FullName}
  elseif($definition.AppPath){
   foreach($hive in @('HKEY_CURRENT_USER','HKEY_LOCAL_MACHINE')){
    $key='Registry::'+$hive+'\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\'+$definition.AppPath
    try{$candidate=(Get-Item -LiteralPath $key -ErrorAction Stop).GetValue('');if($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)){$path=$candidate;break}}catch{}
   }
  }
  if($path){$items.Add([pscustomobject]@{Name=$definition.Name;Aliases=$definition.Aliases;Path=$path;Arguments=@($arguments);Custom=$false})}
 }
 if(Test-Path -LiteralPath $script:coveAppsFile){
  try{
   $saved=@(Get-Content -LiteralPath $script:coveAppsFile -Raw|ConvertFrom-Json)
   foreach($app in $saved){
    $name=ConvertTo-CoveAppName ([string]$app.Name)
    $extension=[IO.Path]::GetExtension([string]$app.Path).ToLowerInvariant()
    if($name -and $extension -in @('.exe','.lnk') -and [IO.Path]::IsPathRooted([string]$app.Path)){
     $items.Add([pscustomobject]@{Name=[string]$app.Name;Aliases=@($name);Path=[string]$app.Path;Arguments=@();Custom=$true})
    }
   }
  }catch{}
 }
 foreach($found in @((Get-CoveInstalledGames)) + @(Get-CoveDiscoveredApps)){
  $alias=ConvertTo-CoveAppName $found.Name
  if($alias -and -not @($items|Where-Object{$_.Aliases -contains $alias}).Count){$items.Add($found)}
 }
 $script:coveAppsCache=@($items.ToArray());return @($script:coveAppsCache)
}
function Save-CoveCustomApps([object[]]$apps){
 $data=@($apps|Where-Object{$_.Custom}|ForEach-Object{@{Name=$_.Name;Path=$_.Path}})
 $json=ConvertTo-Json -InputObject $data -Depth 4
 [IO.File]::WriteAllText($script:coveAppsFile,$json,[Text.Encoding]::UTF8);$script:coveAppsCache=$null
}
function Add-CoveApplication([string]$name,[string]$path){
 $normalized=ConvertTo-CoveAppName $name
 if(-not $normalized -or $normalized.Length -gt 60){throw 'Escolha um nome curto para chamar o aplicativo.'}
 if([IO.Path]::GetExtension($path).ToLowerInvariant() -notin @('.exe','.lnk') -or -not [IO.Path]::IsPathRooted($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)){throw 'Escolha um aplicativo .exe ou um atalho .lnk existente.'}
 $apps=@(Get-CoveApplications)
 if(@($apps|Where-Object{$_.Aliases -contains $normalized}).Count){throw 'Ja existe um aplicativo com esse nome. Escolha outro nome.'}
 $apps+=@([pscustomobject]@{Name=$name.Trim();Path=$path;Custom=$true})
 Save-CoveCustomApps $apps
}
function Invoke-CoveAppRequest([string]$text,[switch]$DryRun,[switch]$RequireConfirmation){
 $request=Get-CoveAppRequest $text
 if(-not $request){return [pscustomobject]@{Handled=$false;Message='';AppName='';Launched=$false}}
 if($request.Kind -eq 'refresh' -and -not $DryRun){$script:coveAppsCache=$null}
 $apps=@(Get-CoveApplications)
 if($request.Kind -eq 'refresh'){return [pscustomobject]@{Handled=$true;Message=('Encontrei '+$apps.Count+' apps e jogos.');AppName='';Launched=$false}}
 if($request.Kind -eq 'list'){
  $names=($apps|Select-Object -First 30|ForEach-Object{$_.Name}) -join ', '
  if($apps.Count -gt 30){$names+='; e mais '+($apps.Count-30)+' na lista Apps'}
  if(-not $names){$names='nenhum aplicativo cadastrado'}
  return [pscustomobject]@{Handled=$true;Message=('Posso abrir: '+$names+'. Tambem encontro apps no menu Iniciar e na Area de Trabalho. Apps portateis podem ser cadastrados ou abertos pelo caminho completo.');AppName='';Launched=$false}
 }
 $matching=@($apps|Where-Object{$_.Aliases -contains $request.Target})
 if($matching.Count -gt 1){return [pscustomobject]@{Handled=$true;Message='Mais de um app tem esse nome. Escolha o caminho correto no botao Apps.';AppName='';Launched=$false}}
 $app=$matching|Select-Object -First 1
 if($request.DirectPath){$app=[pscustomobject]@{Name=$request.DirectPath;Path=$request.DirectPath;Arguments=@();Aliases=@();Custom=$false}}
 if(-not $app){
  $suggestion=Get-CoveAppSuggestion $request.Target $apps
  if($suggestion){return [pscustomobject]@{Handled=$true;Message=('Voce quis dizer '+$suggestion.Name+'? Diga sim para abrir ou nao para cancelar.');AppName=$suggestion.Name;Launched=$false;NeedsConfirmation=$true}}
  return [pscustomobject]@{Handled=$true;Message=('Nao identifiquei o aplicativo em: '+$request.Target+'. Confira o nome no botao Apps ou tente dizer abre o Discord.');AppName='';Launched=$false}
 }
 if($RequireConfirmation){return [pscustomobject]@{Handled=$true;Message=('Entendi abrir '+$app.Name+'. Diga sim para confirmar ou nao para cancelar.');AppName=$app.Name;Launched=$false;NeedsConfirmation=$true}}
 if($app.LaunchUri -and -not (Test-CoveGameUri $app.LaunchUri)){return [pscustomobject]@{Handled=$true;Message='O atalho do jogo e invalido.';AppName='';Launched=$false}}
 if(-not $app.AppId -and -not $app.LaunchUri -and -not (Test-Path -LiteralPath $app.Path -PathType Leaf)){return [pscustomobject]@{Handled=$true;Message=('O caminho de '+$app.Name+' nao esta mais disponivel. Confira o cadastro em Apps.');AppName=$app.Name;Launched=$false}}
 try{
  if(-not $DryRun){
   # Never interpret the recognized phrase as a command or as arguments.
   if($app.LaunchUri){Start-Process -FilePath $app.LaunchUri -ErrorAction Stop|Out-Null}
   elseif($app.AppId){
    Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList ('shell:AppsFolder\'+$app.AppId) -ErrorAction Stop|Out-Null
   }else{
   $launch=@{FilePath=$app.Path;ErrorAction='Stop'}
   if([IO.Path]::GetExtension($app.Path) -eq '.exe'){$launch.WorkingDirectory=[IO.Path]::GetDirectoryName($app.Path)}
   if($app.Arguments.Count){$launch.ArgumentList=$app.Arguments}
   Start-Process @launch|Out-Null
   }
  }
  return [pscustomobject]@{Handled=$true;Message=('Abrindo '+$app.Name+'.');AppName=$app.Name;Launched=(-not $DryRun)}
 }catch{return [pscustomobject]@{Handled=$true;Message=('Nao consegui iniciar '+$app.Name+'. Confira se ele abre pelo Windows.');AppName=$app.Name;Launched=$false}}
}

function Get-CoveDiscoveredApps {
 $found=New-Object 'Collections.Generic.List[object]'
 $roots=@([Environment]::GetFolderPath('StartMenu'),[Environment]::GetFolderPath('CommonStartMenu'),[Environment]::GetFolderPath('Desktop'),[Environment]::GetFolderPath('CommonDesktopDirectory'))
 foreach($root in $roots){
  if($root -and (Test-Path -LiteralPath $root)){
   foreach($file in @(Get-ChildItem -LiteralPath $root -Filter '*.lnk' -Recurse -File -ErrorAction SilentlyContinue)){
    $alias=ConvertTo-CoveAppName $file.BaseName
    $found.Add([pscustomobject]@{Name=$file.BaseName;Aliases=@($alias);Path=$file.FullName;Arguments=@();Custom=$false})
   }
   foreach($file in @(Get-ChildItem -LiteralPath $root -Filter '*.url' -File -ErrorAction SilentlyContinue)){
    # Desktop game shortcuts are offered only for known installed game protocols.
    $url=Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue|Where-Object{$_ -match '^URL=(steam://|com\.epicgames\.launcher://|roblox://)'}|Select-Object -First 1
    if($url){$found.Add([pscustomobject]@{Name=$file.BaseName;Aliases=@((ConvertTo-CoveAppName $file.BaseName));Path=$file.FullName;Arguments=@();Custom=$false})}
   }
  }
 }
 if(Get-Command Get-StartApps -ErrorAction SilentlyContinue){
  foreach($app in @(Get-StartApps -ErrorAction SilentlyContinue)){
   # App IDs come from Windows, never from a spoken command.
   if($app.AppID -and $app.AppID -notmatch '["\r\n]'){
    $found.Add([pscustomobject]@{Name=$app.Name;Aliases=@((ConvertTo-CoveAppName $app.Name));Path='';AppId=[string]$app.AppID;Arguments=@();Custom=$false})
   }
  }
 }
 return $found.ToArray()
}
