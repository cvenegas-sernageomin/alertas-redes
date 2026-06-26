$here = $PSScriptRoot
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

Describe "Build-PlacemarkPronostico" {
    $v = [PSCustomObject]@{
        Nombre='+12 a 24h'; Lat=-33.5; Lon=-70.5
        PrecipEcmwf=26.0; PrecipGfs=18.0; PrecipIcon=30.0
        IsoEcmwf=3200; IsoGfs=3100; IsoIcon=3400
        ColorEcmwf='rojo'; ColorGfs='amarillo'; ColorIcon='rojo'
        ColorFinal='rojo'; NModelos=2; EstiloKml='rojo_2'
    }
    $pm = Build-PlacemarkPronostico $v

    It "es un elemento Placemark"          { $pm | Should Match '<Placemark>'   }
    It "usa styleUrl rojo_2"               { $pm | Should Match '#rojo_2'       }
    It "contiene ECMWF en descripcion"     { $pm | Should Match 'ECMWF'         }
    It "contiene GFS en descripcion"       { $pm | Should Match 'GFS'           }
    It "contiene ICON en descripcion"      { $pm | Should Match 'ICON'          }
    It "coordenadas lon,lat"               { $pm | Should Match '-70.5,-33.5'   }
}

Describe "Build-PronosticoKml" {
    $fixture = Get-Content "$here\fixtures\openmeteo_2pts.json" -Raw | ConvertFrom-Json
    $puntos  = $fixture | ForEach-Object { Parse-OpenMeteoPoint $_ }
    $ventanas = @()
    foreach ($p in $puntos) { $ventanas += Build-VentanasPunto $p }
    $kml = Build-PronosticoKml $ventanas

    It "contiene declaracion XML"        { $kml | Should Match '<?xml'        }
    It "contiene carpeta +0 a 6h"        { $kml | Should Match '\+0 a 6h'     }
    It "contiene carpeta +12 a 24h"      { $kml | Should Match '\+12 a 24h'   }
    It "contiene carpeta +24 a 48h"      { $kml | Should Match '\+24 a 48h'   }
    It "contiene 8 placemarks (2pts x 4ventanas)" {
        ($kml | Select-String '<Placemark>' -AllMatches).Matches.Count | Should Be 8
    }
    It "contiene estilo rojo_2" { $kml | Should Match 'rojo_2' }
}
