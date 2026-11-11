$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
. "$PSScriptRoot\CoveConversation.ps1"
$source=[IO.File]::ReadAllText("$PSScriptRoot\Cove-Voice.ps1")
$start=$source.IndexOf('$chat=[Windows.Markup.XamlReader]::Parse(')
$begin=$source.IndexOf('<Window ',$start);$end=$source.IndexOf("'@)",$begin)
$chat=[Windows.Markup.XamlReader]::Parse($source.Substring($begin,$end-$begin))
$chat.Resources.MergedDictionaries.Add([Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText("$PSScriptRoot\Cove-Theme.xaml")))
$transcript=$chat.FindName('Transcript')
try{
 $transcript.Text="Voce: Texto de teste.`r`n`r`nCove: Resposta de teste, com duas linhas.`r`nSegunda linha.`r`n`r`n"
 Update-CoveConversation
 $rows=$chat.FindName('MessageList').Children
 if($rows.Count -ne 2 -or $rows[0].HorizontalAlignment -ne 'Right' -or $rows[1].HorizontalAlignment -ne 'Left'){throw 'Message roles/alignment'}
 if($rows[1].Child.Children[1].Text -notlike '*Segunda linha.*' -or -not $rows[1].Child.Children[1].IsReadOnly){throw 'Multiline/read-only copyable text'}
 $raw=$transcript.Text;Update-CoveConversation;if($transcript.Text -cne $raw){throw 'UI changed conversation history'}
 $transcript.Clear();Update-CoveConversation;if($rows.Count){throw 'Clear left bubbles visible'}
 'OK: chat XAML, separate message bubbles, alignment, multiline text, copyable read-only content, history preserved and clear.'
}finally{$chat.Close()}
