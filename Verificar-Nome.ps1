$ErrorActionPreference='Stop'
. "$PSScriptRoot\CoveIdentity.ps1"
$originalFile=$script:coveIdentityFile;$originalName=$script:assistantName
$test=Join-Path $PSScriptRoot ('name-test-'+[guid]::NewGuid().ToString('N')+'.json')
try{
 $script:coveIdentityFile=$test
 if((Get-CoveAssistantName) -cne 'Cove'){throw 'Default name'}
 Set-CoveAssistantName '  Luma  ' |Out-Null
 if($script:assistantName -cne 'Luma' -or (Get-CoveAssistantName) -cne 'Luma'){throw 'Custom name not applied/persisted'}
 Set-CoveAssistantName 'J.A.R.V.I.S'|Out-Null
 if((Get-CoveAssistantName) -cne 'J.A.R.V.I.S'){throw 'Existing name replacement failed'}
 foreach($bad in @('','---','<script>',('a'*25))){
  $blocked=$false;try{Set-CoveAssistantName $bad|Out-Null}catch{$blocked=$true}
  if(-not $blocked -or (Get-CoveAssistantName) -cne 'J.A.R.V.I.S'){throw 'Invalid name changed saved name'}
 }
 $tokens=$null;$issues=$null;$ast=[Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot\Cove-Voice.ps1",[ref]$tokens,[ref]$issues)
 if($issues.Count){throw ($issues|Out-String)}
 Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
 $source=[IO.File]::ReadAllText("$PSScriptRoot\Cove-Voice.ps1");$start=$source.IndexOf('function Show-Settings');$begin=$source.IndexOf('<Window ',$start);$end=$source.IndexOf("'@)",$begin)
 $dialog=[Windows.Markup.XamlReader]::Parse($source.Substring($begin,$end-$begin))
 if(-not $dialog.FindName('AssistantName') -or -not $dialog.FindName('SaveAssistantName') -or -not $dialog.FindName('ResetAssistantName')){throw 'Name controls missing'}
 $start=$source.IndexOf('$chat=[Windows.Markup.XamlReader]::Parse(');$begin=$source.IndexOf('<Window ',$start);$end=$source.IndexOf("'@)",$begin)
 $chat=[Windows.Markup.XamlReader]::Parse($source.Substring($begin,$end-$begin))
 $transcript=$chat.FindName('Transcript');$transcript.Text="Cove: Texto de teste.`r`n`r`n"
 . "$PSScriptRoot\CoveConversation.ps1"
 Update-CoveConversation
 if($chat.FindName('MessageList').Children[0].Child.Children[0].Text -cne 'J.A.R.V.I.S'){throw 'Bubble ignores custom name'}
 foreach($button in @('SaveAssistantName','ResetAssistantName')){
  $node=$ast.Find({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'Add_Click' -and $n.Expression.Extent.Text -like "*FindName('$button')*"},$true)
  if(-not $node){throw 'Missing name handler'}
  $block=$node.Arguments[0].ScriptBlock.GetScriptBlock()
  $dialog.FindName('AssistantName').Text='Luna'
  & $block
  $expected=if($button -eq 'SaveAssistantName'){'Luna'}else{'Cove'}
  if((Get-CoveAssistantName) -cne $expected -or $chat.FindName('AssistantTitle').Text -cne $expected){throw "Name callback failed: $button"}
 }
 $dialog.Close();$chat.Close()
 'OK: default, name validation, atomic save/reload, custom message labels and real save/reset callbacks. Test preference file only.'
}finally{$script:coveIdentityFile=$originalFile;$script:assistantName=$originalName;if(Test-Path -LiteralPath $test){Remove-Item -LiteralPath $test}}
