param([switch]$Online)

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Path -Parent }

if ($Online) {
    # Lee URL del remoto git
    $remoto = git -C $here remote get-url origin 2>$null
    if (-not $remoto) { throw "No hay remoto git configurado. Usa Crear-KMZ.ps1 sin -Online primero." }
    # convierte https://github.com/USER/REPO a raw url de rama live
    $rawBase = $remoto -replace 'https://github.com/', 'https://raw.githubusercontent.com/'
    $rawBase = $rawBase -replace '\.git$', ''
    $kmlUrl = "$rawBase/live/red_alertas.kml"
    $kmzPath = "$here\alertas-redes-online.kmz"
} else {
    $kmlUrl  = "file:///$($here -replace '\\','/')/red_alertas.kml"
    $kmzPath = "$here\alertas-redes.kmz"
}

$kmlContenido = @"
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<NetworkLink>
  <name>Alertas Redes Chile</name>
  <open>1</open>
  <Link>
    <href>$kmlUrl</href>
    <refreshMode>onInterval</refreshMode>
    <refreshInterval>900</refreshInterval>
  </Link>
</NetworkLink>
</kml>
"@

# Empaqueta en ZIP con extensión .kmz
$tmpKml = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.kml'
[System.IO.File]::WriteAllText($tmpKml, $kmlContenido, [System.Text.Encoding]::UTF8)

if (Test-Path $kmzPath) { Remove-Item $kmzPath -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($kmzPath, 'Create')
[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $tmpKml, 'doc.kml') | Out-Null
$zip.Dispose()
Remove-Item $tmpKml

Write-Host "KMZ generado: $kmzPath" -ForegroundColor Green
if ($Online) { Write-Host "  NetworkLink apunta a: $kmlUrl" -ForegroundColor Gray }
