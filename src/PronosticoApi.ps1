function Get-GrillaChile {
    $puntos = @()
    $lat = -17.5
    while ($lat -ge -56.0) {
        $lonMin = if ($lat -gt -30) { -75.0 } elseif ($lat -gt -43) { -76.0 } else { -77.0 }
        $lonMax = if ($lat -gt -30) { -67.0 } else { -68.0 }
        $lon = $lonMin
        while ($lon -le $lonMax) {
            $puntos += [PSCustomObject]@{ Lat = $lat; Lon = $lon }
            $lon = [math]::Round($lon + 1.0, 1)
        }
        $lat = [math]::Round($lat - 1.0, 1)
    }
    return $puntos
}

function Parse-OpenMeteoPoint($obj) {
    $h = $obj.hourly
    return [PSCustomObject]@{
        Lat               = [double]$obj.latitude
        Lon               = [double]$obj.longitude
        HourlyPrecipEcmwf = @($h.precipitation_ecmwf_ifs025)
        HourlyPrecipGfs   = @($h.precipitation_gfs_seamless)
        HourlyPrecipIcon  = @($h.precipitation_icon_seamless)
        HourlyIsoEcmwf    = @($h.freezing_level_height_ecmwf_ifs025)
        HourlyIsoGfs      = @($h.freezing_level_height_gfs_seamless)
        HourlyIsoIcon     = @($h.freezing_level_height_icon_seamless)
    }
}

function Get-SumaVentana([array]$serie, [int]$desde, [int]$hasta) {
    $suma = 0.0
    for ($i = $desde; $i -le $hasta; $i++) {
        if ($null -ne $serie[$i]) { $suma += [double]$serie[$i] }
    }
    return [math]::Round($suma, 1)
}

function Get-MinVentana([array]$serie, [int]$desde, [int]$hasta) {
    $min = $null
    for ($i = $desde; $i -le $hasta; $i++) {
        if ($null -ne $serie[$i]) {
            $v = [int]$serie[$i]
            if ($null -eq $min -or $v -lt $min) { $min = $v }
        }
    }
    return $min
}
