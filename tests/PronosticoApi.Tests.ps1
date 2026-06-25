$here = $PSScriptRoot
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
    It "todas las longitudes dentro del rango de Chile" {
        $grilla | ForEach-Object {
            $_.Lon | Should BeGreaterThan -78.0
            $_.Lon | Should BeLessThan  -66.0
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
