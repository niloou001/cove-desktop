$script:coveIdentityFile=Join-Path $PSScriptRoot 'cove-identity.json'
function ConvertTo-CoveAssistantName([string]$Name){
 $Name=($Name.Trim() -replace '\s+',' ')
 if($Name.Length -lt 1 -or $Name.Length -gt 24 -or $Name -notmatch '\p{L}' -or $Name -notmatch "^[\p{L}\p{M}\p{N} .'-]+$"){throw 'Use um nome de 1 a 24 caracteres, com letras, numeros, espacos, ponto ou hifen.'}
 return $Name
}
function Get-CoveWakePattern([string]$Name=$script:assistantName){
 $plain=$Name.Normalize([Text.NormalizationForm]::FormD) -replace '\p{M}',''
 $words=($plain -replace '[^\p{L}\p{N}]',' ' -replace '\s+',' ').Trim()
 $compact=($plain -replace "[.']",'' -replace '[^\p{L}\p{N}]',' ' -replace '\s+',' ').Trim()
 $aliases=@($Name,$words,$compact);if($words -eq 'Cove'){$aliases+=@('couve','couvi')}
 if($compact -eq 'Jarvis'){$aliases+=@('jarbas')}
 return '(?<![\p{L}\p{N}])(?:'+((@($aliases|Where-Object{$_}|Select-Object -Unique)|ForEach-Object{[regex]::Escape($_)}) -join '|')+')(?![\p{L}\p{N}])'
}
function Get-CoveAssistantName {
 if(Test-Path -LiteralPath $script:coveIdentityFile){try{return ConvertTo-CoveAssistantName ([string](Get-Content -LiteralPath $script:coveIdentityFile -Raw|ConvertFrom-Json).Name)}catch{}}
 return 'Cove'
}
function Set-CoveAssistantName([string]$Name){
 $Name=ConvertTo-CoveAssistantName $Name
 $temporary=$script:coveIdentityFile+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try{
  [IO.File]::WriteAllText($temporary,(@{Name=$Name}|ConvertTo-Json -Compress),[Text.Encoding]::UTF8)
  if(Test-Path -LiteralPath $script:coveIdentityFile){[IO.File]::Replace($temporary,$script:coveIdentityFile,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$script:coveIdentityFile)}
  $script:assistantName=$Name
  $script:assistantWakePattern=Get-CoveWakePattern $Name
  if($script:listener -and $script:listener.PSObject.Properties['WakeName']){$script:listener.WakeName=$Name}
 }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary}}
 return $Name
}
$script:assistantName=Get-CoveAssistantName
$script:assistantWakePattern=Get-CoveWakePattern $script:assistantName
