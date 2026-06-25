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
