$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    if (-not [Environment]::Is64BitProcess) { throw 'Use o PowerShell de 64 bits para preparar o Cove.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $assets = Join-Path $PSScriptRoot 'assets'
    New-Item -ItemType Directory -Path $assets -Force | Out-Null
    try{$installLock=New-Object IO.FileStream((Join-Path $assets 'microphone-install.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw 'A preparacao da escuta local ja esta em andamento. Aguarde terminar.'}
    function Get-Archive($uri, $destination) {
        $part = $destination + '.part'
        Invoke-WebRequest -Uri $uri -OutFile $part -UseBasicParsing -TimeoutSec 240
        Move-Item -LiteralPath $part -Destination $destination -Force
    }
    if (-not (Test-Path -LiteralPath (Join-Path $assets 'native\libvosk.dll'))) {
        Write-Host 'Baixando o reconhecimento local de voz (Vosk)...'
        $archive = Join-Path $assets 'vosk.nupkg'
        Get-Archive 'https://api.nuget.org/v3-flatcontainer/vosk/0.3.38/vosk.0.3.38.nupkg' $archive
        $package = Join-Path $assets ('package-' + [guid]::NewGuid().ToString('N'))
        [IO.Compression.ZipFile]::ExtractToDirectory($archive, $package)
        $lib = Get-ChildItem -LiteralPath $package -Filter libvosk.dll -Recurse | Where-Object { $_.FullName -match 'win-x64|win64' } | Select-Object -First 1
        if (-not $lib) { throw 'Biblioteca de Windows 64 bits nao encontrada no pacote Vosk.' }
        $native = Join-Path $assets 'native'
        New-Item -ItemType Directory -Path $native -Force | Out-Null
        Get-ChildItem -LiteralPath $lib.DirectoryName -File | Copy-Item -Destination $native -Force
    }
    $model = Join-Path $assets 'vosk-model-small-pt-0.3'
    if (-not (Test-Path -LiteralPath (Join-Path $model 'final.mdl')) -and -not (Test-Path -LiteralPath (Join-Path $model 'am\final.mdl'))) {
        $archive = Join-Path $assets 'portugues.zip'
        if (-not (Test-Path -LiteralPath $archive)) {
            Write-Host 'Baixando o modelo de portugues (cerca de 31 MB)...'
            Get-Archive 'https://alphacephei.com/vosk/models/vosk-model-small-pt-0.3.zip' $archive
        } else { Write-Host 'Aproveitando o modelo de portugues ja baixado...' }
        $stage = Join-Path $assets ('model-' + [guid]::NewGuid().ToString('N'))
        [IO.Compression.ZipFile]::ExtractToDirectory($archive, $stage)
        $source = Join-Path $stage 'vosk-model-small-pt-0.3'
        if (-not (Test-Path -LiteralPath (Join-Path $source 'final.mdl')) -and -not (Test-Path -LiteralPath (Join-Path $source 'am\final.mdl'))) { throw 'O ZIP nao contem o arquivo final.mdl do modelo. Confira assets\portugues.zip.' }
        if (Test-Path -LiteralPath $model) {
            $preserved=[IO.Path]::GetFullPath($model+'.incomplete-'+[guid]::NewGuid().ToString('N'))
            if([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($model)) -ne [IO.Path]::GetFullPath($assets) -or [IO.Path]::GetDirectoryName($preserved) -ne [IO.Path]::GetFullPath($assets)){throw 'Destino de recuperacao do modelo invalido.'}
            Move-Item -LiteralPath $model -Destination $preserved
        }
        Move-Item -LiteralPath $source -Destination $model
    }
    Write-Host 'Pronto. O Cove ja pode usar reconhecimento local de portugues.' -ForegroundColor Green
    exit 0
} catch {
    Write-Host ('Nao foi possivel preparar: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'A janela ficara aberta para voce copiar o erro.'
    exit 1
} finally {if($installLock){$installLock.Dispose()}}
