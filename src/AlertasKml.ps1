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
    $desc  = "<![CDATA[<b>$($e.Nombre)</b><br/>Red: $($e.Red)<br/>Precip: $($e.TasaMmH) mm/h<br/>Dato: $hora]]>"
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
    $color = Get-ColorEmas $e.TasaMmH $e.Isoterma
    $hora  = Format-Epoch $e.Epoch
    $isoStr  = if ($null -ne $e.Isoterma) { "$($e.Isoterma) m" } else { 'sin dato' }
    $tempStr = if ($null -ne $e.TempC)    { "$($e.TempC) grados C"   } else { 'sin dato' }
    $desc = "<![CDATA[<b>$($e.Nombre)</b><br/>Precip: $($e.TasaMmH) mm/h<br/>Temp: $tempStr<br/>Isoterma 0C: $isoStr<br/>Altitud: $($e.Altitud) m<br/>Dato: $hora]]>"
    return @"
    <Placemark>
      <name>$($e.Nombre) - $($e.TasaMmH) mm/h</name>
      <styleUrl>#$color</styleUrl>
      <description>$desc</description>
      <Point><coordinates>$($e.Lon),$($e.Lat),0</coordinates></Point>
    </Placemark>
"@
}

function Build-Kml([array]$redes, [array]$emas) {
    $estilos = Build-Styles
    $pmRedes = ($redes | ForEach-Object { Build-PlacemarkRedes $_ }) -join "`n"
    $pmEmas  = ($emas  | ForEach-Object { Build-PlacemarkEmas $_ })  -join "`n"
    $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    return @"
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document>
  <name>Alertas Redes Chile - $ts</name>
$estilos
  <Folder>
    <name>DMC/DGA/Agromet - Precipitacion ($($redes.Count) est.)</name>
    <open>1</open>
$pmRedes
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
