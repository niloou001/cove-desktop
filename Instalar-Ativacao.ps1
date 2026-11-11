param([switch]$ConfigureOnly)
$ErrorActionPreference='Stop'
try{
 $base=Join-Path $env:LOCALAPPDATA 'Cove'
 $legacyStart=Join-Path $base 'start.ps1'
 $listener=Join-Path $base 'listener.py'
 $launcher=Join-Path $PSScriptRoot 'Abrir-Cove-Por-Voz.cmd'
 if(-not (Test-Path -LiteralPath $listener) -or -not (Test-Path -LiteralPath $legacyStart)){throw 'Instale primeiro o ativador da frase oi Cove, papai chegou. Esta integracao usa o ouvinte local ja instalado.'}
 if(-not (Test-Path -LiteralPath $launcher)){throw 'O iniciador do Cove Desktop nao foi encontrado.'}
 $wakeSource=Join-Path $PSScriptRoot 'CoveWakeListener.py'
 if(Test-Path -LiteralPath $wakeSource){Copy-Item -LiteralPath $wakeSource -Destination $listener -Force}
 [IO.File]::WriteAllText((Join-Path $base 'desktop-root.txt'),$PSScriptRoot,[Text.Encoding]::UTF8)
 $legacyDesktop=Join-Path $env:USERPROFILE 'Desktop'
 $actualDesktop=[Environment]::GetFolderPath('Desktop')
 $desktops=@($legacyDesktop,$actualDesktop)|Select-Object -Unique
 $batch="@echo off`r`ncall `""+$launcher.Replace('%','%%')+"`"`r`n"
 $activate="@echo off`r`ncall `""+(Join-Path $PSScriptRoot 'Ativar-Cove-Por-Voz.cmd').Replace('%','%%')+"`"`r`n"
 foreach($desktop in $desktops){
  if(-not (Test-Path -LiteralPath $desktop -PathType Container)){New-Item -ItemType Directory -Path $desktop -Force|Out-Null}
  $destination=Join-Path $desktop 'Cove.bat'
  if(Test-Path -LiteralPath $destination){
   $backup=Join-Path $desktop 'Cove-antes-do-Desktop.bat.bak'
   if(-not (Test-Path -LiteralPath $backup)){Copy-Item -LiteralPath $destination -Destination $backup}
  }
  [IO.File]::WriteAllText($destination,$batch,[Text.Encoding]::Default)
  [IO.File]::WriteAllText((Join-Path $desktop 'Ativar Cove por voz.cmd'),$activate,[Text.Encoding]::Default)
 }
 $startup=[Environment]::GetFolderPath('Startup')
 $shortcutFile=Join-Path $startup 'Cove Voz.lnk'
 if(-not (Test-Path -LiteralPath $shortcutFile)){
  $shell=New-Object -ComObject WScript.Shell
  $shortcut=$shell.CreateShortcut($shortcutFile)
  $shortcut.TargetPath=Join-Path $PSHOME 'powershell.exe'
  $shortcut.Arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$legacyStart+'"'
  $shortcut.WorkingDirectory=$base;$shortcut.WindowStyle=7;$shortcut.Save()
 }
 . (Join-Path $PSScriptRoot 'CoveIdentity.ps1')
 Write-Host ('Frase configurada: oi '+(Get-CoveAssistantName)+', papai chegou -> Cove Desktop.') -ForegroundColor Green
 Write-Host 'A inicializacao no login do Windows esta configurada.'
 if(-not $ConfigureOnly){
  Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"'+$legacyStart+'"')) -WorkingDirectory $base -WindowStyle Hidden
  Write-Host 'Ativacao iniciada. Aguarde alguns segundos e diga a frase.'
 }else{Write-Host 'Para iniciar na sua area de trabalho agora, abra Ativar Cove por voz.cmd na Area de Trabalho.'}
 exit 0
}catch{Write-Host ('Nao foi possivel configurar: '+$_.Exception.Message) -ForegroundColor Red;exit 1}
