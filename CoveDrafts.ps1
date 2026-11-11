function Show-CoveSavedDrafts {
 $draftWindow=[Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Rascunhos preservados" Width="540" Height="480" WindowStartupLocation="CenterOwner" Background="#101B29" Foreground="#E6EEF8" FontFamily="Segoe UI"><Grid Margin="22"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="130"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><TextBlock Text="Rascunhos guardados antes de substituir o texto" FontSize="16" TextWrapping="Wrap" Margin="0,0,0,12"/><ListBox x:Name="DraftList" Grid.Row="1" DisplayMemberPath="Label" Background="#172432" Foreground="#E6EEF8"/><TextBox x:Name="DraftText" Grid.Row="2" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Margin="0,12,0,12"/><DockPanel Grid.Row="3"><Button x:Name="CopyDraft" Content="Copiar texto" DockPanel.Dock="Right"/><TextBlock x:Name="DraftInfo" TextWrapping="Wrap" Foreground="#91A6BE" Margin="0,0,10,0"/></DockPanel></Grid></Window>
'@)
 $draftWindow.Owner=$chat;$draftWindow.Resources.MergedDictionaries.Add($theme)
 [CoveApp.Messaging]::DraftDirectory=Join-Path $PSScriptRoot '.cove-drafts'
 $list=$draftWindow.FindName('DraftList');$text=$draftWindow.FindName('DraftText');$info=$draftWindow.FindName('DraftInfo')
 try{$list.ItemsSource=@([CoveApp.Messaging]::ReadSavedDrafts());$info.Text='Selecione para ler. As copias ficam protegidas neste usuario do Windows.'}catch{$info.Text='Nao consegui abrir os rascunhos protegidos neste perfil do Windows.'}
 $list.Add_SelectionChanged({if($list.SelectedItem){$text.Text=$list.SelectedItem.Text}})
 $draftWindow.FindName('CopyDraft').Add_Click({if($list.SelectedItem){[Windows.Clipboard]::SetText($list.SelectedItem.Text);$info.Text='Texto copiado.'}})
 if($SmokeTest){$draftTimer=New-Object Windows.Threading.DispatcherTimer;$draftTimer.Interval=[TimeSpan]::FromMilliseconds(250);$draftTimer.Add_Tick({$draftTimer.Stop();$draftWindow.Close()});$draftTimer.Start()}
 $draftWindow.ShowDialog()|Out-Null
}
