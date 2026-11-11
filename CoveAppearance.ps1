function Get-CoveAccent([string]$File){
 if(Test-Path -LiteralPath $File){try{$data=Get-Content -LiteralPath $File -Raw|ConvertFrom-Json;if([string]$data.Accent -match '^#[0-9a-fA-F]{6}$'){return ([string]$data.Accent).ToUpperInvariant()}}catch{}}
 return '#67D9BE'
}
function Set-CoveAccent($Window,[string]$Hex){
 if($Hex -notmatch '^#[0-9a-fA-F]{6}$'){throw 'Escolha uma cor ou use o formato #RRGGBB.'}
 $base=[Windows.Media.ColorConverter]::ConvertFromString($Hex)
 $secondary=[Windows.Media.Color]::FromRgb([byte]($base.R*.55+$base.B*.45),[byte]($base.G*.55+$base.R*.45),[byte]($base.B*.55+$base.G*.45))
 $light=[Windows.Media.Color]::FromRgb([byte]($base.R*.55+255*.45),[byte]($base.G*.55+255*.45),[byte]($base.B*.55+255*.45))
 $dark=[Windows.Media.Color]::FromRgb([byte]($base.R*.33),[byte]($base.G*.33),[byte]($base.B*.33))
 $colors=@{
  CovePrimary=$base;CoveSecondary=$secondary;CoveLight=$light
  CovePrimaryCloud=[Windows.Media.Color]::FromArgb(215,$base.R,$base.G,$base.B)
  CovePrimaryMist=[Windows.Media.Color]::FromArgb(102,$base.R,$base.G,$base.B)
  CovePrimaryClear=[Windows.Media.Color]::FromArgb(0,$base.R,$base.G,$base.B)
  CoveSecondaryCloud=[Windows.Media.Color]::FromArgb(201,$secondary.R,$secondary.G,$secondary.B)
  CoveSecondaryMist=[Windows.Media.Color]::FromArgb(98,$secondary.R,$secondary.G,$secondary.B)
  CoveSecondaryClear=[Windows.Media.Color]::FromArgb(0,$secondary.R,$secondary.G,$secondary.B)
  CoveLightCloud=[Windows.Media.Color]::FromArgb(183,$light.R,$light.G,$light.B)
  CoveRim=[Windows.Media.Color]::FromArgb(159,$light.R,$light.G,$light.B)
 }
 foreach($key in $colors.Keys){$Window.Resources[$key]=$colors[$key]}
 return [pscustomobject]@{Idle=$dark.ToString();Listening=$base.ToString();Thinking=$secondary.ToString();Speaking=$secondary.ToString();Light=$light;Hex=$Hex.ToUpperInvariant()}
}
