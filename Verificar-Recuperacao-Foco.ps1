$ErrorActionPreference='Stop'
Add-Type -Path "$PSScriptRoot\CoveComputer.cs"
$script:activeWindow=20L
$script:activations=0
[CoveApp.Computer]::RecoverForeground(10L,[Func[long]]{$script:activeWindow},[Action]{$script:activations++;if($script:activations -eq 2){$script:activeWindow=10L}},[Action]{},4,0)
if($script:activations -ne 2){throw 'Nao recuperou o foco apos uma tentativa recusada.'}
[CoveApp.Computer]::RecoverForeground(10L,[Func[long]]{10L},[Action]{throw 'Nao deve ativar uma janela que ja esta em foco.'},[Action]{},4,0)
$script:activations=0
try{
 [CoveApp.Computer]::RecoverForeground(10L,[Func[long]]{20L},[Action]{$script:activations++},[Action]{},4,0)
 throw 'Aceitou uma janela diferente.'
}catch{if($_.Exception.GetBaseException() -isnot [OperationCanceledException]){throw}}
if($script:activations -ne 4){throw 'Numero de tentativas incorreto.'}
$script:activations=0
try{
 [CoveApp.Computer]::RecoverForeground(10L,[Func[long]]{20L},[Action]{$script:activations++},[Action]{throw [OperationCanceledException]::new('Esc')},4,0)
 throw 'Ignorou o cancelamento.'
}catch{if($_.Exception.GetBaseException() -isnot [OperationCanceledException]){throw}}
if($script:activations -ne 0){throw 'Tentou ativar depois de cancelar.'}
'OK: recuperacao, foco existente, recusa do Windows e cancelamento.'
