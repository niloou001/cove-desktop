function Invoke-CoveFileRequest([string]$text,[switch]$DryRun){
 $result=[pscustomobject]@{Handled=$false;Message='';NeedsConfirmation=$false;AppName='';LocalOnly=$true}
 $text=ConvertTo-CoveRequestLanguage $text
 $normalized=ConvertTo-CoveAppName $text
 if($normalized -match '^(quais discos|liste os discos|listar discos|mostrar discos|meu computador|este computador)$'){
  $result.Handled=$true
  $result.Message='Discos disponiveis: '+((Get-PSDrive -PSProvider FileSystem|ForEach-Object{$_.Root}) -join ', ')+'. Diga listar pasta seguido do caminho, ou abrir pasta Documentos.'
  return $result
 }
 # Preserve the original spelling of paths, accents, spaces and punctuation.
 if($text -notmatch '(?i)^\s*(?:cove[, ]+)?(abrir|abra|abre|listar|liste|mostrar|mostre|ler|leia)\s+(?:a\s+)?(pasta|arquivo)\s+(.+?)\s*$'){return $result}
 $verb=$Matches[1].ToLowerInvariant();$kind=$Matches[2].ToLowerInvariant();$target=$Matches[3].Trim().Trim('"')
 $result.Handled=$true
 try{
  switch(ConvertTo-CoveAppName $target){
   'documentos' {$target=[Environment]::GetFolderPath('MyDocuments')}
   'area de trabalho' {$target=[Environment]::GetFolderPath('Desktop')}
   'downloads' {$target=Join-Path $env:USERPROFILE 'Downloads'}
  }
  if(-not [IO.Path]::IsPathRooted($target) -or $target.StartsWith('\\')){throw 'Informe um caminho local completo, como C:\Users, ou diga Documentos, Downloads ou Area de Trabalho.'}
  $item=Get-Item -LiteralPath $target -ErrorAction Stop
  if($kind -eq 'pasta' -and -not $item.PSIsContainer){throw 'Esse caminho corresponde a um arquivo.'}
  if($verb -in @('abrir','abra','abre')){
   if(-not $item.PSIsContainer){throw 'Para abrir programas, use o cadastro no botao Apps. Para consultar um texto, diga leia arquivo seguido do caminho.'}
   if(-not $DryRun){Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList ('"'+$item.FullName+'"') -ErrorAction Stop|Out-Null}
   $result.Message='Pasta aberta: '+$item.FullName
  }elseif($verb -in @('ler','leia')){
   if($item.PSIsContainer -or $item.Extension -notin @('.txt','.md','.csv','.json','.log')){throw 'Posso ler arquivos de texto: txt, md, csv, json e log.'}
   if($item.Length -gt 1MB){throw 'Esse arquivo e grande demais para leitura por voz. Escolha um texto de ate 1 MB.'}
   $content=[IO.File]::ReadAllText($item.FullName)
   if($content.Length -gt 4000){$content=$content.Substring(0,4000)+' [Leitura limitada aos primeiros 4000 caracteres.]'}
   $result.Message=if($content){$content}else{'O arquivo esta vazio.'}
  }else{
   if(-not $item.PSIsContainer){throw 'Para listar, informe uma pasta.'}
   $entries=@(Get-ChildItem -LiteralPath $item.FullName -ErrorAction Stop|Select-Object -First 31)
   $result.Message=if($entries.Count){($entries|Select-Object -First 30|ForEach-Object{if($_.PSIsContainer){'Pasta '+$_.Name}else{$_.Name}}) -join '; '}else{'A pasta esta vazia.'}
   if($entries.Count -gt 30){$result.Message+='; Exibindo os primeiros 30 itens.'}
  }
 }catch{$result.Message='Nao consegui acessar esse caminho. '+$_.Exception.Message}
 return $result
}
