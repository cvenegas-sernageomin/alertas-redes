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

function Build-AcumuladoSerie([array]$precip) {
    $acc = 0.0
    $out = [System.Collections.Generic.List[double]]::new()
    foreach ($v in $precip) {
        if ($null -ne $v) { $acc += [double]$v }
        $out.Add([math]::Round($acc, 1))
    }
    return $out.ToArray()
}

function Build-ChartAcumulado([array]$tiempos, [array]$precip, [int]$horas) {
    if ($tiempos.Count -lt 2) { return '' }
    # Tomar las ultimas $horas muestras (paso horario)
    $n     = $tiempos.Count
    $desde = [math]::Max(0, $n - $horas)
    $t = @($tiempos[$desde..($n - 1)])
    $p = @($precip[$desde..($n - 1)])
    if ($t.Count -lt 2) { return '' }

    $labels = @($t | ForEach-Object {
        [DateTimeOffset]::FromUnixTimeSeconds([long]$_).ToLocalTime().ToString('dd HH:mm')
    })
    $acum    = Build-AcumuladoSerie $p
    $totalMm = if ($acum.Count -gt 0) { $acum[-1] } else { 0 }

    $ds = [System.Collections.Generic.List[hashtable]]::new()
    $ds.Add(@{
        type='bar'; label='Precip mm/h'; data=$p
        backgroundColor='rgba(55,138,221,0.7)'; yAxisID='yP'; order=2
    })
    $ds.Add(@{
        type='line'; label='Acumulado mm'; data=$acum
        borderColor='#1f7a1f'; backgroundColor='rgba(31,122,31,0.15)'; fill=$true
        borderWidth=2; pointRadius=0; tension=0.2; yAxisID='yA'; order=1
    })

    $escalas = @{
        x  = @{ ticks=@{ font=@{ size=9 }; maxTicksLimit=8 } }
        yP = @{ position='left';  title=@{ display=$true; text='mm/h' };    ticks=@{ font=@{ size=9 } } }
        yA = @{ position='right'; grid=@{ drawOnChartArea=$false }
               title=@{ display=$true; text='Acum mm' }; ticks=@{ font=@{ size=9 } }; beginAtZero=$true }
    }
    $cfg = @{
        type = 'bar'
        data = @{ labels=$labels; datasets=$ds.ToArray() }
        options = @{
            plugins = @{
                legend = @{ display=$true; position='bottom'; labels=@{ boxWidth=10; font=@{ size=9 } } }
                title  = @{ display=$true; text="Acumulado ${horas}h: $totalMm mm"; font=@{ size=11 } }
            }
            scales = $escalas
        }
    }
    $json    = $cfg | ConvertTo-Json -Depth 15 -Compress
    $encoded = [Uri]::EscapeDataString($json)
    return "https://quickchart.io/chart?v=4&w=330&h=180&c=$encoded"
}

function Build-GraficosAcumulado([array]$tiempos, [array]$precip) {
    if (-not $tiempos -or $tiempos.Count -lt 2) { return '' }
    # Sin lluvia en la ventana -> sin graficos (estacion seca = linea plana en 0, no aporta y abulta el KML)
    $total = 0.0
    foreach ($v in $precip) { if ($null -ne $v) { $total += [double]$v } }
    if ($total -lt 0.1) { return '' }
    $img = ''
    $c24 = Build-ChartAcumulado $tiempos $precip 24
    $c48 = Build-ChartAcumulado $tiempos $precip 48
    if ($c24) { $img += "<br/><b>Ultimas 24 h</b><br/><img src='$c24' width='330'/>" }
    if ($c48) { $img += "<br/><b>Ultimas 48 h</b><br/><img src='$c48' width='330'/>" }
    return $img
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
    $chartImg = Build-GraficosAcumulado $e.TiemposSerie $e.ValoresSerie
    $leyenda = "<hr/><small><b>Umbrales:</b> Verde &lt;5 mm/h &middot; Amarillo &ge;5 &middot; Rojo &ge;10</small>"
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
    $chartImg = Build-GraficosAcumulado $e.TiemposSerie $e.ValoresPrecip
    $leyenda = "<hr/><small><b>Umbrales EMA:</b> Amarillo precip &ge;5 mm/h + isoterma &ge;3000 m &middot; Rojo &ge;10 + iso &ge;3000</small>"
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
            "<hr/><small><b>Umbrales (acumulado ventana):</b> Verde &lt;5 mm o iso &lt;2500 m &middot; Amarillo &ge;5 + iso &ge;2500 &middot; Rojo &ge;20 + iso &ge;3000</small>]]>"
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
