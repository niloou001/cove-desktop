$ErrorActionPreference='Stop'
. "$PSScriptRoot\CoveApps.ps1"
. "$PSScriptRoot\CoveControl.ps1"
Add-Type -Path "$PSScriptRoot\CoveComputer.cs"
$tokens=$null;$problems=$null
[Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot\CoveControl.ps1",[ref]$tokens,[ref]$problems)|Out-Null
if($problems.Count){throw ($problems|Out-String)}
function Check([string]$command,[string]$expected,[switch]$Live){
 $r=Invoke-CoveComputerRequest $command -DryRun:(-not $Live)
 if(-not $r.Handled -or $r.Message -notlike $expected){throw ($command+': '+$r.Message)}
}
foreach($command in @('digite Olá {+}% ^ teste','pressione control s','pressione alt tab','pressione seta esquerda','pressione f12','mover mouse para -100 200','clique direito','duplo clique','rolar para baixo','minimizar janela','maximizar janela','focar janela Bloco de notas')){
 $r=Invoke-CoveComputerRequest $command -DryRun
 if(-not $r.Handled -or $r.Message -like 'Nao consegui*'){throw ($command+': '+$r.Message)}
}
Check 'pressione uma tecla inexistente' '*Tecla desconhecida*'
Check 'digite teste sem destino' '*Primeiro diga focar janela*' -Live
if((Invoke-CoveComputerRequest 'qual a capital do Brasil' -DryRun).Handled){throw 'Conversa interceptada'}
if((Invoke-CoveComputerRequest 'nao excluir arquivo C:\teste.txt' -DryRun).Handled){throw 'Negacao ignorada'}
Check 'criar arquivo C:\teste.ps1 com texto comando' '*arquivo de texto*'
Check 'criar pasta C:\' '*raiz do disco*'
Check 'criar arquivo C:\teste.txt:stream com texto teste' '*caminho completo*'
$testRoot=Join-Path $PSScriptRoot ('controle-test-'+[guid]::NewGuid().ToString('N'))
try{
 Check ('criar pasta '+$testRoot) 'Pasta criada:*' -Live
 $file=Join-Path $testRoot 'nota com espaço.txt'
 Check ('criar arquivo '+$file+' com texto Olá {+}% ^ $()') 'Arquivo criado:*' -Live
 if([IO.File]::ReadAllText($file) -cne 'Olá {+}% ^ $()'){throw 'Texto literal alterado'}
 Check ('criar arquivo '+$file+' com texto sobrescrever') 'Nao consegui*' -Live
 Check ('editar arquivo '+$file+' com texto Novo conteúdo') 'Arquivo atualizado*' -Live
 $backup=@(Get-ChildItem -LiteralPath $testRoot -Filter '*.cove-backup-*')
 if($backup.Count -ne 1 -or [IO.File]::ReadAllText($backup[0].FullName) -cne 'Olá {+}% ^ $()'){throw 'Backup incorreto'}
 Check ('adicionar ao arquivo '+$file+' com texto Outra linha') 'Arquivo atualizado*' -Live
 if([IO.File]::ReadAllText($file) -cne ('Novo conteúdo'+[Environment]::NewLine+'Outra linha')){throw 'Adicao incorreta'}
 $moved=Join-Path $testRoot 'movido.txt'
 Check ('mover arquivo '+$file+' para '+$moved) 'Arquivo movido*' -Live
 if((Test-Path -LiteralPath $file) -or -not (Test-Path -LiteralPath $moved)){throw 'Movimentacao falhou'}
 # Deletion must resolve through RecycleBin; only this test-owned file is used.
 Check ('excluir arquivo '+$moved) 'Arquivo enviado para a Lixeira:*' -Live
 if(Test-Path -LiteralPath $moved){throw 'Arquivo nao foi reciclado'}
}finally{
 # Delete only known test-owned files and the empty test directory.
 $resolved=[IO.Path]::GetFullPath($testRoot)
 if($resolved.StartsWith($PSScriptRoot+'\controle-test-',[StringComparison]::OrdinalIgnoreCase)){
  if(Test-Path -LiteralPath $resolved){Get-ChildItem -LiteralPath $resolved -File|ForEach-Object{[IO.File]::Delete($_.FullName)};[IO.Directory]::Delete($resolved,$false)}
 }
}
'OK: compilacao nativa, roteamento, teclas e mouse em simulacao, criacao, edicao, backups, movimentacao e Lixeira reais em arquivos de teste.'
