$ErrorActionPreference='Stop'
foreach($file in @('Cove-Voice.ps1','Preparar-Cove.ps1')) {
 $tokens=$null;$problems=$null
 [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$problems)|Out-Null
 if($problems.Count){throw ($file+': '+($problems|Out-String))}
}
Add-Type -Path @((Join-Path $PSScriptRoot 'CoveCore.cs'),(Join-Path $PSScriptRoot 'CoveASR.cs')) -ReferencedAssemblies System.Net.Http,System.Web.Extensions
$example='{"output":[{"type":"reasoning"},{"type":"message","content":[{"type":"output_text","text":"Ola, "},{"type":"output_text","text":"tudo bem?"}]}]}'
if([CoveApp.Brain]::Extract($example) -cne 'Ola, tudo bem?'){throw 'Falha ao extrair resposta da API.'}
$failed=$false
try{[CoveApp.Brain]::Extract('{"output":[]}')|Out-Null}catch{$failed=$true}
if(-not $failed){throw 'Resposta vazia deveria falhar.'}
$sample='couve qual e a capital do brasil'
$question=[regex]::Replace($sample,'(?i)^.*?\b(cove|couve|couvi)\b[ ,.!?]*','').Trim()
if($question -ne 'qual e a capital do brasil'){throw 'Nome nao foi removido da pergunta.'}
if('como vai voce' -match '(?i)\b(cove|couve|couvi)\b'){throw 'Falso acionamento do nome.'}
if([CoveApp.Brain]::LimitMessage('{"error":{"code":"rate_limit_exceeded","type":"rate_limit_error"}}') -notlike '*temporario*'){throw 'Limite temporario classificado incorretamente.'}
if([CoveApp.Brain]::LimitMessage('{"error":{"code":"insufficient_quota"}}') -notlike '*saldo ou limite*'){throw 'Quota classificada incorretamente.'}
if([CoveApp.Brain]::LimitMessage('{"error":{"code":"credit_balance_exhausted"}}') -notlike '*saldo de creditos*'){throw 'Saldo classificado incorretamente.'}
if([CoveApp.Brain]::LimitMessage('not json') -notlike '*nao identificou*'){throw 'Erro desconhecido classificado incorretamente.'}
$cancel=New-Object Threading.CancellationTokenSource
$cancel.Cancel()
$task=[CoveApp.Brain]::Ask('test-key','{}',$cancel.Token)
try{$task.GetAwaiter().GetResult()|Out-Null;throw 'Cancelamento ignorado.'}catch{if(-not $task.IsCanceled){throw 'Requisicao cancelada nao foi tratada como cancelamento.'}}
$cancel.Dispose()
$mono=New-Object CoveApp.PcmConverter(48000,2)
$pcm=New-Object byte[] 19200
for($i=0;$i -lt $pcm.Length;$i+=4){$pcm[$i]=232;$pcm[$i+1]=3;$pcm[$i+2]=232;$pcm[$i+3]=3}
$converted=$mono.Convert($pcm)
if($converted.Length -ne 3200 -or [BitConverter]::ToInt16($converted,0) -ne 1000){throw 'Conversao de microfone 48k stereo falhou.'}
$converter=New-Object CoveApp.PcmConverter(44100,1)
$first=$converter.Convert((New-Object byte[] 4410));$second=$converter.Convert((New-Object byte[] 4410))
if($first.Length+$second.Length -ne 3200){throw 'Conversao entre blocos de audio perdeu amostras.'}
'OK: sintaxe, compilacao, resposta da API, resposta vazia, nome e cancelamento.'
