param([switch]$Restart,[switch]$ShowDiscord,[switch]$ListenOnStart)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\CoveRuntime.ps1"
function Test-CoveProcessCommand([string]$Command,[string]$Root){
 if($Command -match '(?i)(?:^|\s)-(?:Command|EncodedCommand|c|ec)\b'){return $false}
 $scriptPath=[regex]::Escape((Join-Path $Root 'Cove-Voice.ps1'))
 return $Command -match ('(?i)(?:^|\s)-File\s+(?:"'+$scriptPath+'"|'+$scriptPath+')(?=\s|$)') -and $Command -notmatch '(?i)(?:^|\s)-SmokeTest(?:\s|$)'
}
function Get-CoveOwnedProcesses([string]$Root){
 return @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.ProcessId -ne $PID -and $_.CommandLine -and (Test-CoveProcessCommand $_.CommandLine $Root)}|ForEach-Object{[int]$_.ProcessId})
}
function Backup-CoveLegacyConversation([int]$ProcessId,[string]$Root){
 try{
  Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,WindowsBase
  foreach($handle in [CoveApp.RuntimeWindows]::Handles($ProcessId,'Conversa com Cove')){
   $rootElement=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$handle)
   $box=$rootElement.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'Transcript')))
   if($box){$pattern=$null;if($box.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern,[ref]$pattern)){$text=$pattern.Current.Value;if($text){Save-CoveReloadState $Root $text};return}}
  }
 }catch{}
}
try{
 $build=Get-CoveBuildId $PSScriptRoot
 $running=Test-CoveInstanceRunning $PSScriptRoot
 $runtime=$null;try{$runtime=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'cove-runtime.json') -Raw -ErrorAction Stop|ConvertFrom-Json}catch{}
 if($running -and ($Restart -or -not $runtime -or $runtime.Root -ne $PSScriptRoot -or $runtime.Build -ne $build -or $runtime.Features -notcontains 'mouse-two-monitors')){
  if(-not ('CoveApp.RuntimeWindows' -as [type])){Add-Type -Path "$PSScriptRoot\CoveRuntimeWindows.cs"}
  $prefix=Get-CoveChannelPrefix $PSScriptRoot
  try{$reload=[Threading.EventWaitHandle]::OpenExisting($prefix+'.Reload');try{$reload.Set()|Out-Null}finally{$reload.Dispose()}}catch{}
  $until=[datetime]::UtcNow.AddSeconds(2)
  while((Test-CoveInstanceRunning $PSScriptRoot) -and [datetime]::UtcNow -lt $until){Start-Sleep -Milliseconds 100}
  if(Test-CoveInstanceRunning $PSScriptRoot){
   foreach($owner in @(Get-CoveOwnedProcesses $PSScriptRoot)){
    Backup-CoveLegacyConversation $owner $PSScriptRoot
    [CoveApp.RuntimeWindows]::CloseCove($owner)|Out-Null
   }
   $until=[datetime]::UtcNow.AddSeconds(8)
   while((Test-CoveInstanceRunning $PSScriptRoot) -and [datetime]::UtcNow -lt $until){Start-Sleep -Milliseconds 100}
  }
  if(Test-CoveInstanceRunning $PSScriptRoot){throw 'A instancia antiga ainda esta aberta. Use o botao direito na bolinha > Sair e abra Atualizar Cove novamente. Nenhum processo foi encerrado a forca.'}
 }
 $arguments='-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'Cove-Voice.ps1')+'"'
 if($ListenOnStart){$arguments+=' -ListenOnStart'}
 if($ShowDiscord){$arguments+=' -OpenDiscordSettings'}
 Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
 if(-not $ListenOnStart -and -not $ShowDiscord){
  if(-not ('CoveApp.RuntimeWindows' -as [type])){Add-Type -Path "$PSScriptRoot\CoveRuntimeWindows.cs"}
  $until=[datetime]::UtcNow.AddSeconds(30)
  do{
   try{
    $active=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'cove-runtime.json') -Raw -ErrorAction Stop|ConvertFrom-Json
    if($active.Root -eq $PSScriptRoot -and $active.Build -eq $build -and [CoveApp.RuntimeWindows]::Handles($active.Pid,'Conversa com Cove').Length){
     $show=[Threading.EventWaitHandle]::OpenExisting((Get-CoveChannelPrefix $PSScriptRoot)+'.Show')
     try{$show.Set()|Out-Null}finally{$show.Dispose()}
     Start-Sleep -Milliseconds 250
     [CoveApp.RuntimeWindows]::RevealConversation($active.Pid)|Out-Null
     break
    }
   }catch{}
   Start-Sleep -Milliseconds 250
  }while([datetime]::UtcNow -lt $until)
 }
}catch{
 Add-Type -AssemblyName PresentationFramework
 [Windows.MessageBox]::Show($_.Exception.GetBaseException().Message,'Cove - atualizar')|Out-Null
 exit 1
}
