function Update-CoveConversation {
 if(-not $chat -or -not $transcript){return}
 $list=$chat.FindName('MessageList');if(-not $list){return};$list.Children.Clear()
 $entries=[regex]::Matches($transcript.Text,'(?ms)^(Voce|Cove): (.*?)(?=^(?:Voce|Cove): |\z)')
 foreach($entry in @($entries|Select-Object -Last 80)){
  $mine=$entry.Groups[1].Value -eq 'Voce';$text=$entry.Groups[2].Value.TrimEnd([char[]]"`r`n")
  $row=New-Object Windows.Controls.Border;$row.MaxWidth=430;$row.Margin='0,0,0,14';$row.Padding='16,12';$row.CornerRadius=if($mine){'18,18,5,18'}else{'18,18,18,5'}
  $row.HorizontalAlignment=if($mine){'Right'}else{'Left'};$row.Background=if($mine){'#263B49'}else{'#17232F'};$row.BorderThickness='1';$row.BorderBrush=if($mine){'#405965'}else{'#293B49'}
  if($mine -and $script:appearance -and $script:appearance.Palette){$row.Background=$script:appearance.Palette.Idle;$row.BorderBrush=$script:appearance.Hex}
  $content=New-Object Windows.Controls.StackPanel
  $author=New-Object Windows.Controls.TextBlock;$author.Text=if($mine){'VOCE'}elseif($script:assistantName){$script:assistantName.ToUpperInvariant()}else{'COVE'};$author.FontSize=10;$author.FontWeight='SemiBold';$author.Foreground=if($mine){'#ADC2CE'}else{'#BEE5DC'};$author.Margin='0,0,0,7'
  $body=New-Object Windows.Controls.TextBox;$body.Text=$text;$body.IsReadOnly=$true;$body.TextWrapping='Wrap';$body.AcceptsReturn=$true;$body.BorderThickness='0';$body.Background='Transparent';$body.Padding='0';$body.FontSize=14;$body.Foreground='#E5EDF4';$body.IsReadOnlyCaretVisible=$false
  $content.Children.Add($author)|Out-Null;$content.Children.Add($body)|Out-Null;$row.Child=$content;$list.Children.Add($row)|Out-Null
 }
 $chat.FindName('MessageScroll').ScrollToEnd()
 if($list.Children.Count){$last=$list.Children[$list.Children.Count-1];$fade=New-Object Windows.Media.Animation.DoubleAnimation(0,1,[Windows.Duration]::new([TimeSpan]::FromMilliseconds(140)));$last.BeginAnimation([Windows.UIElement]::OpacityProperty,$fade)}
}
