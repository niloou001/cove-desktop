function ConvertTo-CoveShortcut([string]$Text){
 if([string]::IsNullOrWhiteSpace($Text)){return ''}
 try{$converter=New-Object Windows.Input.KeyGestureConverter;$gesture=$converter.ConvertFromInvariantString($Text.Trim())}catch{throw 'Use uma combinacao como Ctrl+Shift+M ou uma tecla de funcao, como F8.'}
 if($gesture.Key -eq [Windows.Input.Key]::None -or ($gesture.Modifiers -eq [Windows.Input.ModifierKeys]::None -and ($gesture.Key -lt [Windows.Input.Key]::F1 -or $gesture.Key -gt [Windows.Input.Key]::F24))){throw 'Use Ctrl, Alt ou uma tecla de funcao para nao acionar o atalho enquanto digita.'}
 return $converter.ConvertToInvariantString($gesture)
}
function Get-CoveShortcutSettings([string]$File=(Join-Path $PSScriptRoot 'cove-shortcuts.json')){
 $settings=[pscustomobject]@{Microphone='Ctrl+Shift+M';ClearConversation='Ctrl+Shift+L'}
 if(Test-Path -LiteralPath $File){try{
  $saved=Get-Content -LiteralPath $File -Raw|ConvertFrom-Json
  foreach($name in @('Microphone','ClearConversation')){if($saved.PSObject.Properties[$name] -and $saved.$name -is [string]){$settings.$name=ConvertTo-CoveShortcut $saved.$name}}
  if($settings.Microphone -and $settings.Microphone -eq $settings.ClearConversation){throw 'Duplicate shortcuts'}
 }catch{$settings=[pscustomobject]@{Microphone='Ctrl+Shift+M';ClearConversation='Ctrl+Shift+L'}}}
 return $settings
}
function Save-CoveShortcutSettings([string]$Microphone,[string]$ClearConversation,[string]$File=(Join-Path $PSScriptRoot 'cove-shortcuts.json')){
 $settings=[pscustomobject]@{Microphone=(ConvertTo-CoveShortcut $Microphone);ClearConversation=(ConvertTo-CoveShortcut $ClearConversation)}
 if($settings.Microphone -and $settings.Microphone -eq $settings.ClearConversation){throw 'Escolha combinacoes diferentes para cada acao.'}
 [IO.File]::WriteAllText($File,($settings|ConvertTo-Json),[Text.Encoding]::UTF8)
 return $settings
}
function Get-CoveShortcutAction($Settings,[Windows.Input.Key]$Key,[Windows.Input.ModifierKeys]$Modifiers){
 $converter=New-Object Windows.Input.KeyGestureConverter
 foreach($name in @('Microphone','ClearConversation')){if($Settings.$name){$gesture=$converter.ConvertFromInvariantString($Settings.$name);if($gesture.Key -eq $Key -and $gesture.Modifiers -eq $Modifiers){return $name}}}
 return ''
}
function Get-CoveMicrophoneRequest([string]$Text){
 $key=ConvertTo-CoveAppName (ConvertTo-CoveRequestLanguage $Text)
 $result=[pscustomobject]@{Handled=$false;Paused=$false}
 if($key -match '^(?:como|explique|me explica|se|caso|nao pause|nao desligue|nao desative)\b'){return $result}
 $microphone='(?:o |meu |a )?(?:microfone|mic|escuta)(?: (?:do|no|da|na) (?:cove|aplicativo|app|software))?'
 if($key -match ('^(?:pausa|pause|pausar|desativa|desative|desativar|desliga|desligue|desligar|silencia|silencie|silenciar|interrompe|interrompa) '+$microphone+'$') -or $key -match '^(?:para|pare|parar) de (?:me )?(?:ouvir|escutar)$|^nao (?:me )?(?:ouca|escute)(?: agora)?$'){$result.Handled=$true;$result.Paused=$true}
 elseif($key -match ('^(?:retoma|retome|retomar|ativa|ative|ativar|reativa|reative|reativar|liga|ligue|ligar|despausa|despause) '+$microphone+'$') -or $key -match '^(?:volta|volte|voltar) a (?:me )?(?:ouvir|escutar)$|^(?:pode )?me (?:ouvir|escutar) de novo$'){$result.Handled=$true}
 return $result
}
