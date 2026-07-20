# Requiere que AlertasKml.ps1 ya este cargado (Get-ColorRedes, Get-ColorEmas)

# --- Pueblos/ciudades grandes de Chile (para ubicar la estacion mas cercana) ---
$script:PueblosCL = @(
    @{N='Arica';La=-18.478;Lo=-70.321},           @{N='Iquique';La=-20.214;Lo=-70.152},
    @{N='Alto Hospicio';La=-20.250;Lo=-70.100},    @{N='Pozo Almonte';La=-20.258;Lo=-69.785},
    @{N='Calama';La=-22.456;Lo=-68.924},           @{N='Antofagasta';La=-23.650;Lo=-70.400},
    @{N='Tocopilla';La=-22.092;Lo=-70.197},        @{N='Mejillones';La=-23.100;Lo=-70.450},
    @{N='Taltal';La=-25.410;Lo=-70.480},           @{N='Copiapo';La=-27.366;Lo=-70.332},
    @{N='Vallenar';La=-28.576;Lo=-70.759},         @{N='Caldera';La=-27.070;Lo=-70.820},
    @{N='Chanaral';La=-26.348;Lo=-70.620},         @{N='La Serena';La=-29.907;Lo=-71.252},
    @{N='Coquimbo';La=-29.953;Lo=-71.343},         @{N='Ovalle';La=-30.601;Lo=-71.199},
    @{N='Illapel';La=-31.633;Lo=-71.168},          @{N='Vicuna';La=-30.034;Lo=-70.713},
    @{N='Los Vilos';La=-31.910;Lo=-71.510},        @{N='Salamanca';La=-31.780;Lo=-70.960},
    @{N='La Ligua';La=-32.450;Lo=-71.230},         @{N='San Felipe';La=-32.750;Lo=-70.720},
    @{N='Los Andes';La=-32.834;Lo=-70.598},        @{N='Quillota';La=-32.880;Lo=-71.249},
    @{N='Valparaiso';La=-33.046;Lo=-71.620},       @{N='Vina del Mar';La=-33.024;Lo=-71.552},
    @{N='Quilpue';La=-33.047;Lo=-71.442},          @{N='Villa Alemana';La=-33.043;Lo=-71.373},
    @{N='San Antonio';La=-33.594;Lo=-71.606},      @{N='Casablanca';La=-33.320;Lo=-71.410},
    @{N='Santiago';La=-33.450;Lo=-70.667},         @{N='Puente Alto';La=-33.611;Lo=-70.576},
    @{N='Maipu';La=-33.510;Lo=-70.760},            @{N='Melipilla';La=-33.690;Lo=-71.215},
    @{N='Talagante';La=-33.665;Lo=-70.928},        @{N='Buin';La=-33.730;Lo=-70.740},
    @{N='Colina';La=-33.200;Lo=-70.670},           @{N='Rancagua';La=-34.170;Lo=-70.740},
    @{N='San Fernando';La=-34.585;Lo=-70.989},     @{N='Rengo';La=-34.410;Lo=-70.860},
    @{N='Santa Cruz';La=-34.640;Lo=-71.360},       @{N='Pichilemu';La=-34.390;Lo=-72.000},
    @{N='Curico';La=-34.983;Lo=-71.239},           @{N='Talca';La=-35.426;Lo=-71.665},
    @{N='Linares';La=-35.846;Lo=-71.593},          @{N='Constitucion';La=-35.330;Lo=-72.410},
    @{N='Cauquenes';La=-35.970;Lo=-72.320},        @{N='Parral';La=-36.140;Lo=-71.830},
    @{N='Molina';La=-35.110;Lo=-71.280},           @{N='Chillan';La=-36.606;Lo=-72.103},
    @{N='San Carlos';La=-36.420;Lo=-71.960},       @{N='Bulnes';La=-36.740;Lo=-72.300},
    @{N='Concepcion';La=-36.827;Lo=-73.050},       @{N='Talcahuano';La=-36.720;Lo=-73.120},
    @{N='Coronel';La=-37.030;Lo=-73.140},          @{N='Lota';La=-37.090;Lo=-73.160},
    @{N='Los Angeles';La=-37.469;Lo=-72.354},      @{N='Canete';La=-37.800;Lo=-73.390},
    @{N='Lebu';La=-37.610;Lo=-73.650},             @{N='Mulchen';La=-37.720;Lo=-72.240},
    @{N='Nacimiento';La=-37.500;Lo=-72.670},       @{N='Angol';La=-37.795;Lo=-72.716},
    @{N='Victoria';La=-38.230;Lo=-72.330},         @{N='Traiguen';La=-38.250;Lo=-72.670},
    @{N='Collipulli';La=-37.950;Lo=-72.430},       @{N='Temuco';La=-38.736;Lo=-72.590},
    @{N='Padre Las Casas';La=-38.770;Lo=-72.600},  @{N='Lautaro';La=-38.530;Lo=-72.440},
    @{N='Nueva Imperial';La=-38.740;Lo=-72.950},   @{N='Villarrica';La=-39.286;Lo=-72.228},
    @{N='Pucon';La=-39.270;Lo=-71.980},            @{N='Loncoche';La=-39.370;Lo=-72.630},
    @{N='Pitrufquen';La=-38.980;Lo=-72.640},       @{N='Valdivia';La=-39.814;Lo=-73.245},
    @{N='La Union';La=-40.290;Lo=-73.080},         @{N='Rio Bueno';La=-40.330;Lo=-72.950},
    @{N='Paillaco';La=-40.070;Lo=-72.870},         @{N='Osorno';La=-40.573;Lo=-73.133},
    @{N='Rio Negro';La=-40.790;Lo=-73.220},        @{N='Purranque';La=-40.910;Lo=-73.160},
    @{N='Puerto Montt';La=-41.469;Lo=-72.941},     @{N='Puerto Varas';La=-41.320;Lo=-72.990},
    @{N='Llanquihue';La=-41.250;Lo=-73.010},       @{N='Frutillar';La=-41.130;Lo=-73.050},
    @{N='Calbuco';La=-41.770;Lo=-73.130},          @{N='Ancud';La=-41.870;Lo=-73.830},
    @{N='Castro';La=-42.480;Lo=-73.760},           @{N='Quellon';La=-43.120;Lo=-73.620},
    @{N='Chaiten';La=-42.920;Lo=-72.710},          @{N='Coyhaique';La=-45.572;Lo=-72.068},
    @{N='Puerto Aysen';La=-45.400;Lo=-72.690},     @{N='Cochrane';La=-47.250;Lo=-72.570},
    @{N='Punta Arenas';La=-53.163;Lo=-70.917},     @{N='Puerto Natales';La=-51.730;Lo=-72.510},
    @{N='Porvenir';La=-53.300;Lo=-70.370},
    @{N='Hanga Roa';La=-27.147;Lo=-109.432},        @{N='San Juan Bautista';La=-33.638;Lo=-78.828}
)

function Get-PuebloCercano([double]$lat, [double]$lon) {
    $best = $null; $bestKm = [double]::MaxValue
    $rad = [math]::PI / 180.0
    foreach ($p in $script:PueblosCL) {
        $dLat = ($p.La - $lat) * $rad
        $dLon = ($p.Lo - $lon) * $rad
        $a = [math]::Sin($dLat / 2) * [math]::Sin($dLat / 2) +
             [math]::Cos($lat * $rad) * [math]::Cos($p.La * $rad) *
             [math]::Sin($dLon / 2) * [math]::Sin($dLon / 2)
        $km = 6371.0 * 2 * [math]::Atan2([math]::Sqrt($a), [math]::Sqrt(1 - $a))
        if ($km -lt $bestKm) { $bestKm = $km; $best = $p }
    }
    if ($null -eq $best) { return $null }
    return [pscustomobject]@{ Nombre = $best.N; Km = [int][math]::Round($bestKm) }
}

# Pueblo/localidad REAL mas cercano por geocodificacion inversa (Nominatim/OSM).
# Devuelve el nombre del lugar mas fino disponible, o $null si falla.
$script:GeoCache = @{}
function Get-LugarNominatim([double]$lat, [double]$lon) {
    $key = '{0:F3},{1:F3}' -f $lat, $lon
    if ($script:GeoCache.ContainsKey($key)) { return $script:GeoCache[$key] }
    $lugar = $null
    try {
        $url = "https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=jsonv2&zoom=14&addressdetails=1&accept-language=es"
        $headers = @{ 'User-Agent' = 'alertas-redes-sernageomin/1.0 (notificador precipitacion)' }
        $r = Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 15
        $a = $r.address
        foreach ($campo in 'village','hamlet','town','suburb','neighbourhood','city_district','locality','municipality','city','county') {
            if ($a.$campo) { $lugar = [string]$a.$campo; break }
        }
        Start-Sleep -Milliseconds 1100   # politica Nominatim: <= 1 req/s
    } catch {
        $lugar = $null
    }
    $script:GeoCache[$key] = $lugar
    return $lugar
}

# Hora local actual del lugar de la alerta. Isla de Pascua (lon < -100) usa su propia
# zona horaria; el resto del pais, hora continental. El horario de verano se aplica solo.
function Get-HoraLocal([double]$lon) {
    $tzId = if ($lon -lt -100) { 'Easter Island Standard Time' } else { 'Pacific SA Standard Time' }
    try {
        $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($tzId)
        $local = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz)
        return $local.ToString('HH:mm')
    } catch {
        return $null
    }
}

# Sufijo " — <Pueblo cercano> — cerca de <Ciudad grande> (~N km) · 🕒 HH:mm (local)"
function Get-CercaDe($e) {
    if ($null -eq $e.Lat -or $null -eq $e.Lon) { return '' }
    $lat = [double]$e.Lat; $lon = [double]$e.Lon
    $ciudad = Get-PuebloCercano $lat $lon
    $pueblo = Get-LugarNominatim $lat $lon
    $partes = @()
    if ($pueblo) { $partes += $pueblo }
    if ($null -ne $ciudad) {
        # no repetir si el pueblo ya es la misma ciudad grande
        $mismo = $pueblo -and (($pueblo -replace '\s', '').ToLower() -eq ($ciudad.Nombre -replace '\s', '').ToLower())
        if (-not $mismo) { $partes += "cerca de $($ciudad.Nombre) (~$($ciudad.Km) km)" }
    }
    $sufijo = ''
    if ($partes.Count -gt 0) { $sufijo = ' — ' + ($partes -join ' — ') }
    $hora = Get-HoraLocal $lon
    if ($hora) { $sufijo += " · 🕒 $hora hrs (local)" }
    return $sufijo
}

function Get-SismosFuertes([array]$sismos, [double]$minMag = 6.0, [int]$ventanaMin = 90) {
    if ($null -eq $sismos -or $sismos.Count -eq 0) { return @() }
    $ahora = [datetime]::UtcNow
    $candidatos = @($sismos | Where-Object {
        $_.Mag -ge $minMag -and $null -ne $_.FechaUtc -and
        ($ahora - $_.FechaUtc).TotalMinutes -le $ventanaMin -and
        ($ahora - $_.FechaUtc).TotalMinutes -ge -10
    })
    # Dedup: mismo evento reportado por CSN y USGS (proximidad espacio-temporal)
    $unicos = [System.Collections.ArrayList]::new()
    foreach ($s in ($candidatos | Sort-Object FechaUtc -Descending)) {
        $dup = $false
        foreach ($u in $unicos) {
            if ([math]::Abs($s.Lat - $u.Lat) -le 0.5 -and
                [math]::Abs($s.Lon - $u.Lon) -le 0.5 -and
                [math]::Abs(($s.FechaUtc - $u.FechaUtc).TotalMinutes) -le 5) {
                $dup = $true; break
            }
        }
        if (-not $dup) { [void]$unicos.Add($s) }
    }
    return $unicos.ToArray()
}

function Build-ResumenAlertas([array]$redes, [array]$emas, [array]$allVentanas, [array]$sismos = @()) {
    $ts = (Get-Date).ToUniversalTime().ToString('HH:mm') + ' UTC — ' + (Get-Date).ToLocalTime().ToString('dd-MMM-yyyy')

    # --- Condiciones actuales ---
    $rojasRedes     = @($redes | Where-Object { (Get-ColorRedes $_.TasaMmH) -eq 'rojo' })
    $amarillasRedes = @($redes | Where-Object { (Get-ColorRedes $_.TasaMmH) -eq 'amarillo' })
    $rojasEmas      = @($emas  | Where-Object { (Get-ColorEmas $_.TasaMmH $_.Isoterma) -eq 'rojo' })
    $amarillasEmas  = @($emas  | Where-Object { (Get-ColorEmas $_.TasaMmH $_.Isoterma) -eq 'amarillo' })

    # --- Pronostico ---
    if ($null -eq $allVentanas) { $allVentanas = @() }
    $rojoPron      = @($allVentanas | Where-Object { $_.ColorFinal -eq 'rojo' })
    $amarilloPron  = @($allVentanas | Where-Object { $_.ColorFinal -eq 'amarillo' })

    # --- Sismos fuertes (M >= 6, recientes, deduplicados) ---
    $sismosFuertes = @(Get-SismosFuertes $sismos)

    $hayAlertas = ($rojasRedes.Count + $amarillasRedes.Count + $rojasEmas.Count +
                   $amarillasEmas.Count + $rojoPron.Count + $amarilloPron.Count +
                   $sismosFuertes.Count) -gt 0
    if (-not $hayAlertas) { return $null }

    $hayRojo = $rojasRedes.Count -gt 0 -or $rojasEmas.Count -gt 0 -or $rojoPron.Count -gt 0
    $nivel = if ($sismosFuertes.Count -gt 0) {
        '🌋 SISMO FUERTE (M&ge;6)'
    } elseif ($hayRojo) {
        '🔴 ALERTA ROJA activa'
    } else {
        '🟡 Alerta moderada'
    }

    $lineas = @("<b>$nivel — $ts</b>`n")

    # --- Sismos: primero por urgencia ---
    if ($sismosFuertes.Count -gt 0) {
        $lineas += "🌋 <b>Sismo(s) M&ge;6 en los últimos 90 min: $($sismosFuertes.Count)</b>"
        foreach ($s in $sismosFuertes) {
            $prof  = if ($null -ne $s.Prof) { "$($s.Prof) km" } else { 's/d' }
            $lugar = if ($s.Lugar) { " — $($s.Lugar)" } else { '' }
            $lineas += "  • <b>M $($s.Mag)</b> | prof $prof | $($s.Lat)°, $($s.Lon)°$lugar [$($s.Fuente)] $($s.Fecha)"
        }
        $lineas += ''
    }

    # --- Redes (precipitación sola) ---
    if ($rojasRedes.Count -gt 0) {
        $lineas += "🔴 <b>Redes: $($rojasRedes.Count) est. con precip ≥ 10 mm/h</b>"
        $top = $rojasRedes | Sort-Object TasaMmH -Descending | Select-Object -First 5
        foreach ($e in $top) {
            $lineas += "  • <b>$($e.Nombre)</b> [$($e.Red)]: $($e.TasaMmH) mm/h$(Get-CercaDe $e)"
        }
        if ($rojasRedes.Count -gt 5) { $lineas += "  … y $($rojasRedes.Count - 5) más" }
    }
    if ($amarillasRedes.Count -gt 0) {
        $lineas += "🟡 <b>Redes: $($amarillasRedes.Count) est. con precip ≥ 5 mm/h</b>"
        $top = $amarillasRedes | Sort-Object TasaMmH -Descending | Select-Object -First 3
        foreach ($e in $top) {
            $lineas += "  • $($e.Nombre) [$($e.Red)]: $($e.TasaMmH) mm/h$(Get-CercaDe $e)"
        }
        if ($amarillasRedes.Count -gt 3) { $lineas += "  … y $($amarillasRedes.Count - 3) más" }
    }

    # --- EMAs DMC (precip + isoterma) ---
    if ($rojasEmas.Count -gt 0) {
        $lineas += "🔴 <b>EMAs: $($rojasEmas.Count) est. — precip alta + isoterma 0°C elevada</b>"
        foreach ($e in $rojasEmas | Sort-Object TasaMmH -Descending) {
            $isoStr = if ($null -ne $e.Isoterma) { "$($e.Isoterma) m" } else { 'sin dato' }
            $lineas += "  • <b>$($e.Nombre)</b>: $($e.TasaMmH) mm/h | iso $isoStr | alt $($e.Altitud) m$(Get-CercaDe $e)"
        }
    }
    if ($amarillasEmas.Count -gt 0) {
        $lineas += "🟡 <b>EMAs: $($amarillasEmas.Count) est. — alerta moderada</b>"
        foreach ($e in $amarillasEmas | Sort-Object TasaMmH -Descending) {
            $isoStr = if ($null -ne $e.Isoterma) { "$($e.Isoterma) m" } else { 'sin dato' }
            $lineas += "  • $($e.Nombre): $($e.TasaMmH) mm/h | iso $isoStr$(Get-CercaDe $e)"
        }
    }

    # --- Pronostico (solo resumen + top peores) ---
    if ($rojoPron.Count -gt 0) {
        $lineas += "🔴 <b>Pronóstico: $($rojoPron.Count) celdas con alerta roja (≥20 mm + iso ≥3000 m)</b>"
        $top = $rojoPron | Sort-Object {
            [math]::Max([double]$_.PrecipEcmwf, [math]::Max([double]$_.PrecipGfs, [double]$_.PrecipIcon))
        } -Descending | Select-Object -First 4
        foreach ($v in $top) {
            $pMax = [math]::Max([double]$v.PrecipEcmwf, [math]::Max([double]$v.PrecipGfs, [double]$v.PrecipIcon))
            $iMin = @($v.IsoEcmwf, $v.IsoGfs, $v.IsoIcon) | Where-Object { $null -ne $_ } | Measure-Object -Minimum | Select-Object -ExpandProperty Minimum
            $iStr = if ($null -ne $iMin) { "$iMin m" } else { '-' }
            $lineas += "  • $($v.Lat)°S $($v.Lon)°W [$($v.Nombre)]: máx $pMax mm | iso $iStr | $($v.NModelos)/3 modelos$(Get-CercaDe $v)"
        }
        if ($rojoPron.Count -gt 4) { $lineas += "  … y $($rojoPron.Count - 4) celdas más" }
    }
    if ($amarilloPron.Count -gt 0) {
        $lineas += "🟡 <b>Pronóstico: $($amarilloPron.Count) celdas amarillo (≥5 mm + iso ≥2500 m)</b>"
        $top = $amarilloPron | Sort-Object {
            [math]::Max([double]$_.PrecipEcmwf, [math]::Max([double]$_.PrecipGfs, [double]$_.PrecipIcon))
        } -Descending | Select-Object -First 2
        foreach ($v in $top) {
            $pMax = [math]::Max([double]$v.PrecipEcmwf, [math]::Max([double]$v.PrecipGfs, [double]$v.PrecipIcon))
            $lineas += "  • $($v.Lat)°S $($v.Lon)°W [$($v.Nombre)]: máx $pMax mm | $($v.NModelos)/3 modelos$(Get-CercaDe $v)"
        }
    }

    return $lineas -join "`n"
}

function Send-TelegramMensaje([string]$token, [string]$chatId, [string]$texto) {
    $url  = "https://api.telegram.org/bot$token/sendMessage"
    $body = @{
        chat_id    = $chatId
        text       = $texto
        parse_mode = 'HTML'
    } | ConvertTo-Json -Compress
    try {
        Invoke-WebRequest -Uri $url -Method Post -Body $body `
            -ContentType 'application/json; charset=utf-8' -UseBasicParsing | Out-Null
        return $true
    } catch {
        Write-Warning "Telegram error: $_"
        return $false
    }
}

# --- Sistema de consolidacion diaria de alertas ---

function Read-AlertasDiarias([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    try {
        $json = Get-Content $path -Raw | ConvertFrom-Json
        return $json
    } catch {
        return $null
    }
}

function Save-AlertasDiarias([string]$path, $estado) {
    $json = $estado | ConvertTo-Json -Depth 10 -Compress
    [System.IO.File]::WriteAllText($path, $json, [System.Text.Encoding]::UTF8)
}

# Actualiza el estado diario con los datos actuales, mantiene maximos del dia
function Update-EstadoAlertas($estadoAnterior, [array]$redes, [array]$emas, [array]$ventanas) {
    $hoy = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    $ahora = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    # Si es un dia nuevo, resetear el estado
    if ($null -eq $estadoAnterior -or $estadoAnterior.Dia -ne $hoy) {
        $estadoAnterior = @{
            Dia = $hoy
            EpochCreacion = $ahora
            MaximosPorId = @{}
            RegionalizadasRojas = @()
            RegionalizadasAmarillas = @()
            EmasRojas = @()
            EmasAmarillas = @()
            VentanasRojas = @()
            VentanasAmarillas = @()
            SismosFuertes = @()
            UltimoEnvio = 0
        }
    }

    # Actualizar maximos de redes (capa 1)
    foreach ($e in $redes) {
        $id = "$($e.Nombre)_$($e.Red)"
        $color = Get-ColorRedesFinal $e
        if ($color -eq 'rojo') {
            if (-not $estadoAnterior.MaximosPorId.ContainsKey($id)) {
                $estadoAnterior.MaximosPorId[$id] = @{ Nombre = $e.Nombre; Red = $e.Red; Lat = $e.Lat; Lon = $e.Lon; MaxMmH = 0 }
            }
            if ([double]$e.TasaMmH -gt $estadoAnterior.MaximosPorId[$id].MaxMmH) {
                $estadoAnterior.MaximosPorId[$id].MaxMmH = [double]$e.TasaMmH
            }
        }
    }

    # Recolectar maximos rojas/amarillas del dia (sin duplicar)
    $rojasHoy = @($redes | Where-Object { (Get-ColorRedesFinal $_) -eq 'rojo' })
    $amarillasHoy = @($redes | Where-Object { (Get-ColorRedesFinal $_) -eq 'amarillo' })

    # EMAs rojas/amarillas
    $emasRojasHoy = @($emas | Where-Object { (Get-ColorEmas $_.TasaMmH $_.Isoterma) -eq 'rojo' })
    $emasAmarillasHoy = @($emas | Where-Object { (Get-ColorEmas $_.TasaMmH $_.Isoterma) -eq 'amarillo' })

    # Ventanas pronóstico
    $ventanasRojasHoy = @($ventanas | Where-Object { $_.ColorFinal -eq 'rojo' })
    $ventanasAmarillasHoy = @($ventanas | Where-Object { $_.ColorFinal -eq 'amarillo' })

    # Guardar resumen actual para el consolidado
    $estadoAnterior.RegionalizadasRojas = @($rojasHoy | Select-Object Nombre, Red, TasaMmH, Lat, Lon)
    $estadoAnterior.RegionalizadasAmarillas = @($amarillasHoy | Select-Object Nombre, Red, TasaMmH, Lat, Lon)
    $estadoAnterior.EmasRojas = @($emasRojasHoy | Select-Object Nombre, TasaMmH, Isoterma, Altitud, Lat, Lon)
    $estadoAnterior.EmasAmarillas = @($emasAmarillasHoy | Select-Object Nombre, TasaMmH, Isoterma, Lat, Lon)
    $estadoAnterior.VentanasRojas = @($ventanasRojasHoy | Select-Object Nombre, Lat, Lon, PrecipEcmwf, PrecipGfs, PrecipIcon, NModelos)
    $estadoAnterior.VentanasAmarillas = @($ventanasAmarillasHoy | Select-Object Nombre, Lat, Lon, PrecipEcmwf, PrecipGfs, PrecipIcon, NModelos)

    return $estadoAnterior
}

# Detecta si es hora de enviar el consolidado diario (20:00 UTC = 16:00 Chile)
function Test-EsHoraEnvio() {
    $horaUtc = (Get-Date).ToUniversalTime().Hour
    return $horaUtc -eq 20
}

# Construye resumen consolidado del dia a partir del estado acumulado
function Build-ResumenAlertas-Diario($estado) {
    if ($null -eq $estado -or $estado.RegionalizadasRojas.Count -eq 0 -and
        $estado.RegionalizadasAmarillas.Count -eq 0 -and
        $estado.EmasRojas.Count -eq 0 -and
        $estado.EmasAmarillas.Count -eq 0 -and
        $estado.VentanasRojas.Count -eq 0 -and
        $estado.VentanasAmarillas.Count -eq 0 -and
        $estado.SismosFuertes.Count -eq 0) {
        return $null
    }

    $ts = "$($estado.Dia) (resumen del día)"
    $lineas = @("<b>📋 Resumen diario de alertas — $ts</b>`n")

    # Sismos fuertes
    if ($estado.SismosFuertes.Count -gt 0) {
        $lineas += "🌋 <b>Sismo(s) M≥6 registrado(s):</b>"
        foreach ($s in $estado.SismosFuertes) {
            $prof = if ($null -ne $s.Prof) { "$($s.Prof) km" } else { 's/d' }
            $lineas += "  • <b>M $($s.Mag)</b> | prof $prof | $($s.Lat)°, $($s.Lon)°"
        }
        $lineas += ''
    }

    # Redes rojas
    if ($estado.RegionalizadasRojas.Count -gt 0) {
        $lineas += "🔴 <b>Redes: $($estado.RegionalizadasRojas.Count) estaciones con precip ≥10 mm/h</b>"
        foreach ($e in ($estado.RegionalizadasRojas | Sort-Object TasaMmH -Descending)) {
            $lineas += "  • <b>$($e.Nombre)</b> [$($e.Red)]: máx $([math]::Round($e.TasaMmH, 1)) mm/h"
        }
    }

    # Redes amarillas
    if ($estado.RegionalizadasAmarillas.Count -gt 0) {
        $lineas += "🟡 <b>Redes: $($estado.RegionalizadasAmarillas.Count) estaciones con precip ≥5 mm/h</b>"
        $top = $estado.RegionalizadasAmarillas | Sort-Object TasaMmH -Descending | Select-Object -First 5
        foreach ($e in $top) {
            $lineas += "  • $($e.Nombre) [$($e.Red)]: máx $([math]::Round($e.TasaMmH, 1)) mm/h"
        }
        if ($estado.RegionalizadasAmarillas.Count -gt 5) {
            $lineas += "  … y $($estado.RegionalizadasAmarillas.Count - 5) más"
        }
    }

    # EMAs rojas
    if ($estado.EmasRojas.Count -gt 0) {
        $lineas += "🔴 <b>EMAs: $($estado.EmasRojas.Count) estaciones — precip alta + isoterma elevada</b>"
        foreach ($e in ($estado.EmasRojas | Sort-Object TasaMmH -Descending)) {
            $isoStr = if ($null -ne $e.Isoterma) { "$($e.Isoterma) m" } else { 's/d' }
            $lineas += "  • <b>$($e.Nombre)</b>: máx $([math]::Round($e.TasaMmH, 1)) mm/h | iso $isoStr | alt $($e.Altitud) m"
        }
    }

    # EMAs amarillas
    if ($estado.EmasAmarillas.Count -gt 0) {
        $lineas += "🟡 <b>EMAs: $($estado.EmasAmarillas.Count) estaciones — alerta moderada</b>"
        $top = $estado.EmasAmarillas | Sort-Object TasaMmH -Descending | Select-Object -First 3
        foreach ($e in $top) {
            $isoStr = if ($null -ne $e.Isoterma) { "$($e.Isoterma) m" } else { 's/d' }
            $lineas += "  • $($e.Nombre): máx $([math]::Round($e.TasaMmH, 1)) mm/h | iso $isoStr"
        }
        if ($estado.EmasAmarillas.Count -gt 3) {
            $lineas += "  … y $($estado.EmasAmarillas.Count - 3) más"
        }
    }

    # Pronóstico rojo
    if ($estado.VentanasRojas.Count -gt 0) {
        $lineas += "🔴 <b>Pronóstico: $($estado.VentanasRojas.Count) celdas alerta roja</b>"
        $top = $estado.VentanasRojas | Sort-Object {
            [math]::Max([double]$_.PrecipEcmwf, [math]::Max([double]$_.PrecipGfs, [double]$_.PrecipIcon))
        } -Descending | Select-Object -First 3
        foreach ($v in $top) {
            $pMax = [math]::Max([double]$v.PrecipEcmwf, [math]::Max([double]$v.PrecipGfs, [double]$v.PrecipIcon))
            $lineas += "  • $($v.Lat)°S $($v.Lon)°W [$($v.Nombre)]: máx $([math]::Round($pMax, 1)) mm"
        }
        if ($estado.VentanasRojas.Count -gt 3) {
            $lineas += "  … y $($estado.VentanasRojas.Count - 3) celdas más"
        }
    }

    # Pronóstico amarillo
    if ($estado.VentanasAmarillas.Count -gt 0) {
        $lineas += "🟡 <b>Pronóstico: $($estado.VentanasAmarillas.Count) celdas amarillo</b>"
        $top = $estado.VentanasAmarillas | Sort-Object {
            [math]::Max([double]$_.PrecipEcmwf, [math]::Max([double]$_.PrecipGfs, [double]$_.PrecipIcon))
        } -Descending | Select-Object -First 2
        foreach ($v in $top) {
            $pMax = [math]::Max([double]$v.PrecipEcmwf, [math]::Max([double]$v.PrecipGfs, [double]$v.PrecipIcon))
            $lineas += "  • $($v.Lat)°S $($v.Lon)°W [$($v.Nombre)]: máx $([math]::Round($pMax, 1)) mm"
        }
    }

    return $lineas -join "`n"
}

# Alerta critica inmediata para sismos M >= 6
function Build-AlertaSismo([array]$sismosFuertes) {
    if ($null -eq $sismosFuertes -or $sismosFuertes.Count -eq 0) { return $null }

    $ts = (Get-Date).ToUniversalTime().ToString('HH:mm UTC')
    $lineas = @("<b>🌋 ALERTA CRITICA: Sismo(s) M≥6 detectado(s) — $ts</b>`n")
    foreach ($s in $sismosFuertes) {
        $prof = if ($null -ne $s.Prof) { "$($s.Prof) km" } else { 's/d' }
        $lugar = if ($s.Lugar) { " — $($s.Lugar)" } else { '' }
        $lineas += "  <b>M $($s.Mag)</b> | prof $prof | $($s.Lat)°, $($s.Lon)°$lugar [$($s.Fuente)] $($s.Fecha)"
    }
    return $lineas -join "`n"
}
