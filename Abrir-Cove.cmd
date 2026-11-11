@echo off
if not exist "%~dp0assets\native\libvosk.dll" goto prepare
if exist "%~dp0assets\vosk-model-small-pt-0.3\final.mdl" goto launch
if not exist "%~dp0assets\vosk-model-small-pt-0.3\am\final.mdl" goto prepare
goto launch
:prepare
echo Preparando o reconhecimento de voz na primeira abertura...
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Preparar-Cove.ps1"
if errorlevel 1 (
  echo A preparacao falhou. O Cove abrira com conversa por texto.
  pause
)
:launch
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0CoveLauncher.ps1"
if errorlevel 1 pause
