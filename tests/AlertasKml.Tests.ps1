$here = $PSScriptRoot
. "$here\..\src\UmbralesRegionales.ps1"
. "$here\..\src\AlertasKml.ps1"

Describe "Get-ColorRedes" {
    It "verde para 0 mm/h"  { Get-ColorRedes 0.0  | Should Be 'verde'    }
    It "verde para 4.9"     { Get-ColorRedes 4.9  | Should Be 'verde'    }
    It "amarillo para 5"    { Get-ColorRedes 5.0  | Should Be 'amarillo' }
    It "amarillo para 9.9"  { Get-ColorRedes 9.9  | Should Be 'amarillo' }
    It "rojo para 10"       { Get-ColorRedes 10.0 | Should Be 'rojo'     }
    It "rojo para 50"       { Get-ColorRedes 50.0 | Should Be 'rojo'     }
}

Describe "Get-ColorEmas" {
    # amarillo: precip>=5 Y iso>=3000
    # rojo:     precip>=10 Y iso>=3000
    It "verde cuando precip baja e iso baja" {
        Get-ColorEmas 0.0 1000 | Should Be 'verde'
    }
    It "verde cuando precip alta pero iso baja" {
        Get-ColorEmas 10.0 2999 | Should Be 'verde'
    }
    It "amarillo cuando precip>=5 Y iso>=3000" {
        Get-ColorEmas 5.0 3000 | Should Be 'amarillo'
    }
    It "rojo cuando precip>=10 Y iso>=3000" {
        Get-ColorEmas 10.0 3000 | Should Be 'rojo'
    }
    It "verde cuando iso es null" {
        Get-ColorEmas 15.0 $null | Should Be 'verde'
    }
}

Describe "Build-Kml" {
    $redes = @(
        [PSCustomObject]@{Nombre='Visviri'; Codigo='01K'; Lat=-17.5; Lon=-69.4; TasaMmH=0.0; Epoch=1781802000; Red='DGA/DMC'}
        [PSCustomObject]@{Nombre='Arica';   Codigo='02K'; Lat=-18.3; Lon=-70.3; TasaMmH=7.0; Epoch=1781802000; Red='Agromet'}
    )
    $emas = @(
        [PSCustomObject]@{Nombre='El Paico'; Codigo='330113'; Lat=-33.7; Lon=-71.0; Altitud=275.0; TasaMmH=6.5; TempC=8.0; Isoterma=1505; Epoch=1781807400}
    )
    $kml = Build-Kml $redes $emas

    It "contiene declaracion XML" {
        $kml | Should Match '<?xml'
    }
    It "contiene subcarpeta DGA/DMC" {
        $kml | Should Match 'DGA/DMC'
    }
    It "contiene subcarpeta Agromet" {
        $kml | Should Match 'Agromet'
    }
    It "contiene carpeta EMAs DMC" {
        $kml | Should Match 'EMAs DMC'
    }
    It "contiene 3 placemarks en total" {
        ($kml | Select-String '<Placemark>' -AllMatches).Matches.Count | Should Be 3
    }
    It "estacion redes con 7 mm/h aparece con styleUrl amarillo" {
        $kml | Should Match '#amarillo'
    }
}

Describe "Build-ChartUrl" {
    $tiempos = @(1781794800, 1781798400, 1781802000)
    $precip  = @(0.0, 3.2, 7.5)
    $temp    = @(12.0, 11.5, 10.8)
    $iso     = @(5646, 5569, 5461)

    It "retorna URL de quickchart.io" {
        Build-ChartUrl $tiempos $precip | Should Match 'quickchart\.io'
    }
    It "con solo precip no incluye Temp ni Isoterma" {
        $url = Build-ChartUrl $tiempos $precip
        $url | Should Not Match 'Temp'
        $url | Should Not Match 'Isoterma'
    }
    It "con temp incluye dataset Temp C" {
        Build-ChartUrl $tiempos $precip $temp | Should Match 'Temp'
    }
    It "con iso incluye dataset Isoterma km" {
        Build-ChartUrl $tiempos $precip $temp $iso | Should Match 'Isoterma'
    }
    It "retorna cadena vacia cuando hay menos de 2 puntos" {
        Build-ChartUrl @(1781794800) @(0.0) | Should Be ''
    }
}

Describe "Build-PlacemarkRedes con serie" {
    It "incluye img cuando ValoresSerie tiene 2+ puntos" {
        $e = [PSCustomObject]@{
            Nombre='Visviri'; Codigo='01K'; Lat=-17.5; Lon=-69.4
            TasaMmH=3.2; Epoch=1781802000; Red='DGA/DMC'
            ValoresSerie=@(0.0,1.5,3.2); TiemposSerie=@(1781794800,1781798400,1781802000)
        }
        Build-PlacemarkRedes $e | Should Match '<img'
    }
    It "no incluye img cuando ValoresSerie tiene 1 punto" {
        $e = [PSCustomObject]@{
            Nombre='Visviri'; Codigo='01K'; Lat=-17.5; Lon=-69.4
            TasaMmH=3.2; Epoch=1781802000; Red='DGA/DMC'
            ValoresSerie=@(3.2); TiemposSerie=@(1781802000)
        }
        Build-PlacemarkRedes $e | Should Not Match '<img'
    }
    It "no incluye img cuando la estacion esta seca (toda la serie en 0)" {
        $e = [PSCustomObject]@{
            Nombre='Visviri'; Codigo='01K'; Lat=-17.5; Lon=-69.4
            TasaMmH=0.0; Epoch=1781802000; Red='DGA/DMC'
            ValoresSerie=@(0.0,0.0,0.0,0.0); TiemposSerie=@(1781791200,1781794800,1781798400,1781802000)
        }
        Build-PlacemarkRedes $e | Should Not Match '<img'
    }
    It "incluye dos img cuando hubo lluvia (24h y 48h)" {
        $tiempos = @(0..47 | ForEach-Object { 1781600000 + ($_ * 3600) })
        $precip  = @(0..47 | ForEach-Object { if ($_ -ge 40) { 2.0 } else { 0.0 } })
        $e = [PSCustomObject]@{
            Nombre='Lluviosa'; Codigo='09K'; Lat=-38.0; Lon=-72.0
            TasaMmH=2.0; Epoch=1781600000; Red='DGA/DMC'
            ValoresSerie=$precip; TiemposSerie=$tiempos
        }
        ([regex]::Matches((Build-PlacemarkRedes $e), '<img')).Count | Should Be 2
    }
}

Describe "Get-ColorRedesFinal" {
    It "usa ColorPrecipRegional cuando existe" {
        $e = [PSCustomObject]@{ TasaMmH=2.0; ColorPrecipRegional='rojo' }
        Get-ColorRedesFinal $e | Should Be 'rojo'
    }
    It "cae al umbral simple si no hay region (fuera de tabla)" {
        $e = [PSCustomObject]@{ TasaMmH=7.0; ColorPrecipRegional=$null }
        Get-ColorRedesFinal $e | Should Be 'amarillo'
    }
    It "cae al umbral simple si el objeto no tiene la propiedad (compatibilidad hacia atras)" {
        $e = [PSCustomObject]@{ TasaMmH=12.0 }
        Get-ColorRedesFinal $e | Should Be 'rojo'
    }
}

Describe "Build-PlacemarkRedes con region" {
    $ahora = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $e = [PSCustomObject]@{
        Nombre='Estacion RM'; Codigo='X'; Lat=-33.45; Lon=-70.6
        TasaMmH=1.0; Epoch=$ahora; UltimoDatoEpoch=$ahora; Red='DMC'
        ValoresSerie=@(); TiemposSerie=@()
        Region='Metropolitana'; DiaRacha=2; AcumuladoHoy=45.0
        UmbralesRegion=@{ aviso=30; alerta=60; alarma=82 }
        ColorPrecipRegional='amarillo'
    }
    $pm = Build-PlacemarkRedes $e

    It "usa el color regional en el styleUrl (amarillo), no el flat de TasaMmH (que daria verde)" {
        $pm | Should Match '#amarillo'
    }
    It "muestra la region y el dia de racha en el popup" {
        $pm | Should Match 'Metropolitana'
        $pm | Should Match 'Dia de lluvia continua: 2'
    }
    It "muestra el acumulado del dia y los 3 umbrales" {
        $pm | Should Match 'Acumulado hoy: 45'
        $pm | Should Match 'aviso'
        $pm | Should Match 'alerta'
        $pm | Should Match 'alarma'
    }
}

Describe "Build-PlacemarkRedes sin region pero con AcumuladoHoy (fuera de las 8 regiones)" {
    $ahora = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $e = [PSCustomObject]@{
        Nombre='Estacion Norte'; Codigo='Y'; Lat=-18.5; Lon=-69.5
        TasaMmH=0.0; Epoch=$ahora; UltimoDatoEpoch=$ahora; Red='DMC'
        ValoresSerie=@(); TiemposSerie=@()
        Region=$null; DiaRacha=0; AcumuladoHoy=3.2
        UmbralesRegion=$null; ColorPrecipRegional=$null
    }
    $pm = Build-PlacemarkRedes $e

    It "muestra Acumulado hoy aunque no tenga region (para no esconder lluvia real detras de un 0 mm/h)" {
        $pm | Should Match 'Acumulado hoy: 3.2 mm'
    }
    It "no muestra la tabla de umbrales regionales (usa la de mm/h simple)" {
        $pm | Should Match 'Umbrales mm/h'
    }
}

Describe "Build-ChartAcumulado con umbral" {
    $tiempos = @(0..23 | ForEach-Object { 1781600000 + ($_ * 3600) })
    $precip  = @(0..23 | ForEach-Object { 5.0 })

    It "sin umbral no agrega la linea roja" {
        $url = Build-ChartAcumulado $tiempos $precip 24
        $url | Should Not Match 'Umbral%20alerta'
    }
    It "con umbral agrega el dataset de linea roja" {
        $url = Build-ChartAcumulado $tiempos $precip 24 60
        [Uri]::UnescapeDataString($url) | Should Match 'Umbral alerta \(60 mm\)'
        [Uri]::UnescapeDataString($url) | Should Match '#cc0000'
    }
}

Describe "Build-PlacemarkEmas con serie" {
    It "incluye img con temp e iso cuando TiemposSerie tiene 2+ puntos" {
        $e = [PSCustomObject]@{
            Nombre='El Paico'; Codigo='330113'; Lat=-33.7; Lon=-71.0
            Altitud=275.0; TasaMmH=6.5; TempC=8.0; Isoterma=1505; Epoch=1781807400
            ValoresPrecip=@(3.0,5.5,6.5); ValoresTemp=@(9.0,8.5,8.0)
            ValoresIso=@(1659,1582,1505)
            TiemposSerie=@(1781794800,1781798400,1781802000)
        }
        Build-PlacemarkEmas $e | Should Match '<img'
    }
    It "muestra Acumulado hoy cuando existe (aunque TasaMmH sea 0, no esconde la lluvia real)" {
        $e = [PSCustomObject]@{
            Nombre='Juan Fernandez'; Codigo='390099'; Lat=-33.6; Lon=-78.8
            Altitud=5.0; TasaMmH=0.0; TempC=12.0; Isoterma=1847; Epoch=1781807400
            AcumuladoHoy=1.5
        }
        Build-PlacemarkEmas $e | Should Match 'Acumulado hoy: 1.5 mm'
    }
}

# Cargar PronosticoApi.ps1 también (necesario para construir las ventanas de prueba)
. "$here\..\src\PronosticoApi.ps1"

Describe "Build-StylesPronostico" {
    $estilos = Build-StylesPronostico

    It "contiene style amarillo_1" { $estilos | Should Match 'id="amarillo_1"' }
    It "contiene style amarillo_3" { $estilos | Should Match 'id="amarillo_3"' }
    It "contiene style rojo_2"     { $estilos | Should Match 'id="rojo_2"'     }
    It "contiene 7 estilos en total (verde_p + amarillo/rojo x3)" {
        ($estilos | Select-String '<Style id=' -AllMatches).Matches.Count | Should Be 7
    }
}

Describe "Build-PlacemarkPuntoPronostico" {
    $vs = @(
        [PSCustomObject]@{ Nombre='+0 a 6h';   Lat=-33.5; Lon=-70.5; PrecipEcmwf=1.0;  PrecipGfs=0.5;  PrecipIcon=2.0;  IsoEcmwf=3200; IsoGfs=3100; IsoIcon=3400; ColorEcmwf='verde';    ColorGfs='verde';    ColorIcon='verde';    ColorFinal='verde';    NModelos=3; EstiloKml='verde_p'   }
        [PSCustomObject]@{ Nombre='+6 a 12h';  Lat=-33.5; Lon=-70.5; PrecipEcmwf=6.0;  PrecipGfs=7.0;  PrecipIcon=5.0;  IsoEcmwf=2600; IsoGfs=2700; IsoIcon=2800; ColorEcmwf='amarillo'; ColorGfs='amarillo'; ColorIcon='amarillo'; ColorFinal='amarillo'; NModelos=3; EstiloKml='amarillo_3' }
        [PSCustomObject]@{ Nombre='+12 a 24h'; Lat=-33.5; Lon=-70.5; PrecipEcmwf=26.0; PrecipGfs=18.0; PrecipIcon=30.0; IsoEcmwf=3200; IsoGfs=3100; IsoIcon=3400; ColorEcmwf='rojo';     ColorGfs='amarillo'; ColorIcon='rojo';     ColorFinal='rojo';     NModelos=2; EstiloKml='rojo_2'     }
        [PSCustomObject]@{ Nombre='+24 a 48h'; Lat=-33.5; Lon=-70.5; PrecipEcmwf=2.0;  PrecipGfs=1.0;  PrecipIcon=0.0;  IsoEcmwf=3000; IsoGfs=2900; IsoIcon=3100; ColorEcmwf='verde';    ColorGfs='verde';    ColorIcon='verde';    ColorFinal='verde';    NModelos=3; EstiloKml='verde_p'   }
    )
    $pm = Build-PlacemarkPuntoPronostico $vs

    It "es un elemento Placemark"            { $pm | Should Match '<Placemark>' }
    It "usa el peor estilo del punto (rojo_2)" { $pm | Should Match '#rojo_2'   }
    It "incluye las 4 ventanas en el popup"  {
        $pm | Should Match '\+0 a 6h'
        $pm | Should Match '\+6 a 12h'
        $pm | Should Match '\+12 a 24h'
        $pm | Should Match '\+24 a 48h'
    }
    It "tiene una sola coordenada (1 punto)" {
        ([regex]::Matches($pm, '<coordinates>')).Count | Should Be 1
    }
    It "coordenadas lon,lat"                 { $pm | Should Match '-70.5,-33.5' }
}

Describe "Build-PronosticoKml" {
    $fixture = Get-Content "$here\fixtures\openmeteo_2pts.json" -Raw | ConvertFrom-Json
    $puntos  = $fixture | ForEach-Object { Parse-OpenMeteoPoint $_ }
    $ventanas = @()
    foreach ($p in $puntos) { $ventanas += Build-VentanasPunto $p }
    $kml = Build-PronosticoKml $ventanas

    It "contiene declaracion XML"           { $kml | Should Match '<?xml'          }
    It "contiene la carpeta Pronostico 48h" { $kml | Should Match 'Pronostico 48h' }
    It "contiene 2 placemarks (1 por punto)" {
        ($kml | Select-String '<Placemark>' -AllMatches).Matches.Count | Should Be 2
    }
    It "cada popup trae las 4 ventanas"     {
        $kml | Should Match '\+0 a 6h'
        $kml | Should Match '\+24 a 48h'
    }
}

Describe "Build-ChartAcumulado ventana por tiempo (muestras irregulares)" {
    # 3 muestras: hace 40h (fuera de 24h), hace 10h y ahora (dentro de 24h)
    $fin = 1784289600
    $tiempos = @(($fin - 40*3600), ($fin - 10*3600), $fin)
    $precip  = @(30.0, 94.0, 16.0)
    It "el chart de 24h solo incluye las muestras de las ultimas 24 horas" {
        $url = Build-ChartAcumulado $tiempos $precip 24
        $url | Should Match 'quickchart\.io'
        $dec = [uri]::UnescapeDataString($url)
        $dec | Should Match 'Acumulado 24h: 110 mm'
    }
    It "el chart de 48h incluye las 3 muestras" {
        $dec = [uri]::UnescapeDataString((Build-ChartAcumulado $tiempos $precip 48))
        $dec | Should Match 'Acumulado 48h: 140 mm'
    }
    It "Build-GraficosAcumulado pone los acumulados en negrita en el texto" {
        $html = Build-GraficosAcumulado $tiempos $precip
        $html | Should Match '<b>Ultimas 24 h &mdash; acumulado 110 mm</b>'
        $html | Should Match '<b>Ultimas 48 h &mdash; acumulado 140 mm</b>'
    }
}
