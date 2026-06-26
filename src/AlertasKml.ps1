function Build-ChartUrl([array]$tiempos, [array]$precip, [array]$temp = @(), [array]$iso = @()) {
    if ($tiempos.Count -lt 2) { return '' }

    $labels = @($tiempos | ForEach-Object {
        [DateTimeOffset]::FromUnixTimeSeconds([long]$_).ToLocalTime().ToString('HH:mm')
    })

    $ds = [System.Collections.Generic.List[hashtable]]::new()
    $ds.Add(@{
        type='bar'; label='Precip mm/h'; data=$precip
        backgroundColor='rgba(55,138,221,0.7)'; yAxisID='yP'; order=2
    })

    if ($temp.Count -gt 0) {
        $ds.Add(@{
            type='line'; label='Temp C'; data=$temp
            borderColor='#E24B4A'; borderWidth=2; pointRadius=2; tension=0.3; yAxisID='yR'; order=1
        })
    }

    if ($iso.Count -gt 0) {
        $isoKm = @($iso | ForEach-Object {
            if ($null -ne $_) { [math]::Round([double]$_ / 1000.0, 2) } else { $null }
        })
        $ds.Add(@{
            type='line'; label='Isoterma km'; data=$isoKm
            borderColor='#EF9F27'; borderWidth=2; borderDash=@(4,3); pointRadius=2; tension=0.3; yAxisID='yR'; order=1
        })
        $ds.Add(@{
            type='line'; label='Umbral 3km'; data=@($tiempos | ForEach-Object { 3.0 })
            borderColor='rgba(162,45,45,0.4)'; borderWidth=1; borderDash=@(6,4); pointRadius=0; yAxisID='yR'; order=0; hidden=$true
        })
    }

    $escalas = @{
        x  = @{ ticks = @{ font = @{ size = 10 } } }
        yP = @{ position='left';  title=@{ display=$true; text='mm/h' }; ticks=@{ font=@{ size=10 } } }
    }
    if ($temp.Count -gt 0 -or $iso.Count -gt 0) {
        $escalas['yR'] = @{
            position='right'; grid=@{ drawOnChartArea=$false }
            title=@{ display=$true; text='C/km' }; ticks=@{ font=@{ size=10 } }
        }
    }

    $cfg = @{
        type = 'bar'
        data = @{ labels=$labels; datasets=$ds.ToArray() }
        options = @{ plugins=@{ legend=@{ display=$true; position='bottom'; labels=@{ boxWidth=10; font=@{ size=10 } } } }; scales=$escalas }
    }
    $json    = $cfg | ConvertTo-Json -Depth 15 -Compress
    $encoded = [Uri]::EscapeDataString($json)
    return "https://quickchart.io/chart?v=4&w=300&h=160&c=$encoded"
}

function Get-ColorRedes([double]$mmH) {
    if ($mmH -ge 10) { return 'rojo' }
    if ($mmH -ge 5)  { return 'amarillo' }
    return 'verde'
}

function Get-ColorEmas([double]$mmH, $iso) {
    if ($null -eq $iso) { return 'verde' }
    if ($mmH -ge 10 -and $iso -ge 3000) { return 'rojo' }
    if ($mmH -ge 5  -and $iso -ge 3000) { return 'amarillo' }
    return 'verde'
}

function Format-Epoch([long]$epoch) {
    [DateTimeOffset]::FromUnixTimeSeconds($epoch).ToLocalTime().ToString('HH:mm dd-MMM-yyyy')
}

function Build-Styles {
    return @"
  <Style id="verde">
    <IconStyle>
      <color>ff00cc00</color><scale>0.6</scale>
      <Icon><href>http://maps.google.com/mapfiles/kml/shapes/placemark_circle.png</href></Icon>
    </IconStyle>
    <LabelStyle><scale>0</scale></LabelStyle>
  </Style>
  <Style id="amarillo">
    <IconStyle>
      <color>ff00ffff</color><scale>0.8</scale>
      <Icon><href>http://maps.google.com/mapfiles/kml/shapes/placemark_circle.png</href></Icon>
    </IconStyle>
    <LabelStyle><scale>0</scale></LabelStyle>
  </Style>
  <Style id="rojo">
    <IconStyle>
      <color>ff0000ff</color><scale>1.0</scale>
      <Icon><href>http://maps.google.com/mapfiles/kml/shapes/placemark_circle.png</href></Icon>
    </IconStyle>
    <LabelStyle><scale>0.7</scale></LabelStyle>
  </Style>
"@
}

function Build-PlacemarkRedes($e) {
    $color = Get-ColorRedes $e.TasaMmH
    $hora  = Format-Epoch $e.Epoch
    $chartImg = ''
    if ($e.ValoresSerie -and $e.ValoresSerie.Count -ge 2) {
        $url = Build-ChartUrl $e.TiemposSerie $e.ValoresSerie
        if ($url) { $chartImg = "<br/><small>Precip (mm/h)</small><br/><img src='$url' width='300'/>" }
    }
    $leyenda = "<hr/><b>Leyenda:</b><table cellspacing='2' cellpadding='2'>" +
               "<tr><td bgcolor='#00cc00' width='14'>&nbsp;&nbsp;</td><td>&nbsp;Verde: precip &lt; 5 mm/h</td></tr>" +
               "<tr><td bgcolor='#cc9900' width='14'>&nbsp;&nbsp;</td><td>&nbsp;Amarillo: precip &ge; 5 mm/h</td></tr>" +
               "<tr><td bgcolor='#ff0000' width='14'>&nbsp;&nbsp;</td><td>&nbsp;Rojo: precip &ge; 10 mm/h</td></tr>" +
               "</table>"
    $desc = "<![CDATA[<b>$($e.Nombre)</b><br/>Red: $($e.Red)<br/>Precip: $($e.TasaMmH) mm/h<br/>Dato: $hora$chartImg<br/><br/>$leyenda]]>"
    return @"
    <Placemark>
      <name>$($e.Nombre) - $($e.TasaMmH) mm/h</name>
      <styleUrl>#$color</styleUrl>
      <description>$desc</description>
      <Point><coordinates>$($e.Lon),$($e.Lat),0</coordinates></Point>
    </Placemark>
"@
}

function Build-PlacemarkEmas($e) {
    $color   = Get-ColorEmas $e.TasaMmH $e.Isoterma
    $hora    = Format-Epoch $e.Epoch
    $isoStr  = if ($null -ne $e.Isoterma) { "$($e.Isoterma) m" } else { 'sin dato' }
    $tempStr = if ($null -ne $e.TempC)    { "$($e.TempC) grados C" } else { 'sin dato' }
    $chartImg = ''
    if ($e.TiemposSerie -and $e.TiemposSerie.Count -ge 2) {
        $url = Build-ChartUrl $e.TiemposSerie $e.ValoresPrecip $e.ValoresTemp $e.ValoresIso
        if ($url) { $chartImg = "<br/><small>Precip mm/h | Temp C | Isoterma km</small><br/><img src='$url' width='300'/>" }
    }
    $leyenda = "<hr/><b>Leyenda:</b><table cellspacing='2' cellpadding='2'>" +
               "<tr><td bgcolor='#00cc00' width='14'>&nbsp;&nbsp;</td><td>&nbsp;Verde: condicion sin alerta</td></tr>" +
               "<tr><td bgcolor='#cc9900' width='14'>&nbsp;&nbsp;</td><td>&nbsp;Amarillo: precip &ge; 5 mm/h Y isoterma &ge; 3000 m</td></tr>" +
               "<tr><td bgcolor='#ff0000' width='14'>&nbsp;&nbsp;</td><td>&nbsp;Rojo: precip &ge; 10 mm/h Y isoterma &ge; 3000 m</td></tr>" +
               "</table>"
    $desc = "<![CDATA[<b>$($e.Nombre)</b><br/>Precip: $($e.TasaMmH) mm/h<br/>Temp: $tempStr<br/>Isoterma 0C: $isoStr<br/>Altitud: $($e.Altitud) m<br/>Dato: $hora$chartImg<br/><br/>$leyenda]]>"
    return @"
    <Placemark>
      <name>$($e.Nombre) - $($e.TasaMmH) mm/h</name>
      <styleUrl>#$color</styleUrl>
      <description>$desc</description>
      <Point><coordinates>$($e.Lon),$($e.Lat),0</coordinates></Point>
    </Placemark>
"@
}

function Build-SubfoldersRedes([array]$redes) {
    $grupos = $redes | Group-Object Red | Sort-Object Count -Descending
    $xml = ''
    foreach ($g in $grupos) {
        $pm = ($g.Group | ForEach-Object { Build-PlacemarkRedes $_ }) -join "`n"
        $xml += @"
    <Folder>
      <name>$($g.Name) ($($g.Count) est.)</name>
      <open>0</open>
$pm
    </Folder>

"@
    }
    return $xml
}

function Build-Kml([array]$redes, [array]$emas) {
    $estilos = Build-Styles
    $subfolders = Build-SubfoldersRedes $redes
    $pmEmas  = ($emas  | ForEach-Object { Build-PlacemarkEmas $_ })  -join "`n"
    $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    return @"
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document>
  <name>Alertas Redes Chile - $ts</name>
$estilos
  <Folder>
    <name>Precipitacion ($($redes.Count) est.)</name>
    <open>0</open>
$subfolders
  </Folder>
  <Folder>
    <name>EMAs DMC - Alerta completa ($($emas.Count) est.)</name>
    <open>0</open>
$pmEmas
  </Folder>
</Document>
</kml>
"@
}

function Build-StylesPronostico {
    $xml = @"
  <Style id="verde_p">
    <IconStyle>
      <color>ff00cc00</color><scale>0.6</scale>
      <Icon><href>http://maps.google.com/mapfiles/kml/shapes/placemark_square.png</href></Icon>
    </IconStyle>
    <LabelStyle><scale>0</scale></LabelStyle>
  </Style>
"@
    foreach ($color in @('amarillo', 'rojo')) {
        $kmlColor = if ($color -eq 'rojo') { 'ff0000ff' } else { 'ff00ffff' }
        foreach ($n in @(1, 2, 3)) {
            $scale = if ($n -eq 3) { 1.0 } elseif ($n -eq 2) { 0.8 } else { 0.6 }
            $opac  = if ($n -eq 1) { 'bb' } else { 'ff' }
            $kmlC  = "$opac$($kmlColor.Substring(2))"
            $xml  += @"
  <Style id="${color}_${n}">
    <IconStyle>
      <color>$kmlC</color><scale>$scale</scale>
      <Icon><href>http://maps.google.com/mapfiles/kml/shapes/placemark_square.png</href></Icon>
    </IconStyle>
    <LabelStyle><scale>0</scale></LabelStyle>
  </Style>
"@
        }
    }
    return $xml
}

function Build-PlacemarkPronostico($v) {
    $isoE = if ($null -ne $v.IsoEcmwf) { "$($v.IsoEcmwf) m" } else { 'sin dato' }
    $isoG = if ($null -ne $v.IsoGfs)   { "$($v.IsoGfs) m"   } else { 'sin dato' }
    $isoI = if ($null -ne $v.IsoIcon)  { "$($v.IsoIcon) m"  } else { 'sin dato' }
    $desc = "<![CDATA[<b>$($v.Lat) / $($v.Lon)</b><br/>Ventana: $($v.Nombre)<br/><br/>" +
            "<table><tr><th></th><th>Precip (mm)</th><th>Isoterma (m)</th><th>Alerta</th></tr>" +
            "<tr><td>ECMWF</td><td>$($v.PrecipEcmwf)</td><td>$isoE</td><td>$($v.ColorEcmwf)</td></tr>" +
            "<tr><td>GFS</td><td>$($v.PrecipGfs)</td><td>$isoG</td><td>$($v.ColorGfs)</td></tr>" +
            "<tr><td>ICON</td><td>$($v.PrecipIcon)</td><td>$isoI</td><td>$($v.ColorIcon)</td></tr>" +
            "</table><br/>Acuerdo: $($v.NModelos)/3 modelos en $($v.ColorFinal)<br/><br/>" +
            "<hr/><b>Leyenda (acumulado en ventana):</b><table cellspacing='2' cellpadding='2'>" +
            "<tr><td bgcolor='#00cc00' width='14'>&nbsp;&nbsp;</td><td>&nbsp;Verde: precip &lt; 5 mm O isoterma &lt; 2500 m</td></tr>" +
            "<tr><td bgcolor='#cc9900' width='14'>&nbsp;&nbsp;</td><td>&nbsp;Amarillo: precip &ge; 5 mm Y isoterma &ge; 2500 m</td></tr>" +
            "<tr><td bgcolor='#ff0000' width='14'>&nbsp;&nbsp;</td><td>&nbsp;Rojo: precip &ge; 20 mm Y isoterma &ge; 3000 m</td></tr>" +
            "</table>]]>"
    return @"
    <Placemark>
      <name>$($v.Lat),$($v.Lon)</name>
      <styleUrl>#$($v.EstiloKml)</styleUrl>
      <description>$desc</description>
      <Point><coordinates>$($v.Lon),$($v.Lat),0</coordinates></Point>
    </Placemark>
"@
}

function Build-PronosticoFolders([array]$allVentanas) {
    $nombres = @('+0 a 6h', '+6 a 12h', '+12 a 24h', '+24 a 48h')
    $xml = ''
    foreach ($nombre in $nombres) {
        $grupo = $allVentanas | Where-Object { $_.Nombre -eq $nombre }
        $pm    = ($grupo | ForEach-Object { Build-PlacemarkPronostico $_ }) -join "`n"
        $xml  += @"
  <Folder>
    <name>$nombre ($($grupo.Count) pts)</name>
    <open>0</open>
$pm
  </Folder>

"@
    }
    return $xml
}

function Build-PronosticoKml([array]$allVentanas) {
    $estilosBase  = Build-Styles
    $estilosPron  = Build-StylesPronostico
    $folders      = Build-PronosticoFolders $allVentanas
    $ts           = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    return @"
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document>
  <name>Pronostico Chile - $ts</name>
$estilosBase
$estilosPron
$folders
</Document>
</kml>
"@
}
