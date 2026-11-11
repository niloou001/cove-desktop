$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'CoveInstance.ps1')
foreach($name in @('CoveInstance.ps1','Instalar-Ativacao.ps1','Cove-Voice.ps1')){
 $tokens=$null;$errors=$null
 [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name),[ref]$tokens,[ref]$errors)|Out-Null
 if($errors.Count){throw ($errors|Out-String)}
}
$identity='Cove-test-'+[guid]::NewGuid().ToString('N')
$first=$null;$second=$null;$third=$null
try{
 $first=Open-CoveInstanceChannel -Identity $identity
 if($first.AlreadyRunning -or -not $first.Owned){throw 'A primeira instancia nao foi registrada.'}
 $second=Open-CoveInstanceChannel -Identity $identity -Listen
 if(-not $second.AlreadyRunning -or $second.Owned){throw 'A instancia repetida nao foi detectada.'}
 if(-not $first.Listen.WaitOne(1000)){throw 'O pedido de escuta nao chegou a instancia existente.'}
 if($first.Show.WaitOne(0)){throw 'A abertura por voz usou o sinal errado.'}
 Close-CoveInstanceChannel $second;$second=$null
 $third=Open-CoveInstanceChannel -Identity $identity
 if(-not $first.Show.WaitOne(1000)){throw 'O pedido de exibir a janela nao chegou.'}
}finally{
 Close-CoveInstanceChannel $third
 Close-CoveInstanceChannel $second
 Close-CoveInstanceChannel $first
}
$again=Open-CoveInstanceChannel -Identity $identity
try{if($again.AlreadyRunning){throw 'O canal de uma janela encerrada continuou bloqueado.'}}finally{Close-CoveInstanceChannel $again}
'OK: instancia unica, chamada de voz, exibicao e liberacao dos canais.'
