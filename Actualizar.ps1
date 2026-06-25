$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Path -Parent }
. "$here\src\RedesApi.ps1"
. "$here\src\AlertasKml.ps1"
. "$here\src\PronosticoApi.ps1"

$kmlPath         = "$here\red_alertas.kml"
$kmlPronostico   = "$here\red_pronostico.kml"

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Consultando DMC/DGA/Agromet (todas las redes)..." -ForegroundColor Cyan
try {
    $redes = Get-AllRedes
    Write-Host "  -> $($redes.Count) estaciones" -ForegroundColor Gray
} catch {
    Write-Warning "Error en DMC/DGA/Agromet: $_"
    $redes = @()
}

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Consultando EMAs DMC..." -ForegroundColor Cyan
try {
    $emas = Get-EmasDmc $redes
    Write-Host "  -> $($emas.Count) estaciones" -ForegroundColor Gray
} catch {
    Write-Warning "Error en EMAs DMC: $_"
    $emas = @()
}

if ($redes.Count -eq 0 -and $emas.Count -eq 0) {
    Write-Warning "Sin datos de ninguna fuente. Se mantiene el KML anterior."
    exit 1
}

$kml = Build-Kml $redes $emas
[System.IO.File]::WriteAllText($kmlPath, $kml, [System.Text.Encoding]::UTF8)

$alertasRedes = ($redes | Where-Object { $_.TasaMmH -ge 5 }).Count
$alertasEmas  = ($emas  | Where-Object { (Get-ColorEmas $_.TasaMmH $_.Isoterma) -ne 'verde' }).Count

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] KML escrito: $kmlPath" -ForegroundColor Green
$redes | Group-Object Red | Sort-Object Count -Desc | ForEach-Object {
    Write-Host "    $($_.Name): $($_.Count) est." -ForegroundColor Gray
}
Write-Host "  Total: $($redes.Count) est. | $alertasRedes con precip>=5 mm/h" -ForegroundColor Yellow
Write-Host "  EMAs DMC:  $($emas.Count) est.  | $alertasEmas con alerta activa" -ForegroundColor Yellow

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Consultando pronostico (Open-Meteo grilla Chile)..." -ForegroundColor Cyan
try {
    $grilla       = Get-GrillaChile
    $allVentanas  = Get-PronosticoGrilla $grilla
    $kmlPron      = Build-PronosticoKml $allVentanas
    [System.IO.File]::WriteAllText($kmlPronostico, $kmlPron, [System.Text.Encoding]::UTF8)

    $alertasPron = ($allVentanas | Where-Object { $_.EstiloKml -ne 'verde' }).Count
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] KML pronostico escrito: $kmlPronostico" -ForegroundColor Green
    Write-Host "  Grilla: $($grilla.Count) pts | $alertasPron ventanas con alerta" -ForegroundColor Yellow
} catch {
    Write-Warning "Error en pronostico Open-Meteo: $_. Se mantiene el KML anterior."
}
