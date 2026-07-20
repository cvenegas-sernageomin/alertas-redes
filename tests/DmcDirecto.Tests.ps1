. "$PSScriptRoot\..\src\DmcDirecto.ps1"

$html = Get-Content "$PSScriptRoot\fixtures\dmc_ema_390015.html" -Raw

Describe "Get-EmaInfoDirecto (fixture real 390015)" {
    $info = Get-EmaInfoDirecto -Html $html
    It "extrae el nombre" { $info.Nombre | Should Match "Isla Teja" }
    It "extrae la altitud" { $info.Altitud | Should Be 15.0 }
    It "extrae latitud y longitud" {
        $info.Lat | Should Not Be $null
        $info.Lon | Should Not Be $null
    }
    It "extrae la hora del ultimo dato (string)" { $info.UltimoDato | Should Match '\d{1,2}:\d{2}\s+\d{1,2}\s+[A-Za-z]{3}\s+\d{4}' }
}

Describe "Get-EmaTempActualDirecto" {
    It "toma el ultimo valor no nulo de la serie (snippet sintetico)" {
        $snip = "Highcharts.chart('temperatura', { xAxis: { categories: [`"00:00`",`"00:01`"] }, series: [{ name: '15-06-2026', data: [7.5,8.1,9.0,null,null] }] });"
        Get-EmaTempActualDirecto -Html $snip | Should Be 9.0
    }
    It "devuelve un numero sobre el fixture real" {
        $real = Get-EmaTempActualDirecto -Html $html
        $real | Should Not BeNullOrEmpty
    }
    It "devuelve null si no hay grafico" {
        Get-EmaTempActualDirecto -Html "sin grafico" | Should Be $null
    }
}

Describe "Get-EmaPrecipHoyDirecto" {
    It "interpreta s/p como 0.0" {
        $snip = "<h4> Hoy </h4></td><td class='text-center'><h4> s/p</h4></td>"
        Get-EmaPrecipHoyDirecto -Html $snip | Should Be 0.0
    }
    It "extrae un valor numerico en mm (snippet sintetico)" {
        $snip = "<h4> Hoy </h4></td><td class='text-center'><h4> 12.4</h4></td>"
        Get-EmaPrecipHoyDirecto -Html $snip | Should Be 12.4
    }
    It "extrae lluvia real del fixture (Isla Teja tenia 0.7mm el 2026-07-08)" {
        Get-EmaPrecipHoyDirecto -Html $html | Should Be 0.7
    }
    It "devuelve null si no encuentra la fila Hoy" {
        Get-EmaPrecipHoyDirecto -Html "<table></table>" | Should Be $null
    }
}

Describe "ConvertTo-EpochChile" {
    It "convierte 'HH:mm dd MMM yyyy' (mes en ingles) a epoch UTC" {
        $epoch = ConvertTo-EpochChile "08:30 08 Jul 2026"
        $epoch | Should Not Be $null
        # 08:30 hora Chile (UTC-4 en julio, sin horario de verano) = 12:30 UTC
        [DateTimeOffset]::FromUnixTimeSeconds($epoch).UtcDateTime.ToString('HH:mm') | Should Be '12:30'
    }
    It "acepta mes en espanol abreviado" {
        $epoch = ConvertTo-EpochChile "10:00 01 Ene 2026"
        $epoch | Should Not Be $null
    }
    It "devuelve null con texto vacio o invalido" {
        ConvertTo-EpochChile "" | Should Be $null
        ConvertTo-EpochChile "no es una fecha" | Should Be $null
    }
}

Describe "Get-PrecipRateDirecto" {
    It "calcula mm/h entre dos corridas (2.5 mm en 900s = 10 mm/h)" {
        Get-PrecipRateDirecto -PrecipActual 2.5 -EpochActual 1000900 -PrecipPrev 0.0 -EpochPrev 1000000 | Should Be 10
    }
    It "en reset de medianoche usa el acumulado actual como caido desde el reset" {
        # 00:10 con 0.5mm ya acumulados, corrida previa 23:55 con 8.0mm (dia anterior) -> delta negativo
        $epochPrev = 1000000
        $epochAct  = $epochPrev + 900   # 15 min despues
        $r = Get-PrecipRateDirecto -PrecipActual 0.5 -EpochActual $epochAct -PrecipPrev 8.0 -EpochPrev $epochPrev
        $r | Should Be 2.0   # 0.5mm en 0.25h
    }
    It "devuelve null si no hay corrida previa" {
        Get-PrecipRateDirecto -PrecipActual 3.0 -EpochActual 1000 -PrecipPrev $null -EpochPrev $null | Should Be $null
    }
}

Describe "Get-SerieDesdeHistoria" {
    It "con menos de 2 muestras no hay serie" {
        $s = Get-SerieDesdeHistoria @(@{ epoch=1000; precip=0.0 })
        $s.Tiempos.Count | Should Be 0
    }
    It "calcula el delta entre muestras consecutivas (con punto inicial 0 real)" {
        $h = @(
            @{ epoch=1000; precip=0.0 }
            @{ epoch=4600; precip=2.0 }
            @{ epoch=8200; precip=5.0 }
        )
        $s = Get-SerieDesdeHistoria $h
        $s.Tiempos.Count | Should Be 3
        $s.Valores[0] | Should Be 0.0
        $s.Valores[1] | Should Be 2.0
        $s.Valores[2] | Should Be 3.0
    }
    It "ordena la historia por epoch antes de calcular (por si llega desordenada)" {
        $h = @(
            @{ epoch=8200; precip=5.0 }
            @{ epoch=1000; precip=0.0 }
            @{ epoch=4600; precip=2.0 }
        )
        $s = Get-SerieDesdeHistoria $h
        $s.Valores[0] | Should Be 0.0
        $s.Valores[1] | Should Be 2.0
        $s.Valores[2] | Should Be 3.0
    }
    It "si la primera muestra NO es 0, no se emite punto inicial (delta desconocido)" {
        $h = @(
            @{ epoch=1000; precip=4.0 }
            @{ epoch=4600; precip=6.0 }
        )
        $s = Get-SerieDesdeHistoria $h
        $s.Tiempos.Count | Should Be 1
        $s.Valores[0] | Should Be 2.0
    }
    It "maneja el reset de medianoche (delta negativo -> usa el acumulado actual)" {
        $h = @(
            @{ epoch=1000; precip=8.0 }
            @{ epoch=4600; precip=0.5 }
        )
        $s = Get-SerieDesdeHistoria $h
        $s.Valores[0] | Should Be 0.5
    }
}

Describe "Add-MuestraHistoria" {
    It "agrega la muestra nueva" {
        $h = Add-MuestraHistoria -Historia @() -Epoch 1000 -Precip 2.0 -AhoraEpoch 1000
        $h.Count | Should Be 1
        $h[0].precip | Should Be 2.0
    }
    It "descarta muestras mas viejas que la ventana (50h por defecto)" {
        $vieja = @{ epoch = 1000; precip = 1.0 }
        $ahora = 1000 + (51 * 3600)
        $h = Add-MuestraHistoria -Historia @($vieja) -Epoch $ahora -Precip 3.0 -AhoraEpoch $ahora
        $h.Count | Should Be 1
        $h[0].precip | Should Be 3.0
    }
    It "conserva muestras dentro de la ventana" {
        $reciente = @{ epoch = 1000; precip = 1.0 }
        $ahora = 1000 + (10 * 3600)
        $h = Add-MuestraHistoria -Historia @($reciente) -Epoch $ahora -Precip 3.0 -AhoraEpoch $ahora
        $h.Count | Should Be 2
    }
    It "no agrega nada si Precip es null (corrida fallida)" {
        $h = Add-MuestraHistoria -Historia @() -Epoch 1000 -Precip $null -AhoraEpoch 1000
        $h.Count | Should Be 0
    }
}

Describe "Read-EstadoDmc / Save-EstadoDmc" {
    It "guarda y relee el estado" {
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            Save-EstadoDmc $tmp @{ '390015' = @{ precip = 0.7; epoch = 1000000 } }
            $r = Read-EstadoDmc $tmp
            $r['390015'].precip | Should Be 0.7
            $r['390015'].epoch  | Should Be 1000000
        } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
    }
    It "guarda y relee la historia" {
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            Save-EstadoDmc $tmp @{ '390015' = @{ precip = 0.7; epoch = 1000000; historia = @(@{epoch=900000;precip=0.2},@{epoch=1000000;precip=0.7}) } }
            $r = Read-EstadoDmc $tmp
            $r['390015'].historia.Count | Should Be 2
            $r['390015'].historia[1].precip | Should Be 0.7
        } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
    }
    It "devuelve hashtable vacio si el archivo no existe" {
        $r = Read-EstadoDmc "$PSScriptRoot\no_existe_$(Get-Random).json"
        $r.Count | Should Be 0
    }
}

Describe "Get-EstacionesDmcDirecto (contra fixture, sin red)" {
    # Mockea Get-DmcHtmlGzip para no golpear la red real en el test suite
    Mock Get-DmcHtmlGzip { return $html }
    $r = Get-EstacionesDmcDirecto -Codigos @('390015') -EstadoPrev @{} -ThrottleMs 0

    It "produce 1 estacion Redes y 1 Emas" {
        $r.Redes.Count | Should Be 1
        $r.Emas.Count  | Should Be 1
    }
    It "la Red es DMC" { $r.Redes[0].Red | Should Be 'DMC' }
    It "primera corrida: TasaMmH es 0.0 (sin estado previo para diferenciar)" {
        $r.Redes[0].TasaMmH | Should Be 0.0
    }
    It "EstadoNuevo guarda el precip crudo para la proxima corrida" {
        $r.EstadoNuevo['390015'].precip | Should Be 0.7
    }
    It "la Ema tiene altitud y temperatura" {
        $r.Emas[0].Altitud | Should Be 15.0
        $r.Emas[0].TempC   | Should Not Be $null
    }
    It "AcumuladoHoy es el precip crudo del dia (no la tasa)" {
        $r.Redes[0].AcumuladoHoy | Should Be 0.7
        $r.Emas[0].AcumuladoHoy  | Should Be 0.7
    }
    It "primera corrida: la serie ya tiene el punto del 0 de medianoche sembrado" {
        # fixture con dato viejo (jul-08) + 0 de hoy 00:00 -> 1 punto (reset a 0)
        $r.Redes[0].TiemposSerie.Count | Should Be 1
    }
    It "EstadoNuevo guarda la historia con la muestra + el 0 de medianoche" {
        $r.EstadoNuevo['390015'].historia.Count | Should Be 2
    }

    # Segunda corrida con estado previo (incluye historia de la 1ra) -> calcula tasa Y serie
    $estadoPrev = @{ '390015' = @{ precip = 0.0; epoch = $r.Redes[0].Epoch - 3600
        historia = @(@{ epoch = $r.Redes[0].Epoch - 3600; precip = 0.0 }) } }
    $r2 = Get-EstacionesDmcDirecto -Codigos @('390015') -EstadoPrev $estadoPrev -ThrottleMs 0
    It "segunda corrida: calcula tasa mm/h contra el estado previo" {
        $r2.Redes[0].TasaMmH | Should Be 0.7
    }
    It "segunda corrida: la muestra previa (dias mas vieja que la ventana de 50h) se poda; queda el reset a 0 de hoy" {
        # fixture del 8-jul: la muestra previa sintetica queda fuera de la ventana de 50h ->
        # historia = [0 de medianoche de HOY, muestra vieja re-agregada]; la serie solo trae
        # el reset a 0 de hoy (0.7 - 0.7 del delta viejo ya no es calculable)
        $r2.Redes[0].TiemposSerie.Count | Should Be 1
        $r2.Redes[0].ValoresSerie[0] | Should Be 0.0
    }
    It "EstadoNuevo guarda historia con el 0 de medianoche + la muestra (la previa podada por vieja)" {
        $r2.EstadoNuevo['390015'].historia.Count | Should Be 2
    }
}

Describe "Get-AcumuladoHonesto" {
    # 12:00 UTC del 17-jul = 08:00 Chile del 17 (invierno UTC-4)
    $epochHoy  = 1784289600
    $epochAyer = 1784257200   # 23:00 Chile del 16
    It "con dato de la fuente, lo devuelve tal cual" {
        Get-AcumuladoHonesto -PrecipHoy 12.5 -PrevEntry $null -FechaChileHoy '2026-07-17' | Should Be 12.5
    }
    It "sin dato pero con estado previo DEL MISMO dia Chile: arrastra el ultimo acumulado" {
        $prev = @{ precip = 7.0; epoch = $epochHoy }
        Get-AcumuladoHonesto -PrecipHoy $null -PrevEntry $prev -FechaChileHoy '2026-07-17' | Should Be 7.0
    }
    It "sin dato y estado previo de AYER: null (s/d), no un 0 falso ni el total de ayer" {
        $prev = @{ precip = 44.0; epoch = $epochAyer }
        Get-AcumuladoHonesto -PrecipHoy $null -PrevEntry $prev -FechaChileHoy '2026-07-17' | Should Be $null
    }
    It "sin dato y sin estado previo: null" {
        Get-AcumuladoHonesto -PrecipHoy $null -PrevEntry $null -FechaChileHoy '2026-07-17' | Should Be $null
    }
    It "un 0.0 real de la fuente SI es 0 (s/p), no null" {
        Get-AcumuladoHonesto -PrecipHoy 0.0 -PrevEntry $null -FechaChileHoy '2026-07-17' | Should Be 0.0
    }
}

Describe "Get-EpochMedianocheChile" {
    It "medianoche Chile del 17-jul (invierno UTC-4) es 04:00 UTC" {
        Get-EpochMedianocheChile '2026-07-17' | Should Be 1784260800
    }
    It "medianoche Chile del 15-ene (verano UTC-3) es 03:00 UTC" {
        Get-EpochMedianocheChile '2026-01-15' | Should Be ([DateTimeOffset]::Parse('2026-01-15T03:00:00Z').ToUnixTimeSeconds())
    }
}

Describe "Add-MedianocheCero" {
    $mn = 1784260800   # 00:00 del 17-jul Chile
    It "historia vacia: agrega el 0 de medianoche" {
        $h = Add-MedianocheCero -Historia @() -MedianocheEpoch $mn
        $h.Count | Should Be 1
        $h[0].precip | Should Be 0.0
        $h[0].epoch | Should Be $mn
    }
    It "historia solo con muestras de ayer: agrega el 0" {
        $h = Add-MedianocheCero -Historia @(@{ epoch = $mn - 3600; precip = 44.0 }) -MedianocheEpoch $mn
        $h.Count | Should Be 2
    }
    It "historia con muestras de hoy pero SIN el 0 de las 00:00: igual lo siembra (ancla la base del dia)" {
        # bug real 2026-07-17: estacion que partio a mitad del dia con 94mm ya caidos
        # mostraba solo el delta entre corridas; el 0 de medianoche ancla el acumulado real
        $h = Add-MedianocheCero -Historia @(@{ epoch = $mn + 7200; precip = 5.0 }) -MedianocheEpoch $mn
        $h.Count | Should Be 2
        @($h | Where-Object { [int64]$_.epoch -eq $mn })[0].precip | Should Be 0.0
    }
    It "el propio 0 sembrado cuenta como muestra de hoy en la corrida siguiente" {
        $h1 = Add-MedianocheCero -Historia @() -MedianocheEpoch $mn
        $h2 = Add-MedianocheCero -Historia $h1 -MedianocheEpoch $mn
        $h2.Count | Should Be 1
    }
}
