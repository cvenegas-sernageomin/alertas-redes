# Requiere que AlertasKml.ps1 ya este cargado (Get-ColorRedes, Get-ColorEmas)

function Build-ResumenAlertas([array]$redes, [array]$emas, [array]$allVentanas) {
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

    $hayAlertas = ($rojasRedes.Count + $amarillasRedes.Count + $rojasEmas.Count +
                   $amarillasEmas.Count + $rojoPron.Count + $amarilloPron.Count) -gt 0
    if (-not $hayAlertas) { return $null }

    $nivel = if ($rojasRedes.Count -gt 0 -or $rojasEmas.Count -gt 0 -or $rojoPron.Count -gt 0) {
        '🔴 ALERTA ROJA activa'
    } else {
        '🟡 Alerta moderada'
    }

    $lineas = @("<b>$nivel — $ts</b>`n")

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
