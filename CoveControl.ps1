function Invoke-CoveComputerRequest([string]$text,[switch]$DryRun){
 $result=[pscustomobject]@{Handled=$true;Message='';NeedsConfirmation=$false;AppName=''}
 $command=ConvertTo-CoveAppName $text
 try{
  if($command -in @('ajuda computador','comandos do computador')){
   $result.Message='Diga listar janelas; focar janela seguido do titulo; digite seguido do texto; pressione control s; mover mouse para 500 300; clicar; clique direito; duplo clique; rolar para baixo; minimizar janela; maximizar janela; criar pasta seguido do caminho; criar arquivo caminho com texto conteudo; editar arquivo caminho com texto conteudo; adicionar ao arquivo caminho com texto conteudo; mover arquivo caminho para destino; excluir arquivo caminho. Os comandos de teclado e clique usam a janela escolhida em focar janela.'
  }elseif($command -eq 'listar janelas'){
   if($DryRun){$result.Message='Listaria as janelas abertas.'}else{$result.Message=([CoveApp.Computer]::Windows()|Select-Object -First 30) -join '; '}
   if(-not $result.Message){$result.Message='Nenhuma janela encontrada.'}
  }elseif($text -match '(?i)^\s*focar janela\s+(.+?)\s*$'){
   $title=$Matches[1]
   if($DryRun){$result.Message='Focaria a janela: '+$title}else{$result.Message='Janela selecionada: '+[CoveApp.Computer]::Focus($title)}
  }elseif($text -match '(?is)^\s*(?:digite|digitar|escreva)\s+(.+)$'){
   $value=$Matches[1]
   if(-not $DryRun){[CoveApp.Computer]::Type($value)}
   $result.Message='Texto digitado na janela selecionada.'
  }elseif($command -match '^(pressione|pressionar|aperte) (.+)$'){
   $keyText=$Matches[2];$control=$false;$shift=$false;$alt=$false
   $keyText=$keyText -replace '\bctrl\b','control'
   $parts=@($keyText -split ' ')
   $keys=@()
   foreach($part in $parts){switch($part){'control'{$control=$true};'shift'{$shift=$true};'alt'{$alt=$true};default{$keys+=@($part)}}}
   $keyName=$keys -join ' '
   $map=@{enter=13;tab=9;escape=27;esc=27;espaco=32;backspace=8;delete=46;home=36;end=35;'page up'=33;'page down'=34;'seta esquerda'=37;'seta direita'=39;'seta cima'=38;'seta baixo'=40}
   if($map.ContainsKey($keyName)){$key=[uint16]$map[$keyName]}
   elseif($keyName -match '^[a-z0-9]$'){$key=[uint16][char]$keyName.ToUpperInvariant()}
   elseif($keyName -match '^f([1-9]|1[0-2])$'){$key=[uint16](111+[int]$Matches[1])}
   else{throw 'Tecla desconhecida. Exemplos: pressione enter; pressione control s; pressione alt tab.'}
   if(-not $DryRun){[CoveApp.Computer]::Press($key,$control,$shift,$alt)}
   $result.Message='Teclas enviadas a janela selecionada.'
  }elseif($command -match '^mover mouse para (-?\d+) (-?\d+)$' -or $text -match '(?i)^mover mouse para\s+(-?\d+)[, ]+(-?\d+)$'){
   # Parse original text so negative monitor coordinates keep their sign.
   if($text -notmatch '(?i)^mover mouse para\s+(-?\d+)[, ]+(-?\d+)$'){throw 'Use mover mouse para 500 300.'}
   $x=[int]$Matches[1];$y=[int]$Matches[2]
   if(-not $DryRun){[CoveApp.Computer]::Move($x,$y)}
   $result.Message='Mouse movido.'
  }elseif($command -in @('clicar','clique','clique esquerdo','clique direito','duplo clique')){
   if(-not $DryRun){[CoveApp.Computer]::Click(($command -eq 'clique direito'),($command -eq 'duplo clique'))}
   $result.Message='Clique executado.'
  }elseif($command -match '^rolar para (cima|baixo)$'){
   $amount=if($Matches[1] -eq 'cima'){360}else{-360}
   if(-not $DryRun){[CoveApp.Computer]::Scroll($amount)}
   $result.Message='Rolagem executada.'
  }elseif($command -in @('minimizar janela','maximizar janela','restaurar janela')){
   $mode=@{'minimizar janela'=6;'maximizar janela'=3;'restaurar janela'=9}[$command]
   if(-not $DryRun){[CoveApp.Computer]::Window($mode)}
   $result.Message='Janela atualizada.'
  }elseif($text -match '(?is)^\s*(criar arquivo|editar arquivo|adicionar ao arquivo)\s+(.+?)\s+com texto\s+(.*)$'){
   $operation=$Matches[1].ToLowerInvariant();$path=Resolve-CoveWritePath $Matches[2];$value=$Matches[3]
   if([IO.Path]::GetExtension($path).ToLowerInvariant() -notin @('.txt','.md','.csv','.json','.log')){throw 'Use um arquivo de texto: txt, md, csv, json ou log.'}
   if($value.Length -gt 12000){throw 'Limite de 12000 caracteres por comando.'}
   if($operation -eq 'criar arquivo'){
    if(-not $DryRun){$stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write);try{$bytes=[Text.Encoding]::UTF8.GetBytes($value);$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}}
    $result.Message='Arquivo criado: '+$path
   }else{
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw 'Arquivo inexistente.'}
    if(-not $DryRun){
     $backup=$path+'.cove-backup-'+[guid]::NewGuid().ToString('N')
     [IO.File]::Copy($path,$backup,$false)
     if($operation -eq 'editar arquivo'){[IO.File]::WriteAllText($path,$value,[Text.Encoding]::UTF8)}else{[IO.File]::AppendAllText($path,[Environment]::NewLine+$value,[Text.Encoding]::UTF8)}
    }
    $result.Message='Arquivo atualizado com copia de seguranca: '+$path
   }
  }elseif($text -match '(?i)^\s*criar pasta\s+(.+?)\s*$'){
   $path=Resolve-CoveWritePath $Matches[1]
   if(-not $DryRun){[IO.Directory]::CreateDirectory($path)|Out-Null}
   $result.Message='Pasta criada: '+$path
  }elseif($text -match '(?i)^\s*(?:mover|renomear) arquivo\s+(.+?)\s+para\s+(.+?)\s*$'){
   $source=Resolve-CoveWritePath $Matches[1];$destination=Resolve-CoveWritePath $Matches[2]
   if(-not (Test-Path -LiteralPath $source -PathType Leaf)){throw 'Arquivo de origem inexistente.'}
   if(Test-Path -LiteralPath $destination){throw 'O destino ja existe. Escolha outro caminho.'}
   if(-not $DryRun){[IO.File]::Move($source,$destination)}
   $result.Message='Arquivo movido para: '+$destination
  }elseif($text -match '(?i)^\s*(?:excluir|apagar) arquivo\s+(.+?)\s*$'){
   $path=Resolve-CoveWritePath $Matches[1]
   if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw 'Arquivo inexistente.'}
   if(-not $DryRun){
    Add-Type -AssemblyName Microsoft.VisualBasic
    # Recycle only. Let Windows show failures rather than deleting permanently.
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($path,[Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,[Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin,[Microsoft.VisualBasic.FileIO.UICancelOption]::ThrowException)
   }
   $result.Message='Arquivo enviado para a Lixeira: '+$path
  }else{$result.Handled=$false}
 }catch{$result.Message='Nao consegui executar: '+$_.Exception.Message}
 return $result
}
function Resolve-CoveWritePath([string]$path){
 $path=$path.Trim().Trim('"')
 if($path -notmatch '^[a-zA-Z]:[\\/]' -or ($path.IndexOf(':',2) -ge 0)){throw 'Informe o caminho completo de um disco local, como C:\Users\seu nome\Documents\nota.txt.'}
 $full=[IO.Path]::GetFullPath($path)
 if($full.TrimEnd('\') -eq [IO.Path]::GetPathRoot($full).TrimEnd('\')){throw 'Informe uma pasta ou arquivo, em vez da raiz do disco.'}
 return $full
}
