$ErrorActionPreference='Stop'
try{
 $python=Join-Path $PSScriptRoot 'assets\neural\python\python.exe'
 if(-not (Test-Path -LiteralPath $python)){throw 'Prepare as vozes naturais primeiro para instalar o ambiente local do Cove.'}
 $folder=Join-Path $PSScriptRoot 'assets\asr'
 New-Item -ItemType Directory -Path $folder -Force|Out-Null
 $lockPath=Join-Path $folder 'install.lock'
 try{$installLock=New-Object IO.FileStream($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw 'A instalacao da escuta ja esta em andamento.'}
 try{
  Write-Host 'Preparando o reconhecimento mais preciso em portugues. Download unico.' -ForegroundColor Cyan
  & $python -m pip install --disable-pip-version-check --no-warn-script-location --only-binary=:all: --index-url https://pypi.org/simple 'faster-whisper==1.2.1'
  if($LASTEXITCODE -ne 0){throw 'Nao foi possivel instalar o reconhecedor.'}
  $worker=Join-Path $PSScriptRoot 'cove_asr.py'
  $model=Join-Path $folder 'small'
  & $python $worker --model $model --download
  if($LASTEXITCODE -ne 0){throw 'Nao foi possivel baixar o modelo de reconhecimento.'}
  & $python $worker --model $model --check
  if($LASTEXITCODE -ne 0){throw 'O modelo nao passou no teste de carregamento e silencio.'}
  [IO.File]::WriteAllText((Join-Path $folder 'ready.txt'),'whisper-small-1.2.1',[Text.Encoding]::ASCII)
  Write-Host 'Pronto. Reinicie o Cove para usar a nova escuta.' -ForegroundColor Green
 }finally{$installLock.Dispose()}
 exit 0
}catch{Write-Host ('Falha na preparacao: '+$_.Exception.Message) -ForegroundColor Red;exit 1}
