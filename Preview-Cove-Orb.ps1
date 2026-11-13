$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
. "$PSScriptRoot\CoveAppearance.ps1"
$view=New-Object Windows.Window
$view.Width=760;$view.Height=240;$view.WindowStyle='None';$view.ShowInTaskbar=$false;$view.ShowActivated=$false;$view.Background='#080E17'
$layout=New-Object Windows.Controls.Primitives.UniformGrid;$layout.Columns=5;$layout.Margin='16';$view.Content=$layout
$null=Set-CoveAccent $view '#67D9BE'
foreach($entry in @(@('Idle','Em espera'),@('Listening','Ouvindo'),@('Thinking','Pensando'),@('Speaking','Respondendo'),@('Paused','Pausado'))){
 $column=New-Object Windows.Controls.StackPanel;$column.VerticalAlignment='Center'
 $button=New-Object Windows.Controls.Button;$button.Width=108;$button.Height=108;$button.Background='#132A35';$button.Tag=$entry[0]
 $button.Template=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText("$PSScriptRoot\Cove-Orb.xaml"));$column.Children.Add($button)|Out-Null
 $label=New-Object Windows.Controls.TextBlock;$label.Text=$entry[1];$label.Foreground='#B4C9D8';$label.FontSize=12;$label.HorizontalAlignment='Center';$label.Margin='0,14,0,0';$column.Children.Add($label)|Out-Null
 $layout.Children.Add($column)|Out-Null
}
$timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[TimeSpan]::FromMilliseconds(1100)
$timer.Add_Tick({
 $timer.Stop();$view.UpdateLayout()
 $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(760,240,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($view)
 $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
 $file=[IO.File]::Create((Join-Path $PSScriptRoot 'preview-orb-states.png'));try{$encoder.Save($file)}finally{$file.Dispose()};$view.Close()
})
$view.Add_Loaded({$timer.Start()});$view.ShowDialog()|Out-Null
