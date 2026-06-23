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
