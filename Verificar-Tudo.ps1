param([string[]]$Only)
$ErrorActionPreference='Stop'
$folder=Join-Path $PSScriptRoot '.cove-audit'
[IO.Directory]::CreateDirectory($folder)|Out-Null
$skip=@('Verificar-Tudo.ps1','Verificar-Entrada-CAPS-Real.ps1','Verificar-Cove-Visivel.ps1','Verificar-Cove-Em-Execucao.ps1')
$results=@()
foreach($test in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'Verificar-*.ps1'|Sort-Object Name)){
 if($test.Name -in $skip -or ($Only -and $test.Name -notin $Only)){continue}
 $out=Join-Path $folder ($test.BaseName+'.out.txt');$err=Join-Path $folder ($test.BaseName+'.err.txt')
 $p=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "'+$test.FullName+'"') -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
 $processHandle=$p.Handle
 $done=$p.WaitForExit(60000)
 if(-not $done){$p.Kill();$p.WaitForExit()}
 $code=$p.ExitCode
 $record=[pscustomobject]@{Test=$test.Name;Passed=($done -and $code -eq 0);ExitCode=$code;Timeout=(-not $done);Output=([IO.File]::ReadAllText($out)+[IO.File]::ReadAllText($err))}
 $results+=@($record);$p.Dispose()
 [IO.File]::WriteAllText((Join-Path $folder 'results.json'),($results|ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding $true))
 if($record.Passed){'PASS '+$test.Name}else{'FAIL '+$test.Name+' '+$record.Output.Substring(0,[Math]::Min(350,$record.Output.Length))}
}
if(@($results|Where-Object {-not $_.Passed}).Count){exit 1}
