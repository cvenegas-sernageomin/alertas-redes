# Fuente alternativa DIRECTA de la red RedMeteo (aficionados, redmeteo.cl), sin vismet.
# Motivo: se verifico 2026-07-17 (temporal real) que vismet devuelve 0.0 fijo para TODA
# la red RedMeteo (66 estaciones, 3168 valores no nulos en 48h, cero positivos) mientras
# redmeteo.cl mostraba lluvia real en las mismas zonas (48+ estaciones con lluvia diaria,
# hasta 46 mm en Valparaiso). Mismo patron del feed DGA/DMC roto en origen (ver arriba
# la seccion DMC directo en CLAUDE.md).
#
# Fuente: https://redmeteo.cl/liveupdate.php — el mismo JSON que alimenta el mapa publico
# de su home (no bloqueado por robots.txt; su API "formal" requiere solicitud por correo).
# Un solo request por ciclo (~75 KB), muy por debajo de su pedido de uso responsable;
# ademas servimos los datos desde nuestro propio KML, como ellos piden. Atribucion: la
# red aparece como "RedMeteo" en el visor.
#
# Campos del feed: id_estacion (RMCLxxxx), nombre, latitud/longitud, altitud, region,
# fecha_hora (ISO 8601 UTC), lluviadiaria (acumulado del dia, se resetea a medianoche),
# tasalluvia (OJO: viene siempre identico a lluviadiaria — NO es una tasa real, no usar),
# precipitacion (semantica ambigua, no usar). La tasa mm/h se estima diferenciando contra
# la corrida anterior, igual que DMC directo (Get-PrecipRateDirecto).
#
# Requiere DmcDirecto.ps1 cargado ANTES (reusa Get-PrecipRateDirecto, Add-MuestraHistoria,
# Get-SerieDesdeHistoria, Read-EstadoDmc, Save-EstadoDmc).

function Get-RedMeteoLive {
    param(
        [int]$TimeoutSeg = 60,
        [string]$UserAgent = 'alertas-redes/1.0 (uso institucional SERNAGEOMIN; geologia)'
    )
    # El servidor responde Content-Type text/html pero el cuerpo es JSON puro.
    $r = Invoke-WebRequest -Uri 'https://redmeteo.cl/liveupdate.php' -UseBasicParsing `
        -TimeoutSec $TimeoutSeg -UserAgent $UserAgent
    if ($r.Content -match '<!DOCTYPE|<html') { throw "redmeteo.cl devolvio HTML en vez de JSON" }
    # OJO PS 5.1 vs 7: en 5.1 `$s | ConvertFrom-Json` emite el array como UN solo objeto
    # (Count=1 con el array adentro); el ForEach-Object lo enumera y normaliza en ambas
    # versiones (verificado en vivo 2026-07-17: sin esto, en Windows PS 5.1 llegaba 1
    # "observacion" en vez de ~66).
    $datos = ConvertFrom-Json -InputObject $r.Content
    return ,@($datos | ForEach-Object { $_ })
}

# fecha_hora viene como ISO 8601 UTC ("2026-07-17T04:07:31Z").
function ConvertTo-EpochIsoUtc {
    param([string]$Texto)
    if (-not $Texto) { return $null }
    try {
        $dto = [DateTimeOffset]::Parse($Texto, [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)
        return [int64]$dto.ToUnixTimeSeconds()
    } catch { return $null }
}

# (Get-FechaChileDeEpoch vive en DmcDirecto.ps1, compartida por las 3 fuentes directas.)

# Convierte las observaciones del feed en estaciones con el esquema de Capa 1 (Redes).
# Solo Capa 1: son estaciones de aficionados sin altitud/temperatura confiables para
# isoterma (mismo criterio que INIA/FDF/ESO).
function Get-EstacionesRedMeteoDirecto {
    param(
        [array]$Observaciones,
        [hashtable]$EstadoPrev = @{},
        [string]$FechaChile,
        [long]$AhoraEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    )
    $redes = [System.Collections.Generic.List[object]]::new()
    $estadoNuevo = @{}
    $ok = 0; $descartadas = 0
    $vistos = @{}

    foreach ($o in $Observaciones) {
        $cod = [string]$o.id_estacion
        if (-not $cod -or $vistos.ContainsKey($cod)) { $descartadas++; continue }
        if ($null -eq $o.latitud -or $null -eq $o.longitud) { $descartadas++; continue }
        $vistos[$cod] = $true

        $ultimoEpoch = ConvertTo-EpochIsoUtc $o.fecha_hora

        # lluviadiaria se resetea a medianoche en la estacion: solo vale como "acumulado
        # de hoy" si el ultimo dato es del dia calendario Chile actual; si es mas viejo,
        # seria el total de OTRO dia (hay estaciones muertas hace meses en el feed).
        $lluvia = $null
        if ($null -ne $o.lluviadiaria -and $null -ne $ultimoEpoch -and
            (Get-FechaChileDeEpoch $ultimoEpoch) -eq $FechaChile) {
            $lluvia = [double]$o.lluviadiaria
        }
        # null NO es 0: una estacion muerta/vieja queda "s/d" (y gris por inactiva), no
        # con un "0 mm" falso (misma regla que Get-AcumuladoHonesto en DMC directo)
        $acumuladoHoy = $lluvia

        $prevEntry = $EstadoPrev[$cod]
        $tasa = $null
        if ($prevEntry -and $null -ne $lluvia -and $null -ne $ultimoEpoch) {
            $tasa = Get-PrecipRateDirecto -PrecipActual $lluvia -EpochActual $ultimoEpoch `
                -PrecipPrev $prevEntry.precip -EpochPrev $prevEntry.epoch
        }
        $tasaFinal = if ($null -ne $tasa) { $tasa } else { 0.0 }

        $historiaPrev  = if ($prevEntry -and $prevEntry.historia) { $prevEntry.historia } else { @() }
        $historiaNueva = $historiaPrev
        if ($null -ne $lluvia -and $null -ne $ultimoEpoch) {
            $historiaNueva = Add-MuestraHistoria -Historia $historiaPrev -Epoch $ultimoEpoch -Precip $lluvia -AhoraEpoch $AhoraEpoch
        }
        $serie = Get-SerieDesdeHistoria $historiaNueva

        $redes.Add([PSCustomObject]@{
            Id = $null; Nombre = $o.nombre; Codigo = $cod
            Lat = [double]$o.latitud; Lon = [double]$o.longitud
            TasaMmH = $tasaFinal
            Epoch = $(if ($null -ne $ultimoEpoch) { $ultimoEpoch } else { 0 })
            UltimoDatoEpoch = $ultimoEpoch
            OrgConfirmada = 'RedMeteo directo'; Red = 'RedMeteo'
            AcumuladoHoy = $acumuladoHoy
            ValoresSerie = $serie.Valores; TiemposSerie = $serie.Tiempos
        })

        if ($null -ne $lluvia -and $null -ne $ultimoEpoch) {
            $estadoNuevo[$cod] = @{ precip = $lluvia; epoch = $ultimoEpoch; historia = $historiaNueva }
        } elseif ($prevEntry) {
            $estadoNuevo[$cod] = $prevEntry
        }
        $ok++
    }

    return [PSCustomObject]@{
        Redes = $redes.ToArray(); EstadoNuevo = $estadoNuevo
        Ok = $ok; Descartadas = $descartadas
    }
}
