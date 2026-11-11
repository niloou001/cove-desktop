$ErrorActionPreference='Stop'
. "$PSScriptRoot\CoveApps.ps1"
. "$PSScriptRoot\CoveFiles.ps1"
$r=Invoke-CoveFileRequest 'liste os discos' -DryRun
if(-not $r.Handled -or $r.Message -notlike '*C:\*'){throw 'Discos ausentes'}
$r=Invoke-CoveFileRequest 'listar pasta Documentos' -DryRun
if(-not $r.Handled -or $r.Message -notlike '*cove-voice*'){throw 'Listagem falhou'}
$r=Invoke-CoveFileRequest ('leia arquivo '+$PSScriptRoot+'\README.md') -DryRun
if(-not $r.Handled -or $r.Message -notlike '*Cove Desktop*'){throw 'Leitura falhou'}
$r=Invoke-CoveFileRequest 'abrir pasta Documentos' -DryRun
if($r.Message -notlike 'Pasta aberta:*'){throw 'Abertura falhou'}
$r=Invoke-CoveFileRequest 'abrir arquivo C:\Windows\System32\cmd.exe' -DryRun
if($r.Message -notlike '*cadastro*'){throw 'Executavel fora do cadastro'}
$r=Invoke-CoveFileRequest 'abre o Discord' -DryRun
if($r.Handled){throw 'Comando de app interceptado'}
'OK: discos, listagem, leitura, abertura e roteamento.'
