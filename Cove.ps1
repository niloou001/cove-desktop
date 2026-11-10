param([switch]$SmokeTest)
$ErrorActionPreference = 'Stop'
if (-not $SmokeTest) {
    $native = Join-Path $PSScriptRoot 'assets\native\libvosk.dll'
    $model = Join-Path $PSScriptRoot 'assets\vosk-model-small-pt-0.3\am\final.mdl'
    $legacyModel = Join-Path $PSScriptRoot 'assets\vosk-model-small-pt-0.3\final.mdl'
    if (-not (Test-Path -LiteralPath $native) -or (-not (Test-Path -LiteralPath $model) -and -not (Test-Path -LiteralPath $legacyModel))) {
        & "$PSHOME\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Preparar-Cove.ps1')
        if ($LASTEXITCODE -ne 0) { Write-Warning 'Escuta indisponivel. Abrindo conversa por texto.' }
    }
}
& (Join-Path $PSScriptRoot 'Cove-Voice.ps1') -SmokeTest:$SmokeTest
