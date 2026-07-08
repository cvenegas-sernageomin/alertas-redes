$here = $PSScriptRoot
. "$here\..\src\UmbralesRegionales.ps1"
. "$here\..\src\PronosticoApi.ps1"

Describe "Get-GrillaChile" {
    $grilla = Get-GrillaChile

    It "devuelve mas de 50 puntos" {
        $grilla.Count | Should BeGreaterThan 50
    }
    It "todos los puntos tienen Lat y Lon" {
        $grilla | ForEach-Object {
            $_.Lat | Should Not BeNullOrEmpty
            $_.Lon | Should Not BeNullOrEmpty
        }
    }
    It "todas las latitudes dentro del rango de Chile" {
        $grilla | ForEach-Object {
            $_.Lat | Should BeGreaterThan -57.0
            $_.Lat | Should BeLessThan  -17.0
        }
    }
    It "todas las longitudes dentro del rango de Chile (continental e insular)" {
        $grilla | ForEach-Object {
            $_.Lon | Should BeGreaterThan -111.0
            $_.Lon | Should BeLessThan   -66.0
        }
    }
    It "no hay puntos al este de Argentina (lon > -65)" {
        ($grilla | Where-Object { $_.Lon -gt -65 }).Count | Should Be 0
    }
}

Describe "Parse-OpenMeteoPoint" {
    $fixture = Get-Content "$here\fixtures\openmeteo_2pts.json" -Raw | ConvertFrom-Json

    It "parsea lat del punto 1" {
        (Parse-OpenMeteoPoint $fixture[0]).Lat | Should Be -33.5
    }
    It "parsea lon del punto 1" {
        (Parse-OpenMeteoPoint $fixture[0]).Lon | Should Be -70.5
    }
    It "HourlyPrecipEcmwf tiene 48 valores" {
        (Parse-OpenMeteoPoint $fixture[0]).HourlyPrecipEcmwf.Count | Should Be 48
    }
    It "HourlyIsoIcon tiene null en indice 2" {
        (Parse-OpenMeteoPoint $fixture[0]).HourlyIsoIcon[2] | Should BeNullOrEmpty
    }
    It "HourlyIsoEcmwf[0] es 3200" {
        (Parse-OpenMeteoPoint $fixture[0]).HourlyIsoEcmwf[0] | Should Be 3200
    }
}

Describe "Get-SumaVentana" {
    $fixture  = Get-Content "$here\fixtures\openmeteo_2pts.json" -Raw | ConvertFrom-Json
    $punto1   = Parse-OpenMeteoPoint $fixture[0]

    It "suma ECMWF ventana +6 a 12h = 7" {
        Get-SumaVentana $punto1.HourlyPrecipEcmwf 6 11 | Should Be 7.0
    }
    It "suma ECMWF ventana +12 a 24h = 26" {
        Get-SumaVentana $punto1.HourlyPrecipEcmwf 12 23 | Should Be 26.0
    }
    It "suma GFS ventana +12 a 24h = 18" {
        Get-SumaVentana $punto1.HourlyPrecipGfs 12 23 | Should Be 18.0
    }
    It "suma ICON ventana +6 a 12h = 12" {
        Get-SumaVentana $punto1.HourlyPrecipIcon 6 11 | Should Be 12.0
    }
    It "suma ECMWF ventana +0 a 6h = 0" {
        Get-SumaVentana $punto1.HourlyPrecipEcmwf 0 5 | Should Be 0.0
    }
    It "null cuenta como 0 en suma" {
        $serie = @(1.0, $null, 2.0)
        Get-SumaVentana $serie 0 2 | Should Be 3.0
    }
}

Describe "Get-MinVentana" {
    $fixture = Get-Content "$here\fixtures\openmeteo_2pts.json" -Raw | ConvertFrom-Json
    $punto1  = Parse-OpenMeteoPoint $fixture[0]

    It "min ECMWF en cualquier ventana = 3200" {
        Get-MinVentana $punto1.HourlyIsoEcmwf 0 5 | Should Be 3200
    }
    It "min ICON ventana +0 a 6h = 3400 (ignora null)" {
        Get-MinVentana $punto1.HourlyIsoIcon 0 5 | Should Be 3400
    }
    It "min GFS en cualquier ventana = 3100" {
        Get-MinVentana $punto1.HourlyIsoGfs 6 11 | Should Be 3100
    }
    It "retorna null cuando todos los valores son null" {
        $serie = @($null, $null, $null)
        Get-MinVentana $serie 0 2 | Should BeNullOrEmpty
    }
}

Describe "Get-ColorPronostico" {
    It "verde cuando precip=0"                     { Get-ColorPronostico 0.0  3200 | Should Be 'verde'    }
    It "verde cuando precip < 5"                   { Get-ColorPronostico 4.9  3200 | Should Be 'verde'    }
    It "verde cuando iso < 2500 aunque precip alta"{ Get-ColorPronostico 30.0 2499 | Should Be 'verde'    }
    It "verde cuando iso es null"                  { Get-ColorPronostico 30.0 $null | Should Be 'verde'   }
    It "amarillo cuando precip=5 e iso=2500"       { Get-ColorPronostico 5.0  2500 | Should Be 'amarillo' }
    It "amarillo cuando precip=19 e iso=3000"      { Get-ColorPronostico 19.0 3000 | Should Be 'amarillo' }
    It "rojo cuando precip=20 e iso=3000"          { Get-ColorPronostico 20.0 3000 | Should Be 'rojo'     }
    It "rojo cuando precip=30 e iso=3500"          { Get-ColorPronostico 30.0 3500 | Should Be 'rojo'     }
}

Describe "Get-ColorPeorYN" {
    It "verde cuando todos son verde" {
        $r = Get-ColorPeorYN @('verde','verde','verde')
        $r.Color | Should Be 'verde'; $r.N | Should Be 3
    }
    It "peor color y cuenta cuantos modelos coinciden en el peor" {
        $r = Get-ColorPeorYN @('verde','amarillo','amarillo')
        $r.Color | Should Be 'amarillo'; $r.N | Should Be 2
    }
    It "rojo gana aunque sea 1 solo modelo" {
        $r = Get-ColorPeorYN @('verde','amarillo','rojo')
        $r.Color | Should Be 'rojo'; $r.N | Should Be 1
    }
}

Describe "Get-AlertaPrecipRegionalPunto" {
    $fixture = Get-Content "$here\fixtures\openmeteo_2pts.json" -Raw | ConvertFrom-Json
    $puntoRM  = Parse-OpenMeteoPoint $fixture[0]   # lat -33.5 -> Metropolitana
    $puntoSur = Parse-OpenMeteoPoint $fixture[1]   # lat -45.0 -> fuera de tabla

    It "asigna la region cuando el punto cae dentro de la tabla" {
        (Get-AlertaPrecipRegionalPunto $puntoRM).Region | Should Be 'Metropolitana'
    }
    It "devuelve null cuando el punto esta fuera de la tabla" {
        Get-AlertaPrecipRegionalPunto $puntoSur | Should Be $null
    }
    It "usa los umbrales de dia 1 y dia 2 de la region" {
        $a = Get-AlertaPrecipRegionalPunto $puntoRM
        $a.UmbralesDia1.aviso | Should Be (Get-UmbralesRegion 'Metropolitana' 1).aviso
        $a.UmbralesDia2.aviso | Should Be (Get-UmbralesRegion 'Metropolitana' 2).aviso
    }
}

Describe "Build-VentanasPunto incluye AlertaRegional" {
    $fixture = Get-Content "$here\fixtures\openmeteo_2pts.json" -Raw | ConvertFrom-Json
    $puntoRM = Parse-OpenMeteoPoint $fixture[0]
    $v = Build-VentanasPunto $puntoRM

    It "todas las ventanas del punto comparten la misma AlertaRegional" {
        $v[0].AlertaRegional.Region | Should Be 'Metropolitana'
        $v[3].AlertaRegional.Region | Should Be 'Metropolitana'
    }
}

Describe "Get-EstiloPronostico" {
    It "verde da verde_p"     { Get-EstiloPronostico 'verde'    0 | Should Be 'verde_p'   }
    It "amarillo_1"           { Get-EstiloPronostico 'amarillo' 1 | Should Be 'amarillo_1' }
    It "amarillo_2"           { Get-EstiloPronostico 'amarillo' 2 | Should Be 'amarillo_2' }
    It "amarillo_3"           { Get-EstiloPronostico 'amarillo' 3 | Should Be 'amarillo_3' }
    It "rojo_2"               { Get-EstiloPronostico 'rojo'     2 | Should Be 'rojo_2'     }
    It "rojo_3"               { Get-EstiloPronostico 'rojo'     3 | Should Be 'rojo_3'     }
}

Describe "Build-VentanasPunto" {
    $fixture = Get-Content "$here\fixtures\openmeteo_2pts.json" -Raw | ConvertFrom-Json
    $punto1  = Parse-OpenMeteoPoint $fixture[0]
    $punto2  = Parse-OpenMeteoPoint $fixture[1]
    $v1      = Build-VentanasPunto $punto1
    $v2      = Build-VentanasPunto $punto2

    It "devuelve 4 ventanas por punto" {
        $v1.Count | Should Be 4
    }
    It "ventana +0 a 6h de punto 1 es verde_p" {
        ($v1 | Where-Object { $_.Nombre -eq '+0 a 6h' }).EstiloKml | Should Be 'verde_p'
    }
    It "ventana +6 a 12h de punto 1 es amarillo_2" {
        ($v1 | Where-Object { $_.Nombre -eq '+6 a 12h' }).EstiloKml | Should Be 'amarillo_2'
    }
    It "ventana +12 a 24h de punto 1 es rojo_2" {
        ($v1 | Where-Object { $_.Nombre -eq '+12 a 24h' }).EstiloKml | Should Be 'rojo_2'
    }
    It "ventana +24 a 48h de punto 1 es verde_p" {
        ($v1 | Where-Object { $_.Nombre -eq '+24 a 48h' }).EstiloKml | Should Be 'verde_p'
    }
    It "todas las ventanas de punto 2 son verde_p (iso baja)" {
        ($v2 | Where-Object { $_.EstiloKml -ne 'verde_p' }).Count | Should Be 0
    }
    It "ventana +12 a 24h de punto 1 tiene PrecipEcmwf = 26" {
        ($v1 | Where-Object { $_.Nombre -eq '+12 a 24h' }).PrecipEcmwf | Should Be 26.0
    }
    It "ventana +12 a 24h de punto 1 ColorGfs = amarillo" {
        ($v1 | Where-Object { $_.Nombre -eq '+12 a 24h' }).ColorGfs | Should Be 'amarillo'
    }
    It "ventana +12 a 24h de punto 1 NModelos = 2" {
        ($v1 | Where-Object { $_.Nombre -eq '+12 a 24h' }).NModelos | Should Be 2
    }
}
