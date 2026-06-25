param([switch]$Online)

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Path -Parent }

if ($Online) {
    $remoto = git -C $here remote get-url origin 2>$null
    if (-not $remoto) { throw "No hay remoto git configurado. Usa Crear-KMZ.ps1 sin -Online primero." }
    $rawBase        = $remoto -replace 'https://github.com/', 'https://raw.githubusercontent.com/'
    $rawBase        = $rawBase -replace '\.git$', ''
    $kmlUrl         = "$rawBase/live/red_alertas.kml"
    $pronosticoUrl  = "$rawBase/live/red_pronostico.kml"
    $sismosUrl      = "$rawBase/live/red_sismos.kml"
    $kmzPath        = "$here\alertas-redes-online.kmz"
} else {
    $base           = $here -replace '\\', '/'
    $kmlUrl         = "file:///$base/red_alertas.kml"
    $pronosticoUrl  = "file:///$base/red_pronostico.kml"
    $sismosUrl      = "file:///$base/red_sismos.kml"
    $kmzPath        = "$here\alertas-redes.kmz"
}

$kmlContenido = @"
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document>
  <name>Alertas Redes Chile</name>
  <NetworkLink>
    <name>Alertas actuales</name>
    <open>0</open>
    <Link>
      <href>$kmlUrl</href>
      <refreshMode>onInterval</refreshMode>
      <refreshInterval>900</refreshInterval>
    </Link>
  </NetworkLink>
  <NetworkLink>
    <name>Pronostico 48h</name>
    <open>0</open>
    <Link>
      <href>$pronosticoUrl</href>
      <refreshMode>onInterval</refreshMode>
      <refreshInterval>900</refreshInterval>
    </Link>
  </NetworkLink>
  <NetworkLink>
    <name>Sismos Chile (CSN + USGS)</name>
    <open>0</open>
    <Link>
      <href>$sismosUrl</href>
      <refreshMode>onInterval</refreshMode>
      <refreshInterval>3600</refreshInterval>
    </Link>
  </NetworkLink>
</Document>
</kml>
"@

$tmpKml = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.kml'
[System.IO.File]::WriteAllText($tmpKml, $kmlContenido, [System.Text.Encoding]::UTF8)

if (Test-Path $kmzPath) { Remove-Item $kmzPath -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($kmzPath, 'Create')
[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $tmpKml, 'doc.kml') | Out-Null
$zip.Dispose()
Remove-Item $tmpKml

Write-Host "KMZ generado: $kmzPath" -ForegroundColor Green
Write-Host "  Alertas:    $kmlUrl"        -ForegroundColor Gray
Write-Host "  Pronostico: $pronosticoUrl" -ForegroundColor Gray
Write-Host "  Sismos:     $sismosUrl"    -ForegroundColor Gray
