$ErrorActionPreference='Stop'
Add-Type -Path @((Join-Path $PSScriptRoot 'CoveVoice.cs'),(Join-Path $PSScriptRoot 'CoveNeural.cs')) -ReferencedAssemblies System.Web.Extensions
$engine=New-Object CoveApp.CoveSpeech($PSScriptRoot)
if(-not $engine.Installed){$engine.Dispose();'SKIP: vozes locais nao instaladas.';exit 0}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('cove-warmup-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture)|Out-Null
$flags=[Reflection.BindingFlags]'Instance,NonPublic'
# Keep the installed interpreter/assets; replace only the worker with a silent
# protocol fixture. No microphone, network, sound playback or personal text.
$engine.GetType().GetField('root',$flags).SetValue($engine,$fixture)
$worker=@'
import json, sys, time
for line in sys.stdin:
    request = json.loads(line)
    time.sleep(1.0 if request.get("warmup") else 10.0)
    print(json.dumps({"ready": True} if request.get("warmup") else {"done": True}), flush=True)
'@
[IO.File]::WriteAllText((Join-Path $fixture 'cove_neural.py'),$worker)
function Wait-Worker {
 $deadline=[datetime]::UtcNow.AddSeconds(5)
 do {
  $p=$engine.GetType().GetField('child',$flags).GetValue($engine)
  if($p -and -not $p.HasExited){return $p.Id}
  Start-Sleep -Milliseconds 20
 }while([datetime]::UtcNow -lt $deadline)
 throw 'Worker nao iniciou'
}
try{
 $warm=$engine.WarmUp();$first=Wait-Worker
 $engine.Stop();$engine.Stop()
 if(-not $warm.GetAwaiter().GetResult()){throw 'Aquecimento falhou'}
 if((Wait-Worker) -ne $first){throw 'Interrupcao reiniciou o aquecimento'}
 $speech=$engine.Speak('Frase de teste.','kokoro:serena')
 Start-Sleep -Milliseconds 150
 $engine.Stop()
 $cancelled=$false
 try{$speech.GetAwaiter().GetResult()|Out-Null}catch{$cancelled=$true}
 if(-not $cancelled){throw 'Sintese ativa nao foi cancelada'}
 $next=$engine.WarmUp();$second=Wait-Worker
 if($second -eq $first){throw 'Sintese cancelada deixou o protocolo antigo ativo'}
 $next.GetAwaiter().GetResult()|Out-Null
 'OK: aquecimento preservado, sintese interrompida e worker reiniciado sem audio antigo.'
}finally{
 $engine.Dispose()
 [IO.File]::Delete((Join-Path $fixture 'cove_neural.py'))
 [IO.Directory]::Delete($fixture)
}
