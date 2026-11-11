$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'CoveChatGPT.cs') -ReferencedAssemblies System.Net.Http,System.Web.Extensions,System.Security
function Expect-Failure([scriptblock]$code){$failed=$false;try{& $code}catch{$failed=$true};if(-not $failed){throw 'Entrada invalida foi aceita.'}}
$query=[CoveApp.ChatGPTAccount]::ParseQuery('?code=test%2Bvalue&state=abc&scope=openid+profile')
if($query['code'] -cne 'test+value' -or $query['scope'] -cne 'openid profile'){throw 'Retorno OAuth decodificado incorretamente.'}
Expect-Failure {[CoveApp.ChatGPTAccount]::ParseQuery('?state=a&state=b')}
if([CoveApp.ChatGPTAccount]::HasPermission('openid profile')){throw 'Login sem uso do plano foi aceito.'}
if([CoveApp.ChatGPTAccount]::HasPermission('not.chatgpt.tokens.use.direct')){throw 'Escopo parcial foi aceito.'}
if(-not [CoveApp.ChatGPTAccount]::HasPermission('openid chatgpt.tokens.use.direct resource.invoke')){throw 'Escopo correto foi recusado.'}
$claims=New-Object 'Collections.Generic.Dictionary[string,object]'
$claims['iss']='https://auth.openai.com';$claims['aud']='test-client';$claims['sub']='test-user';$claims['nonce']='test-nonce';$claims['exp']=2000
[CoveApp.ChatGPTAccount]::CheckClaims($claims,'test-client','test-nonce',1000)
Expect-Failure {[CoveApp.ChatGPTAccount]::CheckClaims($claims,'wrong-client','test-nonce',1000)}
Expect-Failure {[CoveApp.ChatGPTAccount]::CheckClaims($claims,'test-client','wrong-nonce',1000)}
Expect-Failure {[CoveApp.ChatGPTAccount]::CheckClaims($claims,'test-client','test-nonce',3000)}
$claims['iss']='https://example.org'
Expect-Failure {[CoveApp.ChatGPTAccount]::CheckClaims($claims,'test-client','test-nonce',1000)}
$output=New-Object Text.StringBuilder;$completed=$false
[CoveApp.ChatGPTAccount]::ProcessEvent('{"type":"response.output_text.delta","delta":"Ola"}',$output,[ref]$completed)
if($completed -or $output.ToString() -ne 'Ola'){throw 'Delta de resposta invalido.'}
Expect-Failure {[CoveApp.ChatGPTAccount]::ProcessEvent('{"type":"response.failed"}',$output,[ref]$completed)}
Expect-Failure {[CoveApp.ChatGPTAccount]::ProcessEvent('{"type":"response.incomplete"}',$output,[ref]$completed)}
[CoveApp.ChatGPTAccount]::ProcessEvent('{"type":"response.completed"}',$output,[ref]$completed)
if(-not $completed){throw 'Conclusao nao detectada.'}
$testRoot=Join-Path $PSScriptRoot ('test-auth-'+[guid]::NewGuid().ToString('N'))
$account=New-Object CoveApp.ChatGPTAccount($testRoot)
if($account.Connected){throw 'Conta recem-criada apareceu conectada.'}
$cancel=New-Object Threading.CancellationTokenSource;$cancel.Cancel()
$attempt=$account.SignIn($cancel.Token)
Expect-Failure {$attempt.GetAwaiter().GetResult()}
if(-not $attempt.IsCanceled){throw 'Login cancelado deveria parar antes de abrir o navegador.'}
$cancel.Dispose()
$hostFile=Join-Path $testRoot 'host.txt'
$hostBefore=[IO.File]::ReadAllText($hostFile)
$second=New-Object CoveApp.ChatGPTAccount($testRoot)
if([IO.File]::ReadAllText($hostFile) -cne $hostBefore){throw 'Identificador do host mudou.'}
# Remove only the exact files created by this test; no recursive deletion.
Remove-Item -LiteralPath $hostFile
Remove-Item -LiteralPath $testRoot
'OK: OAuth query, permissoes, identidade, stream, host e cancelamento.'
