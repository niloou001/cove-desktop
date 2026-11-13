$ErrorActionPreference='Stop'
. "$PSScriptRoot\CoveMessagePlanner.ps1"
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
$script:streamSpeechStarted=$false
$script:speechQueue.Clear();$script:streamBuffer=''
$early='Posso ajudar voce a organizar todas as tarefas de hoje com bastante cuidado'
$script:account.TextDeltas.Enqueue($early)
Update-StreamSpeech
if($script:speechQueue.Count -ne 1){throw 'Inicio sem pontuacao esperou mais de 60 caracteres'}
Update-StreamSpeech -Finish
if((($script:speechQueue.ToArray()) -join ' ') -cne $early){throw 'Inicio antecipado perdeu palavras'}
$script:speechQueue.Clear();$script:streamBuffer=''
$script:streamSpeechStarted=$false
$sentence=('palavra '*25).Trim()+'.'
$script:account.TextDeltas.Enqueue($sentence)
Update-StreamSpeech
if($script:speechQueue.Peek().Length -gt 60){throw 'Frase completa longa atrasou o primeiro trecho'}
Update-StreamSpeech -Finish
if((($script:speechQueue.ToArray()) -join ' ') -cne $sentence){throw 'Frase completa perdeu palavras'}
$script:speechQueue.Clear();$script:streamBuffer=''
$long=('palavra '*60).Trim()
$script:account.TextDeltas.Enqueue($long)
Update-StreamSpeech
if(-not $script:speechQueue.Count){throw 'Frase longa esperou ate o final'}
Update-StreamSpeech -Finish
if((($script:speechQueue.ToArray()) -join ' ') -cne $long){throw 'Frase longa alterada'}
$script:speechQueue.Clear();$script:streamBuffer='';$script:suppressSpeech=$false;$script:blockedChatSendClaim=$false
$voiceEngine=[pscustomobject]@{Stops=0};$voiceEngine|Add-Member ScriptMethod Stop {$this.Stops++}
$script:account.TextDeltas.Enqueue('Pronto, en')
Update-StreamSpeech
$script:account.TextDeltas.Enqueue('viei a mensagem para Ester.')
Update-StreamSpeech
if(-not $script:blockedChatSendClaim -or -not $script:suppressSpeech -or $script:speechQueue.Count -or $voiceEngine.Stops -ne 1){throw 'Stream falou uma confirmacao inventada de envio'}
'OK: primeira frase antecipada, texto completo, interrupcao e confirmacao inventada bloqueada antes da fala. Sem rede ou audio.'
