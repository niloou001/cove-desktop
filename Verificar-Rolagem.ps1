$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$window=New-Object Windows.Window;$window.Width=320;$window.Height=220;$window.ShowActivated=$false;$window.ShowInTaskbar=$false
$window.Resources.MergedDictionaries.Add([Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText("$PSScriptRoot\Cove-Theme.xaml")))
$scroll=New-Object Windows.Controls.ScrollViewer;$scroll.VerticalScrollBarVisibility='Auto';$scroll.HorizontalScrollBarVisibility='Disabled'
$content=New-Object Windows.Controls.Border;$content.Height=1600;$scroll.Content=$content;$window.Content=$scroll
try{
 $window.Show();$window.UpdateLayout()
 $bar=$scroll.Template.FindName('PART_VerticalScrollBar',$scroll);$bar.ApplyTemplate()|Out-Null
 $track=$bar.Template.FindName('PART_Track',$bar)
 if(-not $track -or -not $bar.Template.FindName('ScrollGrip',$bar) -or $bar.ActualWidth -ne 12){throw ('Custom rounded scrollbar did not load: width='+$bar.ActualWidth)}
 $scroll.ScrollToVerticalOffset(500);$window.UpdateLayout()
 if($scroll.VerticalOffset -lt 499 -or $track.Value -lt 499){throw 'Scrollbar position no longer follows scroll content'}
 if($track.DecreaseRepeatButton.Command.Name -ne 'PageUp' -or $track.IncreaseRepeatButton.Command.Name -ne 'PageDown'){throw 'Vertical page navigation broken'}
 $bar.Orientation='Horizontal';$bar.ApplyTemplate()|Out-Null;$window.UpdateLayout()
 if($track.DecreaseRepeatButton.Command.Name -ne 'PageLeft' -or $track.IncreaseRepeatButton.Command.Name -ne 'PageRight'){throw 'Horizontal page navigation broken'}
 'OK: theme loads, 12px scrollbar, content offset sync and vertical/horizontal page navigation.'
}finally{$window.Close()}
