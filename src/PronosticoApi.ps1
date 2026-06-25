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
