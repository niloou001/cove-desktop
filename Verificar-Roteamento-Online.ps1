$ErrorActionPreference='Stop'
. "$PSScriptRoot\CoveApps.ps1"
. "$PSScriptRoot\CoveDiscord.ps1"
. "$PSScriptRoot\CoveMessages.ps1"
. "$PSScriptRoot\CoveMessagePlanner.ps1"
function Write-CoveActionTrace {}
. "$PSScriptRoot\CoveOnline.ps1"
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot\Cove-Voice.ps1",[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Ask-Cove'},$true)
. ([scriptblock]::Create($node.Extent.Text))
function Invoke-CoveComputerRequest {return [pscustomobject]@{Handled=$false}}
function Invoke-CoveFileRequest {return [pscustomobject]@{Handled=$false}}
function Invoke-CoveAppRequest {throw 'Local request fell through to app lookup'}
function Add-Message {param($Who,$Text) $script:observed+=@($Text)}
function Say {param($Text) $script:observed+=@($Text)}
function Update-Capture {}
function Get-CoveChromePath {return 'C:\fixture\chrome.exe'}
$voiceEngine=[pscustomobject]@{};$voiceEngine|Add-Member ScriptMethod Stop {}
$script:speechQueue=New-Object 'Collections.Generic.Queue[string]'
$SmokeTest=$true;$script:account=$null;$script:mode='chatgpt';$script:task=$null;$script:discordTask=$null;$script:loginTask=$null;$script:transcribeTask=$null
foreach($phrase in @('que horas sao','noticias de hoje','qual a temperatura em Recife','pesquise sobre aves no Chrome','faca uma ligacao para Joao no Discord','mande mensagem para Ester no WhatsApp dizendo oi','mande mensagem para Ester no Discord dizendo entre na call geral')){
 $script:observed=@();Ask-Cove $phrase
 if($script:observed.Count -lt 2 -or $script:observed -match 'nao consigo iniciar|Cadastre uma chave|Entre em Ajustes'){throw "Local request reached AI/account: $phrase"}
 if($script:discordCancel){$script:discordCancel.Dispose();$script:discordCancel=$null}
}
'OK: actual Ask-Cove routes time, news, weather, Chrome search and natural private calls locally, before AI/account fallback. No real call/browser/network action.'
