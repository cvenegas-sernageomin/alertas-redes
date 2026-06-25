function Get-EstiloSismo([double]$mag) {
    if ($mag -ge 7) { return @{ Color='ff0000cc'; Scale=1.8 } }
    if ($mag -ge 6) { return @{ Color='ff0033ff'; Scale=1.3 } }
    if ($mag -ge 5) { return @{ Color='ff0080ff'; Scale=1.0 } }
    if ($mag -ge 4) { return @{ Color='ff00d7ff'; Scale=0.7 } }
    return @{ Color='ff00ffbf'; Scale=0.5 }
}

function Get-SismosCSN {
    $ua = @{'User-Agent'='Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
    try {
        $htmlCSN = (Invoke-WebRequest -Uri 'https://www.sismologia.cl/' `
                    -UseBasicParsing -TimeoutSec 40 -Headers $ua).Content
    } catch {
        Write-Warning "CSN: no se pudo obtener pagina principal: $_"
        return @()
    }

    $hrefs = [regex]::Matches($htmlCSN, 'href="(/sismicidad/sismos/[^"]+\.html)"') |
             ForEach-Object { $_.Groups[1].Value } |
             Select-Object -Unique |
             Select-Object -First 15

    $sismos = @()
    foreach ($href in $hrefs) {
        $url = "https://www.sismologia.cl$href"
        try {
            $ficha = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30 -Headers $ua).Content
            $txt   = ($ficha -replace '<[^>]+>', ' ') -replace '\s+', ' '

            $lat   = if ($txt -match 'Latitud[^\d-]*(-?\d+\.\d+)')   { [double]$Matches[1] } else { $null }
            $lon   = if ($txt -match 'Longitud[^\d-]*(-?\d+\.\d+)')  { [double]$Matches[1] } else { $null }
            $prof  = if ($txt -match 'Profundidad[^\d]*(\d+)\s*km')  { [int]$Matches[1] }    else { $null }
            $mag   = if ($txt -match 'Magnitud[^\d]*([\d.]+)')        { [double]$Matches[1] } else { $null }
            $fecha = if ($txt -match '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') { $Matches[1] } else { '' }

            if ($null -ne $lat -and $null -ne $lon -and $null -ne $mag) {
                $sismos += [PSCustomObject]@{
                    Lat    = $lat; Lon    = $lon
                    Prof   = $prof; Mag   = $mag
                    Fecha  = $fecha; Lugar = ''
                    Url    = $url; Fuente = 'CSN'
                }
            }
            Start-Sleep -Milliseconds 300
        } catch { continue }
    }
    return $sismos
}

function Get-SismosUSGS {
    $url = "https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson" +
           "&minlatitude=-56&maxlatitude=-17&minlongitude=-76&maxlongitude=-66" +
           "&minmagnitude=3.0&orderby=time&limit=200"
    try {
        $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 60
        [array]$feats = ($resp.Content | ConvertFrom-Json).features
        return $feats | ForEach-Object {
            $p = $_.properties; $c = $_.geometry.coordinates
            [PSCustomObject]@{
                Lat    = [double]$c[1]; Lon  = [double]$c[0]
                Prof   = if ($null -ne $c[2]) { [int]$c[2] } else { $null }
                Mag    = [double]$p.mag
                Fecha  = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$p.time).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
                Lugar  = $p.place; Url = $p.url; Fuente = 'USGS'
            }
        }
    } catch {
        Write-Warning "USGS: error al obtener sismos: $_"
        return @()
    }
}

function Build-PlacemarkSismo($s) {
    $est   = Get-EstiloSismo $s.Mag
    $prof  = if ($null -ne $s.Prof) { "$($s.Prof) km" } else { 'sin dato' }
    $lugar = if ($s.Lugar) { "<tr><td><b>Lugar</b></td><td>$($s.Lugar)</td></tr>" } else { '' }
    $desc  = "<![CDATA[<b>M $($s.Mag) &mdash; $($s.Fuente)</b><br/>" +
             "<table cellpadding='2'>" +
             "<tr><td><b>Fecha</b></td><td>$($s.Fecha)</td></tr>" +
             "<tr><td><b>Magnitud</b></td><td>$($s.Mag)</td></tr>" +
             "<tr><td><b>Profundidad</b></td><td>$prof</td></tr>" +
             $lugar +
             "<tr><td><b>Lat, Lon</b></td><td>$($s.Lat), $($s.Lon)</td></tr>" +
             "<tr><td><b>Fuente</b></td><td><a href='$($s.Url)'>$($s.Fuente)</a></td></tr>" +
             "</table>" +
             "<hr/><b>Leyenda por magnitud:</b>" +
             "<table cellspacing='2' cellpadding='2'>" +
             "<tr><td bgcolor='#cc0000' width='14'>&nbsp;&nbsp;</td><td>&nbsp;M &ge; 7</td></tr>" +
             "<tr><td bgcolor='#ff3300' width='14'>&nbsp;&nbsp;</td><td>&nbsp;M 6.0 &ndash; 6.9</td></tr>" +
             "<tr><td bgcolor='#ff8000' width='14'>&nbsp;&nbsp;</td><td>&nbsp;M 5.0 &ndash; 5.9</td></tr>" +
             "<tr><td bgcolor='#ffd700' width='14'>&nbsp;&nbsp;</td><td>&nbsp;M 4.0 &ndash; 4.9</td></tr>" +
             "<tr><td bgcolor='#80ff40' width='14'>&nbsp;&nbsp;</td><td>&nbsp;M 3.0 &ndash; 3.9</td></tr>" +
             "</table>]]>"
    return @"
    <Placemark>
      <name>M $($s.Mag) $($s.Fuente)</name>
      <Style>
        <IconStyle>
          <color>$($est.Color)</color><scale>$($est.Scale)</scale>
          <Icon><href>http://maps.google.com/mapfiles/kml/shapes/shaded_dot.png</href></Icon>
        </IconStyle>
        <LabelStyle><scale>0</scale></LabelStyle>
      </Style>
      <description>$desc</description>
      <Point><coordinates>$($s.Lon),$($s.Lat),0</coordinates></Point>
    </Placemark>
"@
}

function Build-SismosKml([array]$csn, [array]$usgs) {
    $umbral = 30

    $csnSup  = @($csn  | Where-Object { $null -ne $_.Prof -and $_.Prof -lt $umbral })
    $csnSub  = @($csn  | Where-Object { $null -eq $_.Prof -or  $_.Prof -ge $umbral })
    $usgsSup = @($usgs | Where-Object { $null -ne $_.Prof -and $_.Prof -lt $umbral })
    $usgsSub = @($usgs | Where-Object { $null -eq $_.Prof -or  $_.Prof -ge $umbral })

    $pmCsnSup  = ($csnSup  | ForEach-Object { Build-PlacemarkSismo $_ }) -join "`n"
    $pmCsnSub  = ($csnSub  | ForEach-Object { Build-PlacemarkSismo $_ }) -join "`n"
    $pmUsgsSup = ($usgsSup | ForEach-Object { Build-PlacemarkSismo $_ }) -join "`n"
    $pmUsgsSub = ($usgsSub | ForEach-Object { Build-PlacemarkSismo $_ }) -join "`n"

    $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    return @"
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document>
  <name>Sismos Chile - $ts</name>
  <Folder>
    <name>CSN - Superficiales (&lt;30 km) ($($csnSup.Count) ev.)</name>
    <open>1</open>
$pmCsnSup
  </Folder>
  <Folder>
    <name>CSN - Subduccion (&gt;=30 km) ($($csnSub.Count) ev.)</name>
    <open>0</open>
$pmCsnSub
  </Folder>
  <Folder>
    <name>USGS - Superficiales (&lt;30 km) ($($usgsSup.Count) ev.)</name>
    <open>0</open>
$pmUsgsSup
  </Folder>
  <Folder>
    <name>USGS - Subduccion (&gt;=30 km) ($($usgsSub.Count) ev.)</name>
    <open>0</open>
$pmUsgsSub
  </Folder>
</Document>
</kml>
"@
}
