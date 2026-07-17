. "$PSScriptRoot\..\src\DmcDirecto.ps1"
. "$PSScriptRoot\..\src\RedMeteoDirecto.ps1"

Describe "ConvertTo-EpochIsoUtc" {
    It "convierte ISO 8601 UTC con Z" {
        ConvertTo-EpochIsoUtc '2026-07-17T04:00:00Z' | Should Be 1784260800
    }
    It "devuelve null con texto ilegible" {
        ConvertTo-EpochIsoUtc 'no-es-fecha' | Should Be $null
    }
    It "devuelve null con vacio" {
        ConvertTo-EpochIsoUtc '' | Should Be $null
    }
}

Describe "Get-FechaChileDeEpoch" {
    It "04:00 UTC del 17 jul es 00:00 del 17 en Chile (UTC-4 invierno)" {
        Get-FechaChileDeEpoch 1784260800 | Should Be '2026-07-17'
    }
    It "03:59 UTC del 17 jul todavia es 16 jul en Chile" {
        Get-FechaChileDeEpoch 1784260740 | Should Be '2026-07-16'
    }
}

Describe "Get-EstacionesRedMeteoDirecto (sinteticos)" {
    # 07:00 UTC = 03:00 Chile del mismo dia -> "hoy"
    $obs = @(
        [pscustomobject]@{ id_estacion='RMCL0001'; nombre='Fresca con lluvia'; latitud=-33.0; longitud=-71.0; fecha_hora='2026-07-17T07:00:00Z'; lluviadiaria=10.0 },
        [pscustomobject]@{ id_estacion='RMCL0002'; nombre='Muerta hace meses'; latitud=-20.0; longitud=-70.0; fecha_hora='2026-03-14T15:49:12Z'; lluviadiaria=99.0 },
        [pscustomobject]@{ id_estacion='RMCL0003'; nombre='Sin coordenadas'; latitud=$null; longitud=-70.0; fecha_hora='2026-07-17T07:00:00Z'; lluviadiaria=1.0 },
        [pscustomobject]@{ id_estacion='RMCL0001'; nombre='Duplicada'; latitud=-33.0; longitud=-71.0; fecha_hora='2026-07-17T07:00:00Z'; lluviadiaria=10.0 },
        [pscustomobject]@{ id_estacion='RMCL0004'; nombre='Fecha ilegible'; latitud=-35.0; longitud=-71.5; fecha_hora='no-es-fecha'; lluviadiaria=5.0 }
    )
    $epochPrev = ConvertTo-EpochIsoUtc '2026-07-17T05:00:00Z'
    $prev = @{ 'RMCL0001' = @{ precip = 4.0; epoch = [int64]$epochPrev; historia = @(@{ epoch = [int64]$epochPrev; precip = 4.0 }) } }
    $r = Get-EstacionesRedMeteoDirecto -Observaciones $obs -EstadoPrev $prev -FechaChile '2026-07-17' `
        -AhoraEpoch (ConvertTo-EpochIsoUtc '2026-07-17T07:30:00Z')

    It "acepta 3 y descarta 2 (sin lat/lon + duplicada)" {
        $r.Ok | Should Be 3
        $r.Descartadas | Should Be 2
    }
    It "tasa mm/h por diferencia contra la corrida anterior: (10-4)/2h = 3" {
        ($r.Redes | Where-Object Codigo -eq 'RMCL0001').TasaMmH | Should Be 3.0
    }
    It "AcumuladoHoy = lluviadiaria cuando el dato es de hoy (Chile)" {
        ($r.Redes | Where-Object Codigo -eq 'RMCL0001').AcumuladoHoy | Should Be 10.0
    }
    It "estacion muerta hace meses: AcumuladoHoy=null/'s/d' (su lluviadiaria es de OTRO dia, NO un 0 falso)" {
        ($r.Redes | Where-Object Codigo -eq 'RMCL0002').AcumuladoHoy | Should Be $null
    }
    It "estacion muerta conserva su UltimoDatoEpoch real (para pintarse gris)" {
        ($r.Redes | Where-Object Codigo -eq 'RMCL0002').UltimoDatoEpoch | Should Not Be $null
    }
    It "fecha ilegible: UltimoDatoEpoch null y Epoch 0 (mismo patron que vismet sin timestamps)" {
        $e4 = $r.Redes | Where-Object Codigo -eq 'RMCL0004'
        $e4.UltimoDatoEpoch | Should Be $null
        $e4.Epoch | Should Be 0
    }
    It "todas quedan con Red=RedMeteo y fuente confirmada" {
        @($r.Redes | Where-Object { $_.Red -eq 'RedMeteo' -and $_.OrgConfirmada -eq 'RedMeteo directo' }).Count | Should Be 3
    }
    It "el estado nuevo solo guarda estaciones con dato de hoy" {
        @($r.EstadoNuevo.Keys) | Should Be @('RMCL0001')
    }
    It "la historia acumula la muestra nueva sobre la previa + el 0 de medianoche sembrado" {
        $r.EstadoNuevo['RMCL0001'].historia.Count | Should Be 3
    }
    It "la serie parte del 0 de medianoche y trae los deltas (0, 4, 6)" {
        $e1 = $r.Redes | Where-Object Codigo -eq 'RMCL0001'
        $e1.ValoresSerie.Count | Should Be 3
        $e1.ValoresSerie[0] | Should Be 0.0
        $e1.ValoresSerie[1] | Should Be 4.0
        $e1.ValoresSerie[2] | Should Be 6.0
    }
}

Describe "Get-EstacionesRedMeteoDirecto (primera corrida, sin estado previo)" {
    $obs = @(
        [pscustomobject]@{ id_estacion='RMCL0010'; nombre='Nueva'; latitud=-33.0; longitud=-71.0; fecha_hora='2026-07-17T07:00:00Z'; lluviadiaria=12.5 }
    )
    $r = Get-EstacionesRedMeteoDirecto -Observaciones $obs -EstadoPrev @{} -FechaChile '2026-07-17' `
        -AhoraEpoch (ConvertTo-EpochIsoUtc '2026-07-17T07:30:00Z')

    It "TasaMmH=0 (sin base para diferenciar, se autocorrige al siguiente ciclo)" {
        $r.Redes[0].TasaMmH | Should Be 0.0
    }
    It "AcumuladoHoy si viene aunque no haya tasa" {
        $r.Redes[0].AcumuladoHoy | Should Be 12.5
    }
    It "el estado inicial guarda la primera muestra + el 0 de medianoche sembrado" {
        $r.EstadoNuevo['RMCL0010'].precip | Should Be 12.5
        $r.EstadoNuevo['RMCL0010'].historia.Count | Should Be 2
    }
    It "primera corrida con lluvia: YA hay serie graficable (00:00=0 -> ahora=12.5)" {
        $r.Redes[0].TiemposSerie.Count | Should Be 2
        $r.Redes[0].ValoresSerie[0] | Should Be 0.0
        $r.Redes[0].ValoresSerie[1] | Should Be 12.5
    }
}

Describe "Get-EstacionesRedMeteoDirecto (reset de medianoche)" {
    # Corrida previa: 23:50 Chile de ayer con 30mm. Ahora: 01:00 Chile con 2mm (reseteo).
    $epochAyer = ConvertTo-EpochIsoUtc '2026-07-17T03:50:00Z'   # 23:50 Chile del 16
    $prev = @{ 'RMCL0020' = @{ precip = 30.0; epoch = [int64]$epochAyer; historia = @(@{ epoch = [int64]$epochAyer; precip = 30.0 }) } }
    $obs = @(
        [pscustomobject]@{ id_estacion='RMCL0020'; nombre='Reset'; latitud=-33.0; longitud=-71.0; fecha_hora='2026-07-17T05:00:00Z'; lluviadiaria=2.0 }
    )
    $r = Get-EstacionesRedMeteoDirecto -Observaciones $obs -EstadoPrev $prev -FechaChile '2026-07-17' `
        -AhoraEpoch (ConvertTo-EpochIsoUtc '2026-07-17T05:10:00Z')

    It "delta negativo se trata como 'caido desde el reset': 2mm en ~1.17h" {
        $r.Redes[0].TasaMmH | Should Be ([math]::Round(2.0 / (70.0/60.0), 2))
    }
    It "AcumuladoHoy es el nuevo acumulado post-reset" {
        $r.Redes[0].AcumuladoHoy | Should Be 2.0
    }
}
