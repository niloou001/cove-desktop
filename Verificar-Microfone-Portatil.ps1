$ErrorActionPreference='Stop'
Add-Type -Path @("$PSScriptRoot\CoveCore.cs","$PSScriptRoot\CoveASR.cs") -ReferencedAssemblies System.Net.Http,System.Web.Extensions
if([CoveApp.Listener]::ResolveDevice(7,2) -ne -1){throw 'Microfone salvo de outro PC nao voltou ao padrao.'}
if([CoveApp.Listener]::ResolveDevice(1,2) -ne 1){throw 'Microfone valido alterado.'}
if([CoveApp.Listener]::ResolveDevice(-1,0) -ne -1){throw 'Dispositivo padrao invalido.'}
if([CoveApp.Listener]::MicrophoneError(4) -notlike '*ocupado*'){throw 'Microfone ocupado sem diagnostico.'}
$tokens=$null;$issues=$null
$ast=[Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot\Cove-Voice.ps1",[ref]$tokens,[ref]$issues)
if($issues.Count){throw ($issues|Out-String)}
foreach($name in @('Test-CoveListeningFiles','Get-CoveListeningHint')){
 $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
 . ([scriptblock]::Create($node.Extent.Text.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))))
}
$script:native=$false;$script:model=$false
function Test-Path {param($LiteralPath) if($LiteralPath -like '*libvosk.dll'){return $script:native};return $script:model}
if(Test-CoveListeningFiles){throw 'Instalacao ausente aceita.'}
if((Get-CoveListeningHint) -notlike '*ainda nao foi instalada*'){throw 'Instalacao ausente sem orientacao.'}
$script:native=$true
if(Test-CoveListeningFiles){throw 'Biblioteca sem modelo aceita.'}
$script:model=$true
if(-not (Test-CoveListeningFiles)){throw 'Arquivos instalados depois da abertura nao foram detectados.'}
$script:lastError='Microfone ocupado'
if((Get-CoveListeningHint) -notlike '*Microfone ocupado*'){throw 'Erro original ocultado.'}
$script:micSetup=[pscustomobject]@{HasExited=$false}
if((Get-CoveListeningHint) -notlike '*Aguarde o download*'){throw 'Instalacao em andamento sem orientacao.'}
Remove-Item Function:\Test-Path
'OK: arquivos ausentes, instalacao concluida sem reabrir, erro preservado e dispositivo de outro PC. Sem capturar audio ou alterar permissoes.'
