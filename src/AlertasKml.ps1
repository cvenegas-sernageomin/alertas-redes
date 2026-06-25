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
            borderColor='rgba(162,45,45,0.4)'; borderWidth=1; borderDash=@(6,4); pointRadius=0; yAxisID='yR'; order=0
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
        options = @{ plugins=@{ legend=@{ display=$false } }; scales=$escalas }
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
    $desc = "<![CDATA[<b>$($e.Nombre)</b><br/>Red: $($e.Red)<br/>Precip: $($e.TasaMmH) mm/h<br/>Dato: $hora$chartImg]]>"
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
    $desc = "<![CDATA[<b>$($e.Nombre)</b><br/>Precip: $($e.TasaMmH) mm/h<br/>Temp: $tempStr<br/>Isoterma 0C: $isoStr<br/>Altitud: $($e.Altitud) m<br/>Dato: $hora$chartImg]]>"
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
    <open>1</open>
$subfolders
  </Folder>
  <Folder>
    <name>EMAs DMC - Alerta completa ($($emas.Count) est.)</name>
    <open>1</open>
$pmEmas
  </Folder>
</Document>
</kml>
"@
}
