$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
try{
 if(-not [Environment]::Is64BitProcess){throw 'As vozes precisam do Windows de 64 bits.'}
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $assets=Join-Path $PSScriptRoot 'assets\neural'
 $runtime=Join-Path $assets 'python'
 New-Item -ItemType Directory -Path $assets -Force|Out-Null
 $lockFile=Join-Path $assets 'install.lock'
 try{$installLock=New-Object IO.FileStream($lockFile,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw 'Outra janela ja esta preparando as vozes. Aguarde ela terminar.'}
 try{
  function Get-VoiceFile([string]$url,[string]$destination,[long]$minimum){
   if((Test-Path -LiteralPath $destination) -and (Get-Item -LiteralPath $destination).Length -ge $minimum){return}
   $part=$destination+'.part'
   Invoke-WebRequest -Uri $url -OutFile $part -UseBasicParsing -TimeoutSec 1200
   if((Get-Item -LiteralPath $part).Length -lt $minimum){throw ('Download incompleto: '+[IO.Path]::GetFileName($destination))}
   Move-Item -LiteralPath $part -Destination $destination -Force
  }
  Write-Host 'Preparando Serena e Atlas: vozes neurais locais em portugues.' -ForegroundColor Cyan
  Write-Host 'O download unico pode levar alguns minutos e usa algumas centenas de MB.'
  Write-Host 'Depois, a geracao da voz funciona sem enviar seus textos a outro servico.'
  $python=Join-Path $runtime 'python.exe'
  if(-not (Test-Path -LiteralPath $python)){
   Write-Host '[1/4] Baixando o ambiente de voz...'
   $archive=Join-Path $assets 'python.zip'
   Get-VoiceFile 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip' $archive 5000000
   $stage=Join-Path $assets ('python-'+[guid]::NewGuid().ToString('N'))
   [IO.Compression.ZipFile]::ExtractToDirectory($archive,$stage)
   if(-not (Test-Path -LiteralPath (Join-Path $stage 'python.exe'))){throw 'O ambiente Python nao foi extraido corretamente.'}
   if(Test-Path -LiteralPath $runtime){throw 'Existe uma instalacao parcial em assets\neural\python. Renomeie essa pasta e tente novamente.'}
   Move-Item -LiteralPath $stage -Destination $runtime
  }
  $pth=Join-Path $runtime 'python312._pth'
  [IO.File]::WriteAllText($pth,"python312.zip`r`n.`r`nLib\site-packages`r`nimport site`r`n",[Text.Encoding]::ASCII)
  if(-not (Test-Path -LiteralPath (Join-Path $runtime 'Lib\site-packages\pip\__init__.py'))){
   $getPip=Join-Path $assets 'get-pip.py'
   Get-VoiceFile 'https://bootstrap.pypa.io/get-pip.py' $getPip 100000
   & $python $getPip --no-warn-script-location --disable-pip-version-check --index-url https://pypi.org/simple
   if($LASTEXITCODE -ne 0){throw 'Nao foi possivel preparar o instalador de dependencias.'}
  }
  Write-Host '[2/4] Instalando o mecanismo neural...'
  & $python -m pip install --disable-pip-version-check --no-warn-script-location --only-binary=:all: --index-url https://pypi.org/simple 'kokoro-onnx==0.6.1'
  if($LASTEXITCODE -ne 0){throw 'Nao foi possivel instalar o mecanismo de voz. Confira a conexao com a internet.'}
  Write-Host '[3/4] Baixando o modelo e as vozes...'
  Get-VoiceFile 'https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/kokoro-v1.0.onnx' (Join-Path $assets 'kokoro-v1.0.onnx') 100000000
  Get-VoiceFile 'https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/voices-v1.0.bin' (Join-Path $assets 'voices-v1.0.bin') 1000000
  Write-Host '[4/4] Testando as duas vozes. Aguarde...'
  & $python -m py_compile (Join-Path $PSScriptRoot 'cove_neural.py')
  if($LASTEXITCODE -ne 0){throw 'O programa de voz nao passou na verificacao de sintaxe.'}
  & $python -u (Join-Path $PSScriptRoot 'cove_neural.py') --assets $assets --check
  if($LASTEXITCODE -ne 0){throw 'Os arquivos foram baixados, mas o teste de geracao de audio falhou.'}
  [IO.File]::WriteAllText((Join-Path $assets 'ready.txt'),'kokoro-0.6.1;serena;atlas',[Text.Encoding]::ASCII)
  Write-Host 'Pronto! Serena e Atlas estao disponiveis no Cove.' -ForegroundColor Green
 }finally{$installLock.Dispose()}
 exit 0
}catch{
 Write-Host ('Nao foi possivel preparar as vozes: '+$_.Exception.Message) -ForegroundColor Red
 Write-Host 'Guarde a mensagem acima. Os downloads completos serao reaproveitados na proxima tentativa.'
 exit 1
}
