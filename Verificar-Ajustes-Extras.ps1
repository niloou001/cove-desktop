$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
. "$PSScriptRoot\CoveApps.ps1"
. "$PSScriptRoot\CoveAppearance.ps1"
. "$PSScriptRoot\CoveDiscordLinks.ps1"
$source=[IO.File]::ReadAllText("$PSScriptRoot\Cove-Voice.ps1")
$start=$source.IndexOf('function Show-Settings')
$begin=$source.IndexOf("<Window ",$start)
$end=$source.IndexOf("'@)",$begin)
$dialog=[Windows.Markup.XamlReader]::Parse($source.Substring($begin,$end-$begin))
$dialog.Resources.MergedDictionaries.Add([Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText("$PSScriptRoot\Cove-Theme.xaml")))
$window=New-Object Windows.Window;$orb=New-Object Windows.Controls.Button;$window.Content=$orb;$glow=New-Object Windows.Media.Effects.DropShadowEffect
$colorFile=Join-Path $PSScriptRoot ('settings-color-test-'+[guid]::NewGuid().ToString('N')+'.json')
$linkFile=Join-Path $PSScriptRoot ('settings-link-test-'+[guid]::NewGuid().ToString('N')+'.json')
$script:appearance=[pscustomobject]@{File=$colorFile;Hex='#67D9BE';Palette=(Set-CoveAccent $window '#67D9BE')}
$script:coveDiscordLinksFile=$linkFile;$script:pendingLinkTarget=$null
function Click-Control([string]$Name){$dialog.FindName($Name).RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))}
try{
 . "$PSScriptRoot\CoveSettingsExtras.ps1"
 if($dialog.FindName('AccentSwatches').Children.Count -ne 6){throw 'Color swatches missing'}
 $swatch=$dialog.FindName('AccentSwatches').Children[1]
 $swatch.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
 if($dialog.FindName('AccentHex').Text -cne '#5AA9EA' -or $dialog.FindName('AccentList').SelectedItem -cne 'Oceano'){throw 'Swatch did not select matching color'}
 if($dialog.FindName('AccentList').DisplayMemberPath){throw 'String palette entries must not use a missing display property'}
 $dialog.FindName('AccentHex').Text='#123456'
 if($dialog.FindName('AccentList').SelectedItem -cne 'Personalizada'){throw 'Custom color left an empty palette label'}
 $dialog.FindName('AccentList').SelectedItem='Violeta'
 if($dialog.FindName('AccentHex').Text -cne '#A78BFA'){throw 'Preset event did not fill the color field'}
 Click-Control 'ApplyAccent'
 if($script:appearance.Hex -cne '#A78BFA' -or (Get-CoveAccent $colorFile) -cne '#A78BFA'){throw 'Apply color did not persist'}
 $dialog.FindName('AccentHex').Text='bad';Click-Control 'ApplyAccent'
 if((Get-CoveAccent $colorFile) -cne '#A78BFA'){throw 'Invalid color overwrote preference'}
 $dialog.FindName('CallServer').Text='CAPS';$dialog.FindName('CallChannel').Text='Geral';$dialog.FindName('CallLink').Text='https://discord.com/channels/123456789012345678/234567890123456789'
 Click-Control 'SaveCallLink'
 if((Get-CoveDiscordLinks).Channels.Count -ne 1){throw ('Save channel failed: '+$dialog.FindName('CallStatus').Text)}
 $dialog.FindName('DiscordMethod').SelectedIndex=2
 if((Get-CoveDiscordLinks).Method -cne 'interface'){throw 'Method choice did not save'}
 $dialog.FindName('SavedCalls').SelectedIndex=0;Click-Control 'RemoveCallLink'
 if((Get-CoveDiscordLinks).Channels.Count){throw 'Remove saved channel failed'}
 'OK: real settings callbacks for preset, apply/save color, invalid input, save/remove call and method choice. No real call opened.'
}finally{
 $dialog.Close();$window.Close()
 foreach($file in @($colorFile,$linkFile)){if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}}
}
