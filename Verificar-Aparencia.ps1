$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
. "$PSScriptRoot\CoveAppearance.ps1"
$window=New-Object Windows.Window
$orb=New-Object Windows.Controls.Button
$window.Content=$orb;$orb.Width=108;$orb.Height=108
$orb.Template=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText("$PSScriptRoot\Cove-Orb.xaml"))
$palette=Set-CoveAccent $window '#FF0000'
$orb.ApplyTemplate()|Out-Null
$liquid=$orb.Template.FindName('Liquid',$orb)
if($liquid.Children[0].Fill.GradientStops[0].Color.R -ne 255 -or $liquid.Children[0].Fill.GradientStops[0].Color.B -ne 0){throw 'Initial orb color did not bind'}
$palette=Set-CoveAccent $window '#0000FF'
if($liquid.Children[0].Fill.GradientStops[0].Color.R -ne 0 -or $liquid.Children[0].Fill.GradientStops[0].Color.B -ne 255){throw 'Orb color did not update live'}
foreach($hex in @('#67D9BE','#5AA9EA','#A78BFA','#F08DB7','#E9BD6A','#F58C7A')){
 $palette=Set-CoveAccent $window $hex
 if($palette.Hex -cne $hex){throw 'Preset failed'}
}
$failed=$false;try{Set-CoveAccent $window 'invalid'|Out-Null}catch{$failed=$true};if(-not $failed){throw 'Invalid color accepted'}
$file=Join-Path $PSScriptRoot ('appearance-test-'+[guid]::NewGuid().ToString('N')+'.json')
try{
 [IO.File]::WriteAllText($file,'{"Accent":"#F08DB7"}',[Text.Encoding]::UTF8)
 if((Get-CoveAccent $file) -cne '#F08DB7'){throw 'Saved color not loaded'}
 [IO.File]::WriteAllText($file,'{"Accent":"bad"}',[Text.Encoding]::UTF8)
 if((Get-CoveAccent $file) -cne '#67D9BE'){throw 'Invalid preference did not fall back'}
}finally{if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file};$window.Close()}
'OK: live orb resources, all presets, validation and saved color loading.'
