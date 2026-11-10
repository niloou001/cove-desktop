$ErrorActionPreference='Stop'
Add-Type -Path @((Join-Path $PSScriptRoot 'CoveCore.cs'),(Join-Path $PSScriptRoot 'CoveASR.cs')) -ReferencedAssemblies System.Net.Http,System.Web.Extensions
$packet=New-Object byte[] 3200
$capture=New-Object CoveApp.UtteranceBuffer
for($i=0;$i -lt 20;$i++){if($capture.Push($packet,$false)){throw 'Silencio nao pode gerar pedido.'}}
for($i=0;$i -lt 3;$i++){if($capture.Push($packet,$true)){throw 'Fala nao pode terminar antes da pausa.'}}
for($i=0;$i -lt 10;$i++){if($capture.Push($packet,$false)){throw 'Pausa curta terminou a frase cedo.'}}
$result=$capture.Push($packet,$false)
if(-not $result -or $result.Length -lt 40000){throw 'Frase completa nao foi capturada.'}
if($capture.Push($packet,$false)){throw 'Mesmo pedido foi emitido duas vezes.'}
$capture.Reset()
$capture.Seed($packet)
for($i=0;$i -lt 15;$i++){if($capture.Push($packet,$false)){throw 'Nome na pre-captura nao deve criar sozinho uma pergunta.'}}
for($i=0;$i -lt 2;$i++){$capture.Push($packet,$true)|Out-Null}
$output=$null
for($i=0;$i -lt 11;$i++){$output=$capture.Push($packet,$false)}
if(-not $output){throw 'Resposta curta, como sim, nao foi capturada.'}
'OK: silencio, pausas, resposta curta, pre-captura e emissao unica.'
