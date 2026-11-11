param([switch]$Physical)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,WindowsBase
Add-Type -Path @("$PSScriptRoot\CoveComputer.cs","$PSScriptRoot\CoveDiscord.cs","$PSScriptRoot\CoveMessaging.cs") -ReferencedAssemblies UIAutomationClient,UIAutomationTypes,WindowsBase,System.Security
$displays=@([CoveApp.Computer]::Displays())
if(-not $displays.Count){throw 'No connected display detected'}
$sample=@([CoveApp.Computer+DisplayBounds]::new(0,0,1920,1080),[CoveApp.Computer+DisplayBounds]::new(-2560,-200,0,1240))
if(-not [CoveApp.Computer]::OnDisplay(-1800,100,$sample)){throw 'Left monitor negative coordinate rejected'}
if([CoveApp.Computer]::OnDisplay(-2600,100,$sample)){throw 'Outside display accepted'}
$gap=@([CoveApp.Computer+DisplayBounds]::new(0,0,1920,1080),[CoveApp.Computer+DisplayBounds]::new(-2000,200,-80,1280))
if([CoveApp.Computer]::OnDisplay(-40,300,$gap)){throw 'Gap between screens accepted as a clickable point'}
$path=[CoveApp.Computer]::Movement([CoveApp.Computer+DesktopPoint]::new(1200,600),[CoveApp.Computer+DesktopPoint]::new(-1800,100),16)
if($path.Count -ne 16 -or $path[-1].X -ne -1800 -or $path[-1].Y -ne 100){throw 'Movement did not end at the exact physical pixel'}
for($i=1;$i -lt $path.Count;$i++){if($path[$i].X -gt $path[$i-1].X){throw 'Mouse path reversed unexpectedly'}}
$cancel=New-Object Threading.CancellationTokenSource;$cancel.Cancel();$cancelled=$false
try{[CoveApp.Computer]::CheckMouseCancel($cancel.Token)}catch{$cancelled=$true}finally{$cancel.Dispose()}
if(-not $cancelled){throw 'Cancellation was ignored'}
'OK: negative coordinates, different display sizes, gaps, movement and cancellation.'
if(-not $Physical){return}
$original=[CoveApp.Computer]::Position();$last=$original;$completed=$false;$child=$null
$testRoot=Join-Path $PSScriptRoot ('mouse-test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot)|Out-Null
$exe=Join-Path $testRoot 'CoveMouseFixture.exe';$report=Join-Path $testRoot 'result.txt'
Add-Type -Path "$PSScriptRoot\MouseFixture.cs" -ReferencedAssemblies System.Windows.Forms,System.Drawing -OutputAssembly $exe -OutputType WindowsApplication
try{
 foreach($display in $displays){
  if(Test-Path -LiteralPath $report){Remove-Item -LiteralPath $report}
  $x=$display.Left+100;$y=$display.Top+100
  $start=New-Object Diagnostics.ProcessStartInfo
  $start.FileName=$exe;$start.Arguments='"'+$report+'" Cove-Mouse-Test '+$x+' '+$y+' '+$PID;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
  $child=[Diagnostics.Process]::Start($start)
  $deadline=[datetime]::UtcNow.AddSeconds(8)
  do{$child.Refresh();if($child.HasExited){throw 'Test window exited early'};$handle=$child.MainWindowHandle;if($handle -eq [IntPtr]::Zero){Start-Sleep -Milliseconds 100}}while($handle -eq [IntPtr]::Zero -and [datetime]::UtcNow -lt $deadline)
  if($handle -eq [IntPtr]::Zero){throw 'Test window not found'}
  [CoveApp.Computer]::FocusHandle($handle.ToInt64())
  $scope=[CoveApp.DiscordCall]::BeginMouseNavigation([Threading.CancellationToken]::None)
  try{
   $root=[Windows.Automation.AutomationElement]::FromHandle($handle)
   $flags=[Reflection.BindingFlags]'NonPublic,Static';$type=[CoveApp.DiscordCall]
   $selected=$type.GetMethod('SelectServer',$flags).Invoke($null,@($root,'CAPS',[Threading.CancellationToken]::None))
   if(-not $selected){throw 'Mouse did not select server'}
   $type.GetMethod('SelectVoiceChannel',$flags).Invoke($null,@($root,'CAPS','geral',[Threading.CancellationToken]::None))|Out-Null
   Start-Sleep -Milliseconds 150
   $state=[IO.File]::ReadAllText($report)
   if($state -notmatch '(?m)^server=1$' -or $state -notmatch '(?m)^voice=1$' -or $state -notmatch '(?m)^wrong=0$'){throw ('Wrong click in test window: '+$state)}
   $last=[CoveApp.Computer]::Position()
   if(-not [CoveApp.Computer]::OnDisplay($last.X,$last.Y,@($display))){throw 'Mouse landed on a different display'}
   'OK: physical server + voice clicks on monitor at '+$display.Left+','+$display.Top+'; no text/other-server clicks.'
  }finally{$scope.Dispose()}
  $child.CloseMainWindow()|Out-Null;if(-not $child.WaitForExit(3000)){$child.Kill();$child.WaitForExit()};$child.Dispose();$child=$null
 }
 $completed=$true
}finally{
 if($child){try{$child.CloseMainWindow()|Out-Null;if(-not $child.WaitForExit(2000)){$child.Kill();$child.WaitForExit()}}finally{$child.Dispose()}}
 $current=[CoveApp.Computer]::Position()
 if($completed -and [Math]::Abs($current.X-$last.X) -lt 3 -and [Math]::Abs($current.Y-$last.Y) -lt 3){[CoveApp.Computer]::Move($original.X,$original.Y)}
 $resolved=[IO.Path]::GetFullPath($testRoot)
 if($resolved.StartsWith($PSScriptRoot+'\mouse-test-',[StringComparison]::OrdinalIgnoreCase)){
  foreach($file in @($exe,$report)){if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}}
  [IO.Directory]::Delete($resolved,$false)
 }
}
