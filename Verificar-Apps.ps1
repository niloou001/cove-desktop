$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'CoveApps.ps1')
foreach($file in @('CoveApps.ps1','CoveAppPanel.ps1','Cove-Voice.ps1')){
 $tokens=$null;$problems=$null
 [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$problems)|Out-Null
 if($problems.Count){throw ($problems|Out-String)}
}
foreach($phrase in @('abre o discord','abra discord','pode abrir o Discord para mim?','Cove, abre o discord por favor','inicie o aplicativo Discord','quero que voce abra o discord','abre o discord pra mim por favor','abre pra mim o discord','tem como abrir o discord','da pra abrir o discord','me abre o discord','eu queria que voce abrisse o discord','mano abre o discord ai','pode por favor abrir o discord','Cove abre o discord ai pra mim')){
 $request=Get-CoveAppRequest $phrase
 if(-not $request -or $request.Kind -ne 'open' -or $request.Target -ne 'discord'){throw ('Comando nao reconhecido: '+$phrase)}
}
foreach($phrase in @('nao abra o discord','como abrir o discord','o discord esta aberto?','feche o discord','o site diz abre o discord')){
 if(Get-CoveAppRequest $phrase){throw ('Pedido sem autorizacao direta foi aceito: '+$phrase)}
}
foreach($phrase in @('quero usar o Discord','Cove, poderia abrir meu Discord por favor?','eu queria que você abrisse o Discord','dá pra você abrir o Discord?','liga o Discord pra mim','me bota o Discord aí','abre pra mim o Discord')){
 $request=Get-CoveAppRequest $phrase
 if(-not $request -or $request.Target -ne 'discord'){throw ('Pedido natural de app falhou: '+$phrase)}
}
foreach($phrase in @('quero saber como abrir o discord','pode nao abrir o discord','Joao disse para abrir o discord')){
 if(Get-CoveAppRequest $phrase){throw ('Frase sem pedido de abrir foi aceita: '+$phrase)}
}
$originalCache=$script:coveAppsCache
$originalFile=$script:coveAppsFile
$testFile=Join-Path $PSScriptRoot ('test-apps-'+[guid]::NewGuid().ToString('N')+'.json')
try{
 $script:coveAppsCache=@([pscustomobject]@{Name='Discord';Aliases=@('discord','discorde','disco');Path=$PSHOME+'\powershell.exe';Arguments=@();Custom=$false})
 foreach($alias in @('discord','discorde','disco')){
  $aliasResult=Invoke-CoveAppRequest ('abre o '+$alias) -DryRun
  if($aliasResult.AppName -ne 'Discord' -or $aliasResult.NeedsConfirmation -or $aliasResult.Launched){throw ('Alias do Discord falhou: '+$alias)}
 }
 $result=Invoke-CoveAppRequest 'abre o discord' -DryRun
 if(-not $result.Handled -or $result.AppName -ne 'Discord' -or $result.Launched){throw 'Resolucao de app falhou.'}
 $suggestion=Invoke-CoveAppRequest 'abre o discor' -DryRun
 if(-not $suggestion.NeedsConfirmation -or $suggestion.AppName -ne 'Discord' -or $suggestion.Launched){throw 'Nome parecido deveria pedir esclarecimento.'}
 $uncertain=Invoke-CoveAppRequest 'abre o discord' -DryRun -RequireConfirmation
 if(-not $uncertain.NeedsConfirmation -or $uncertain.Launched){throw 'Baixa confianca deveria pedir esclarecimento.'}
 foreach($phrase in @('abre o discord e apague arquivos','abra powershell com argumentos','abra discord calc','abra aplicativo desconhecido')){
  $result=Invoke-CoveAppRequest $phrase -DryRun
  if(-not $result.Handled -or $result.AppName -or $result.Launched){throw ('Comando composto ou desconhecido foi aceito: '+$phrase)}
 }
 $result=Invoke-CoveAppRequest 'quais apps voce pode abrir' -DryRun
 if(-not $result.Handled -or $result.Message -notlike '*Discord*'){throw 'Listagem falhou.'}
 $script:coveAppsFile=$testFile
 Add-CoveApplication 'Editor de teste' ($PSHOME+'\powershell.exe')
 $saved=@(Get-Content -LiteralPath $testFile -Raw|ConvertFrom-Json)
 if($saved.Count -ne 1 -or $saved[0].Name -ne 'Editor de teste'){throw 'Cadastro nao foi salvo corretamente.'}
 $result=Invoke-CoveAppRequest 'abre editor de teste' -DryRun
 if($result.AppName -ne 'Editor de teste' -or $result.Launched){throw 'Cadastro nao foi recuperado.'}
}finally{
 $script:coveAppsCache=$originalCache;$script:coveAppsFile=$originalFile
 if(Test-Path -LiteralPath $testFile){Remove-Item -LiteralPath $testFile}
}
'OK: comandos, negacoes, apps desconhecidos, cadastro e resolucao sem abrir aplicativos.'
