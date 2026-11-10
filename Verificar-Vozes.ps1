$ErrorActionPreference='Stop'
foreach($file in @('Cove-Voice.ps1','Preparar-Vozes.ps1')){
 $tokens=$null;$problems=$null
 [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$problems)|Out-Null
 if($problems.Count){throw ($problems|Out-String)}
}
Add-Type -Path @((Join-Path $PSScriptRoot 'CoveVoice.cs'),(Join-Path $PSScriptRoot 'CoveNeural.cs')) -ReferencedAssemblies System.Web.Extensions
$voices=@([CoveApp.CoveSpeech]::Voices())
if(@($voices|Where-Object{$_.Id -eq 'kokoro:serena' -and $_.Gender -eq 'Female'}).Count -ne 1){throw 'Perfil Serena ausente.'}
if(@($voices|Where-Object{$_.Id -eq 'kokoro:atlas' -and $_.Gender -eq 'Male'}).Count -ne 1){throw 'Perfil Atlas ausente.'}
function Expect-Failure([scriptblock]$code){$failed=$false;try{& $code}catch{$failed=$true};if(-not $failed){throw 'Resposta de audio invalida foi aceita.'}}
Expect-Failure {[CoveApp.CoveSpeech]::DecodeAudio('{"error":"test"}')}
Expect-Failure {[CoveApp.CoveSpeech]::DecodeAudio('{"audio":"AAAA"}')}
Expect-Failure {[CoveApp.CoveSpeech]::DecodeAudio('{}')}
$wav=New-Object byte[] 44
[Text.Encoding]::ASCII.GetBytes('RIFF').CopyTo($wav,0);[Text.Encoding]::ASCII.GetBytes('WAVE').CopyTo($wav,8)
$json=@{audio=[Convert]::ToBase64String($wav)}|ConvertTo-Json -Compress
if([CoveApp.CoveSpeech]::DecodeAudio($json).Length -ne 44){throw 'Transporte WAV falhou.'}
$testRoot=Join-Path $PSScriptRoot ('voice-test-'+[guid]::NewGuid().ToString('N'))
$engine=New-Object CoveApp.CoveSpeech($testRoot)
try{
 if($engine.Installed){throw 'Instalacao ausente foi considerada pronta.'}
 $task=$engine.Speak('Teste.','kokoro:serena')
 Expect-Failure {$task.GetAwaiter().GetResult()}
 $engine.Stop()
}finally{$engine.Dispose()}
'OK: compilacao, sintaxe, perfis, transporte de audio e instalacao ausente.'
