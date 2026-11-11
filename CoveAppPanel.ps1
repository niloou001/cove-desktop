function Show-CoveApplications {
 $dialog=[Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Apps do Cove" Width="470" Height="590" WindowStartupLocation="CenterOwner" WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True" Background="Transparent" Foreground="#E6EEF8" FontFamily="Segoe UI"><Border Background="#0E1927" BorderBrush="#2A3B50" BorderThickness="1" CornerRadius="24" Padding="24"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<StackPanel Margin="0,0,0,16"><DockPanel x:Name="AppsHeader" Background="Transparent"><Button x:Name="CloseApps" Content="&#x00D7;" DockPanel.Dock="Right" Width="30" Height="30" Padding="0" Background="Transparent" BorderThickness="0"/><TextBlock Text="Apps e jogos" FontSize="23" FontWeight="SemiBold"/></DockPanel><TextBlock Text="Jogos da Steam e Epic, apps do Windows e atalhos. Diga: abre NOME. Para um jogo portatil, cadastre o executavel abaixo." TextWrapping="Wrap" Foreground="#91A6BE" FontSize="12" Margin="0,10,0,0"/></StackPanel>
<Border Grid.Row="1" Background="#142131" CornerRadius="16" Padding="10"><ListBox x:Name="AppsList" DisplayMemberPath="Name" Background="Transparent" Foreground="#E6EEF8" BorderThickness="0"><ListBox.Resources><Style TargetType="ListBoxItem"><Setter Property="Padding" Value="10,8"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem"><Border x:Name="Item" CornerRadius="10" Padding="{TemplateBinding Padding}" Background="Transparent"><ContentPresenter/></Border><ControlTemplate.Triggers><Trigger Property="IsSelected" Value="True"><Setter TargetName="Item" Property="Background" Value="#235D74"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style></ListBox.Resources></ListBox></Border>
<StackPanel Grid.Row="2" Margin="0,16,0,0"><Button x:Name="OpenSelected" Content="Abrir selecionado" Background="#235D74" BorderBrush="#397D91" Margin="0,0,0,14"/><TextBlock Text="Adicionar outro app" FontSize="15"/><Button x:Name="ChooseApp" Content="Escolher aplicativo ou atalho" Background="Transparent" Margin="0,10,0,0"/><TextBlock x:Name="AppPath" Text="Escolha um arquivo .exe ou atalho .lnk." Foreground="#91A6BE" FontSize="11" TextTrimming="CharacterEllipsis" Margin="0,8,0,8"/><TextBox x:Name="AppName" ToolTip="Nome que voce vai dizer para abrir o app"/><WrapPanel Margin="0,10,0,0"><Button x:Name="SaveApp" Content="Adicionar" Background="#235D74" BorderBrush="#397D91"/><Button x:Name="RemoveApp" Content="Remover cadastro" Margin="8,0,0,0" Background="Transparent" IsEnabled="False"/></WrapPanel><TextBlock x:Name="AppStatus" Foreground="#91A6BE" FontSize="11" TextWrapping="Wrap" Margin="0,12,0,0"/></StackPanel>
</Grid></Border></Window>
'@)
 $dialog.Resources.MergedDictionaries.Add($theme);$dialog.Owner=$chat
 $list=$dialog.FindName('AppsList');$appName=$dialog.FindName('AppName');$appPath=$dialog.FindName('AppPath');$appStatus=$dialog.FindName('AppStatus');$remove=$dialog.FindName('RemoveApp')
 $list.ItemsSource=@(Get-CoveApplications)
 $dialog.FindName('OpenSelected').Add_Click({
  if($list.SelectedItem){$result=Invoke-CoveAppRequest ('abra '+$list.SelectedItem.Name) -DryRun:$SmokeTest;$appStatus.Text=$result.Message}
  else{$appStatus.Text='Escolha um aplicativo na lista primeiro.'}
 })
 $dialog.FindName('CloseApps').Add_Click({$dialog.Close()})
 $dialog.FindName('AppsHeader').Add_MouseLeftButtonDown({param($sender,$eventArgs) if($eventArgs.OriginalSource -is [Windows.Controls.TextBlock]){$dialog.DragMove()}})
 $dialog.FindName('ChooseApp').Add_Click({
  $picker=New-Object Microsoft.Win32.OpenFileDialog
  $picker.Title='Escolha o aplicativo que o Cove pode abrir'
  $picker.Filter='Aplicativos e atalhos (*.exe;*.lnk)|*.exe;*.lnk'
  $picker.CheckFileExists=$true;$picker.DereferenceLinks=$false
  if($picker.ShowDialog($dialog)){$appName.Tag=$picker.FileName;$appName.Text=[IO.Path]::GetFileNameWithoutExtension($picker.FileName);$appPath.Text=$picker.FileName;$appStatus.Text='Escolha um nome facil de falar e clique em Adicionar.'}
 })
 $dialog.FindName('SaveApp').Add_Click({
  try{
   Add-CoveApplication $appName.Text ([string]$appName.Tag)
   $list.ItemsSource=@(Get-CoveApplications);$appStatus.Text='Adicionado. Diga: abre '+$appName.Text+'.'
   $appName.Clear();$appName.Tag=$null;$appPath.Text='Escolha um arquivo .exe ou atalho .lnk.'
  }catch{$appStatus.Text=$_.Exception.Message}
 })
 $list.Add_SelectionChanged({$remove.IsEnabled=$null -ne $list.SelectedItem -and $list.SelectedItem.Custom;if($list.SelectedItem){$appStatus.Text='Diga: abre '+$list.SelectedItem.Name+'.'}})
 $remove.Add_Click({
  if($list.SelectedItem -and $list.SelectedItem.Custom){
   $selected=$list.SelectedItem
   Save-CoveCustomApps @(Get-CoveApplications|Where-Object{-not ($_.Custom -and $_.Name -eq $selected.Name -and $_.Path -eq $selected.Path)})
   $list.ItemsSource=@(Get-CoveApplications);$appStatus.Text='Cadastro removido. O aplicativo continua instalado.'
  }
 })
 if($SmokeTest){$appTimer=New-Object Windows.Threading.DispatcherTimer;$appTimer.Interval=[TimeSpan]::FromMilliseconds(500);$appTimer.Add_Tick({$appTimer.Stop();$dialog.Close()});$appTimer.Start()}
 $dialog.ShowDialog()|Out-Null
}
