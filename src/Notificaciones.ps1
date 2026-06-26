# Requiere que AlertasKml.ps1 ya este cargado (Get-ColorRedes, Get-ColorEmas)

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
            $lineas += "  • <b>$($e.Nombre)</b> [$($e.Red)]: $($e.TasaMmH) mm/h"
        }
        if ($rojasRedes.Count -gt 5) { $lineas += "  … y $($rojasRedes.Count - 5) más" }
    }
    if ($amarillasRedes.Count -gt 0) {
        $lineas += "🟡 <b>Redes: $($amarillasRedes.Count) est. con precip ≥ 5 mm/h</b>"
        $top = $amarillasRedes | Sort-Object TasaMmH -Descending | Select-Object -First 3
        foreach ($e in $top) {
            $lineas += "  • $($e.Nombre) [$($e.Red)]: $($e.TasaMmH) mm/h"
        }
        if ($amarillasRedes.Count -gt 3) { $lineas += "  … y $($amarillasRedes.Count - 3) más" }
    }

    # --- EMAs DMC (precip + isoterma) ---
    if ($rojasEmas.Count -gt 0) {
        $lineas += "🔴 <b>EMAs: $($rojasEmas.Count) est. — precip alta + isoterma 0°C elevada</b>"
        foreach ($e in $rojasEmas | Sort-Object TasaMmH -Descending) {
            $isoStr = if ($null -ne $e.Isoterma) { "$($e.Isoterma) m" } else { 'sin dato' }
            $lineas += "  • <b>$($e.Nombre)</b>: $($e.TasaMmH) mm/h | iso $isoStr | alt $($e.Altitud) m"
        }
    }
    if ($amarillasEmas.Count -gt 0) {
        $lineas += "🟡 <b>EMAs: $($amarillasEmas.Count) est. — alerta moderada</b>"
        foreach ($e in $amarillasEmas | Sort-Object TasaMmH -Descending) {
            $isoStr = if ($null -ne $e.Isoterma) { "$($e.Isoterma) m" } else { 'sin dato' }
            $lineas += "  • $($e.Nombre): $($e.TasaMmH) mm/h | iso $isoStr"
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
            $lineas += "  • $($v.Lat)°S $($v.Lon)°W [$($v.Nombre)]: máx $pMax mm | iso $iStr | $($v.NModelos)/3 modelos"
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
            $lineas += "  • $($v.Lat)°S $($v.Lon)°W [$($v.Nombre)]: máx $pMax mm | $($v.NModelos)/3 modelos"
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
