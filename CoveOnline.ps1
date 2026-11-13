$script:coveOnlineFile=Join-Path $PSScriptRoot 'cove-online.json'
$script:onlineCityUntil=[datetime]::MinValue
function Get-CoveWeatherCity {
 if(Test-Path -LiteralPath $script:coveOnlineFile){try{return [string](Get-Content -LiteralPath $script:coveOnlineFile -Raw|ConvertFrom-Json).City}catch{}}
 return ''
}
function Set-CoveWeatherCity([string]$City){
 $City=$City.Trim()
 if(-not $City -or $City.Length -gt 120 -or $City -match '[\r\n]'){throw 'Informe uma cidade e, se preciso, o estado.'}
 [IO.File]::WriteAllText($script:coveOnlineFile,(@{City=$City}|ConvertTo-Json),[Text.Encoding]::UTF8)
}
function Get-CoveChromePath {
 foreach($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe','HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe')){
  if(Test-Path -LiteralPath $key){$path=(Get-Item -LiteralPath $key).GetValue('');if($path -and (Test-Path -LiteralPath $path -PathType Leaf)){return $path}}
 }
 foreach($base in @($env:ProgramFiles,${env:ProgramFiles(x86)},$env:LOCALAPPDATA)){
  if($base){$path=Join-Path $base 'Google\Chrome\Application\chrome.exe';if(Test-Path -LiteralPath $path -PathType Leaf){return $path}}
 }
 return ''
}
function Get-CoveOnlineRequest([string]$Text){
 $text=ConvertTo-CoveRequestLanguage $Text;$key=ConvertTo-CoveAppName $text
 $result=[pscustomobject]@{Handled=$false;Message='';Task=$null;AwaitReply=$false;Kind='';Query='';City='';Url=''}
 if([datetime]::Now -lt $script:onlineCityUntil -and $key -match '^(cancela|cancelar|cancele|deixa pra la|esquece|nao quero)$'){$result.Handled=$true;$result.Kind='cancelCity';return $result}
 if($key -match '^(nao|como pesquisar|como buscar|como ligar|me explica|explique|ele disse|o site disse)\b'){return $result}
 if($text -match '(?i)^(?:minha cidade (?:e|é)|(?:defina|definir|salve|salvar|mude|mudar) (?:a )?cidade(?: para)?)\s+(.+)$'){$result.Kind='city';$result.City=$Matches[1].Trim()}
 elseif($key -match '^(que horas(?: sao| e)?(?: agora)?|qual (?:e )?(?:o )?horario(?: agora| atual)?|me (?:diga|diz|dizer|fala|fale|falar) (?:as horas|o horario|que horas sao)|hora atual)$'){$result.Kind='time'}
 elseif($key -match '^(?:que dia (?:e|estamos)(?: hoje)?|qual (?:e )?a data(?: de hoje)?|data de hoje|dia de hoje)$'){$result.Kind='date'}
 elseif($text -match '(?i)^(?:pesquisa|pesquise|pesquisar|busca|busque|buscar|procura|procure|procurar)(?:\s+(?:na internet|na web|no chrome|no google))?\s+(?:(?:por|sobre)\s+)?(.+)$'){$result.Kind='search';$result.Query=$Matches[1].Trim()}
 elseif($text -match '(?i)^(?:faz|faca|faça|fazer)\s+uma\s+(?:pesquisa|busca)(?:\s+(?:na internet|no chrome|no google))?\s+(?:sobre|por|de)\s+(.+)$'){$result.Kind='search';$result.Query=$Matches[1].Trim()}
 elseif($key -match '^(?:(?:quais sao|quais|me diga|me fala|me fale|leia|mostre|mostrar|traga) )?(?:as )?(?:ultimas |principais )?(?:noticias|manchetes)(?: de hoje| agora| do dia| recentes| atuais)?$' -or $key -match '^(me atualize com as noticias|me atualiza com as noticias|o que esta acontecendo no mundo)$'){$result.Kind='news'}
 elseif($key -match '\b(temperatura|quantos graus|como esta o tempo|como ta o tempo|como esta o clima)\b' -and $key -notmatch '^(explique|o que|como funciona|me explica)\b'){
  $result.Kind='weather'
  if($text -match '(?i)\b(?:em|de)\s+(.+?)(?:\s+(?:agora|hoje))?[?!.]*$'){$result.City=$Matches[1].Trim()}else{$result.City=Get-CoveWeatherCity}
 }elseif([datetime]::Now -lt $script:onlineCityUntil -and $text.Length -le 120 -and $key -notmatch '^(abre|abra|entre|entra|liga|ligue|cancela|cancelar|obrigado|obrigada|valeu|oi|ola|tudo bem|quem|qual|como|que|pesquisa)\b'){$result.Kind='weatherCity';$result.City=$text}
 if(-not $result.Kind){return $result}
 $result.Handled=$true
 if($result.Kind -eq 'search'){
  $result.Query=$result.Query -replace '(?i)\s+(?:no chrome|no google|na internet|na web)$',''
  $result.Url='https://www.google.com/search?q='+[uri]::EscapeDataString($result.Query)
 }
 return $result
}
function Invoke-CoveOnlineRequest([string]$Text,[switch]$DryRun){
 $result=Get-CoveOnlineRequest $Text
 if(-not $result.Handled){return $result}
 switch($result.Kind){
  'cancelCity' {if(-not $DryRun){$script:onlineCityUntil=[datetime]::MinValue};$result.Message='Consulta de temperatura cancelada.'}
  'time' {$result.Message='Agora sao '+(Get-Date -Format 'HH:mm')+'. Horario do computador.'}
  'date' {$result.Message='Hoje e '+[datetime]::Now.ToString('dddd, dd \de MMMM \de yyyy',[Globalization.CultureInfo]::GetCultureInfo('pt-BR'))+'.'}
  'city' {if(-not $DryRun){Set-CoveWeatherCity $result.City};$result.Message='Cidade para temperatura: '+$result.City+'.'}
  'search' {
   $chrome=Get-CoveChromePath
   if(-not $chrome){$result.Message='Nao encontrei o Chrome instalado. Instale ou abra o Chrome e tente novamente.';return $result}
   if(-not $DryRun){try{Start-Process -FilePath $chrome -ArgumentList $result.Url -ErrorAction Stop|Out-Null}catch{$result.Message='Nao consegui abrir a pesquisa no Chrome.';return $result}}
   $result.Message='Abrindo a pesquisa por '+$result.Query+' no Chrome.'
  }
  'news' {$result.Message='Consultando as manchetes recentes.';if(-not $DryRun){$result.Task=[CoveApp.Online]::News([Threading.CancellationToken]::None)}}
  default {
   if(-not $result.City){$result.Message='Qual cidade e estado devo usar para a temperatura? Vou guardar para as proximas consultas.';$result.AwaitReply=$true;if(-not $DryRun){$script:onlineCityUntil=[datetime]::Now.AddSeconds(90)}}
   else{
    if(-not $DryRun){if($result.Kind -eq 'weatherCity'){Set-CoveWeatherCity $result.City};$script:onlineCityUntil=[datetime]::MinValue;$result.Task=[CoveApp.Online]::Weather($result.City,[Threading.CancellationToken]::None)}
    $result.Message='Consultando a temperatura em '+$result.City+'.'
   }
  }
 }
 return $result
}
