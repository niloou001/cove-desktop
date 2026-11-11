$ErrorActionPreference='Stop'
$tokens=$null;$problems=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Cove-Voice.ps1'),[ref]$tokens,[ref]$problems)
if($problems.Count){throw ($problems|Out-String)}
$function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Update-StreamSpeech'},$true)
. ([scriptblock]::Create($function.Extent.Text))
$script:account=[pscustomobject]@{TextDeltas=(New-Object 'Collections.Concurrent.ConcurrentQueue[string]')}
$script:speechQueue=New-Object 'Collections.Generic.Queue[string]'
$script:streamActive=$true;$script:streamHadText=$false;$script:suppressSpeech=$false;$script:streamBuffer=''
$script:account.TextDeltas.Enqueue('Vou ajudar voce. Ainda estou')
Update-StreamSpeech
if($script:speechQueue.Count -ne 1 -or $script:speechQueue.Peek() -cne 'Vou ajudar voce.'){throw 'Primeira frase nao foi antecipada'}
if($script:streamBuffer -cne 'Ainda estou'){throw 'Texto incompleto perdido'}
$script:account.TextDeltas.Enqueue(' preparando a resposta. E este e o final')
Update-StreamSpeech -Finish
$complete=($script:speechQueue.ToArray()) -join ' '
if($complete -cne 'Vou ajudar voce. Ainda estou preparando a resposta. E este e o final'){throw 'Frases repetidas ou perdidas'}
if(-not $script:streamHadText -or $script:streamBuffer){throw 'Estado final incorreto'}
$script:suppressSpeech=$true
$script:account.TextDeltas.Enqueue('Esta parte nao pode ser falada.')
Update-StreamSpeech -Finish
if($script:speechQueue.Count -or $script:streamBuffer -or -not $script:account.TextDeltas.IsEmpty){throw 'Interrupcao deixou falas pendentes'}
$script:suppressSpeech=$false
$long=('palavra '*60).Trim()
$script:account.TextDeltas.Enqueue($long)
Update-StreamSpeech
if(-not $script:speechQueue.Count){throw 'Frase longa esperou ate o final'}
Update-StreamSpeech -Finish
if((($script:speechQueue.ToArray()) -join ' ') -cne $long){throw 'Frase longa alterada'}
'OK: primeira frase antecipada, final completo sem repeticao, frases longas e interrupcao da fila. Sem chamadas de rede ou reproducao de audio.'
