. "$PSScriptRoot\..\src\UmbralesRegionales.ps1"

Describe "Get-RegionPorLat" {
    It "Santiago (-33.45) es Metropolitana" { Get-RegionPorLat -33.45 | Should Be 'Metropolitana' }
    It "Rancagua (-34.17) es OHiggins" { Get-RegionPorLat -34.17 | Should Be 'OHiggins' }
    It "Talca (-35.43) es Maule" { Get-RegionPorLat -35.43 | Should Be 'Maule' }
    It "Temuco (-38.74) es Araucania" { Get-RegionPorLat -38.74 | Should Be 'Araucania' }
    It "Valdivia (-39.81) es LosRios" { Get-RegionPorLat -39.81 | Should Be 'LosRios' }
    It "Puerto Montt (-41.47) es LosLagos" { Get-RegionPorLat -41.47 | Should Be 'LosLagos' }
    It "Arica (-18.5, muy al norte) queda fuera de tabla" { Get-RegionPorLat -18.5 | Should Be $null }
    It "Punta Arenas (-53.2, muy al sur) queda fuera de tabla" { Get-RegionPorLat -53.2 | Should Be $null }
    It "Santiago metropolitano completo (-33.0) sigue siendo Metropolitana" { Get-RegionPorLat -33.0 | Should Be 'Metropolitana' }
}

Describe "Get-UmbralesRegion" {
    It "Metropolitana dia 1" {
        $u = Get-UmbralesRegion 'Metropolitana' 1
        $u.aviso | Should Be 35; $u.alerta | Should Be 71; $u.alarma | Should Be 97
    }
    It "Metropolitana dia 4" {
        $u = Get-UmbralesRegion 'Metropolitana' 4
        $u.aviso | Should Be 21; $u.alerta | Should Be 43; $u.alarma | Should Be 58
    }
    It "dia 4 y siguientes usan la misma fila (dia 7 = dia 4)" {
        (Get-UmbralesRegion 'Maule' 7).aviso | Should Be (Get-UmbralesRegion 'Maule' 4).aviso
    }
    It "dia 0 se trata como dia 1" {
        (Get-UmbralesRegion 'Biobio' 0).aviso | Should Be (Get-UmbralesRegion 'Biobio' 1).aviso
    }
    It "LosRios dia 1: alerta y alarma comparten el mismo umbral (220)" {
        $u = Get-UmbralesRegion 'LosRios' 1
        $u.alerta | Should Be 220; $u.alarma | Should Be 220
    }
    It "region desconocida devuelve null" {
        Get-UmbralesRegion 'Valparaiso' 1 | Should Be $null
    }
}

Describe "Get-ColorPrecipRegional" {
    $u = Get-UmbralesRegion 'Metropolitana' 1   # aviso=35 alerta=71 alarma=97
    It "verde bajo aviso" { Get-ColorPrecipRegional 20 $u | Should Be 'verde' }
    It "amarillo justo en aviso" { Get-ColorPrecipRegional 35 $u | Should Be 'amarillo' }
    It "amarillo entre aviso y alerta" { Get-ColorPrecipRegional 50 $u | Should Be 'amarillo' }
    It "rojo justo en alerta" { Get-ColorPrecipRegional 71 $u | Should Be 'rojo' }
    It "rojo sobre alarma" { Get-ColorPrecipRegional 120 $u | Should Be 'rojo' }
    It "null si no hay umbrales (fuera de tabla)" { Get-ColorPrecipRegional 999 $null | Should Be $null }
}

Describe "Get-AcumuladoCalendario" {
    It "suma solo los valores del dia calendario Chile indicado" {
        # 08:00 y 20:00 hora Chile (UTC-4) del 08-jul-2026 -> caen en '2026-07-08'
        # 23:00 hora Chile del 07-jul-2026 -> cae en '2026-07-07', no debe sumar
        $t08 = [DateTimeOffset]::new(2026,7,8,12,0,0,[TimeSpan]::Zero).ToUnixTimeSeconds()  # 08:00 Chile
        $t20 = [DateTimeOffset]::new(2026,7,9,0,0,0,[TimeSpan]::Zero).ToUnixTimeSeconds()   # 20:00 Chile 08-jul
        $tAyer = [DateTimeOffset]::new(2026,7,8,3,0,0,[TimeSpan]::Zero).ToUnixTimeSeconds() # 23:00 Chile 07-jul
        $tiempos = @($tAyer, $t08, $t20)
        $valores = @(5.0, 2.0, 3.0)
        Get-AcumuladoCalendario $tiempos $valores '2026-07-08' | Should Be 5.0
    }
    It "ignora valores null" {
        $t = [DateTimeOffset]::new(2026,7,8,12,0,0,[TimeSpan]::Zero).ToUnixTimeSeconds()
        Get-AcumuladoCalendario @($t,$t) @(2.0,$null) '2026-07-08' | Should Be 2.0
    }
    It "devuelve 0.0 con serie vacia" {
        Get-AcumuladoCalendario @() @() '2026-07-08' | Should Be 0.0
    }
}

Describe "Update-RachaEstacion" {
    It "primera vez, con lluvia hoy: racha=1" {
        $r = Update-RachaEstacion -EstadoPrev @{} -Codigo 'X' -FechaHoy '2026-07-08' -MmHoy 10.0
        $r.racha | Should Be 1
    }
    It "primera vez, sin lluvia: racha=0" {
        $r = Update-RachaEstacion -EstadoPrev @{} -Codigo 'X' -FechaHoy '2026-07-08' -MmHoy 0.0
        $r.racha | Should Be 0
    }
    It "mismo dia calendario: mantiene la racha y actualiza el acumulado" {
        $prev = @{ 'X' = @{ fecha='2026-07-08'; acumuladoDia=5.0; racha=2 } }
        $r = Update-RachaEstacion -EstadoPrev $prev -Codigo 'X' -FechaHoy '2026-07-08' -MmHoy 8.0
        $r.racha | Should Be 2
        $r.acumuladoDia | Should Be 8.0
    }
    It "dia siguiente, ayer llovio, hoy tambien: racha avanza a 3" {
        $prev = @{ 'X' = @{ fecha='2026-07-07'; acumuladoDia=12.0; racha=2 } }
        $r = Update-RachaEstacion -EstadoPrev $prev -Codigo 'X' -FechaHoy '2026-07-08' -MmHoy 5.0
        $r.racha | Should Be 3
    }
    It "dia siguiente, ayer NO llovio (0mm): racha se corta a 1 (si hoy llueve)" {
        $prev = @{ 'X' = @{ fecha='2026-07-07'; acumuladoDia=0.0; racha=3 } }
        $r = Update-RachaEstacion -EstadoPrev $prev -Codigo 'X' -FechaHoy '2026-07-08' -MmHoy 5.0
        $r.racha | Should Be 1
    }
    It "dia siguiente, ayer llovio pero hoy no (todavia): racha a 0" {
        $prev = @{ 'X' = @{ fecha='2026-07-07'; acumuladoDia=8.0; racha=1 } }
        $r = Update-RachaEstacion -EstadoPrev $prev -Codigo 'X' -FechaHoy '2026-07-08' -MmHoy 0.0
        $r.racha | Should Be 0
    }
    It "salto de mas de 1 dia (cron caido): corta la racha aunque ayer hubiera llovido" {
        $prev = @{ 'X' = @{ fecha='2026-07-01'; acumuladoDia=20.0; racha=4 } }
        $r = Update-RachaEstacion -EstadoPrev $prev -Codigo 'X' -FechaHoy '2026-07-08' -MmHoy 5.0
        $r.racha | Should Be 1
    }
}

Describe "Read-EstadoRacha / Save-EstadoRacha" {
    It "guarda y relee" {
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            Save-EstadoRacha $tmp @{ '390015' = @{ fecha='2026-07-08'; acumuladoDia=5.5; racha=2 } }
            $r = Read-EstadoRacha $tmp
            $r['390015'].fecha | Should Be '2026-07-08'
            $r['390015'].acumuladoDia | Should Be 5.5
            $r['390015'].racha | Should Be 2
        } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
    }
}

Describe "Add-InfoRegional" {
    $estaciones = @(
        [PSCustomObject]@{ Codigo='A'; Lat=-33.45; AcumuladoHoy=40.0 }   # RM, sobre aviso(35) bajo alerta(71)
        [PSCustomObject]@{ Codigo='B'; Lat=-18.5;  AcumuladoHoy=999.0 }  # fuera de tabla
    )
    $nuevoEstado = Add-InfoRegional -Estaciones $estaciones -EstadoPrev @{} -FechaHoy '2026-07-08'

    It "anota Region en la estacion cubierta" { $estaciones[0].Region | Should Be 'Metropolitana' }
    It "calcula ColorPrecipRegional amarillo" { $estaciones[0].ColorPrecipRegional | Should Be 'amarillo' }
    It "DiaRacha es 1 (primera corrida, con lluvia)" { $estaciones[0].DiaRacha | Should Be 1 }
    It "estacion fuera de tabla no tiene Region ni color regional" {
        $estaciones[1].Region | Should Be $null
        $estaciones[1].ColorPrecipRegional | Should Be $null
    }
    It "devuelve el estado nuevo para persistir" {
        $nuevoEstado['A'].racha | Should Be 1
        $nuevoEstado.ContainsKey('B') | Should Be $true
    }
}
