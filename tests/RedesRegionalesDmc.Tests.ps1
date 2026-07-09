. "$PSScriptRoot\..\src\DmcDirecto.ps1"
. "$PSScriptRoot\..\src\RedesRegionalesDmc.ps1"

Describe "Get-EstacionesBoletinRegion (fixture real region 01)" {
    $html = Get-Content "$PSScriptRoot\fixtures\boletin_region01.html" -Raw
    $est = Get-EstacionesBoletinRegion -Html $html

    It "extrae las 5 estaciones de la tabla" {
        $est.Count | Should Be 5
    }
    It "extrae codigo, nombre y propietario correctamente" {
        $inia = $est | Where-Object { $_.Codigo -eq '200011' }
        $inia.Nombre | Should Be 'Pica Inia'
        $inia.Propietario | Should Be 'INIA'
    }
    It "las estaciones DMC tambien se extraen (el filtro es responsabilidad del llamador)" {
        @($est | Where-Object { $_.Propietario -eq 'DMC' }).Count | Should Be 4
    }
    It "devuelve array vacio si no hay tabla" {
        (Get-EstacionesBoletinRegion -Html "sin tabla aqui").Count | Should Be 0
    }
}

Describe "Get-EstacionesRegionalesDirecto (fixture real, sin red)" {
    $html = Get-Content "$PSScriptRoot\fixtures\inia_ema_330026.html" -Raw
    Mock Get-DmcHtmlGzip { return $html }
    $estaciones = @([PSCustomObject]@{ Codigo='330026'; Nombre='La Platina ( INIA )'; Propietario='INIA' })
    $r = Get-EstacionesRegionalesDirecto -Estaciones $estaciones -EstadoPrev @{} -ThrottleMs 0

    It "produce 1 estacion" { $r.Redes.Count | Should Be 1 }
    It "usa el Propietario como Red" { $r.Redes[0].Red | Should Be 'INIA' }
    It "toma el nombre real de la pagina (no el del boletin)" {
        $r.Redes[0].Nombre | Should Match 'La Platina'
    }
    It "extrae lat/lon reales" {
        $r.Redes[0].Lat | Should Not Be $null
        $r.Redes[0].Lon | Should Not Be $null
    }
    It "marca la fuente confirmada con el propietario" {
        $r.Redes[0].OrgConfirmada | Should Be 'INIA directo'
    }
    It "sin dato de precipitacion valido (esta estacion mostraba '.' hoy): AcumuladoHoy=0" {
        $r.Redes[0].AcumuladoHoy | Should Be 0.0
    }
}

Describe "Get-EstacionesRegionalesDirecto (estacion inexistente)" {
    Mock Get-DmcHtmlGzip { throw "404" }
    $estaciones = @([PSCustomObject]@{ Codigo='999999'; Nombre='No existe'; Propietario='FDF' })
    $r = Get-EstacionesRegionalesDirecto -Estaciones $estaciones -EstadoPrev @{} -ThrottleMs 0

    It "cuenta como fallida sin detener el resto" {
        $r.Fallidas | Should Be 1
        $r.Redes.Count | Should Be 0
    }
}
