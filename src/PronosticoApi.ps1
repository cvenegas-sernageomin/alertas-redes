function Get-GrillaChile {
    # lonMax (este): limite con Argentina/Bolivia por latitud
    $lonMaxTab = @{
        '-17.5'='-68';'-18.5'='-68';'-19.5'='-68';'-20.5'='-68';'-21.5'='-68';'-22.5'='-68'
        '-23.5'='-68';'-24.5'='-68';'-25.5'='-68';'-26.5'='-68';'-27.5'='-69';'-28.5'='-69'
        '-29.5'='-70';'-30.5'='-70';'-31.5'='-70';'-32.5'='-70';'-33.5'='-70';'-34.5'='-70'
        '-35.5'='-71';'-36.5'='-71';'-37.5'='-71';'-38.5'='-71';'-39.5'='-71';'-40.5'='-71'
        '-41.5'='-72';'-42.5'='-72';'-43.5'='-72';'-44.5'='-72';'-45.5'='-72';'-46.5'='-72'
        '-47.5'='-73';'-48.5'='-73';'-49.5'='-73';'-50.5'='-73';'-51.5'='-73';'-52.5'='-73'
        '-53.5'='-69';'-54.5'='-69';'-55.5'='-69'
    }
    # lonMin (oeste): limite aproximado de la costa chilena (evita puntos en el oceano)
    $lonMinTab = @{
        '-17.5'='-71';'-18.5'='-71';'-19.5'='-71';'-20.5'='-71';'-21.5'='-71';'-22.5'='-71'
        '-23.5'='-71';'-24.5'='-71';'-25.5'='-72';'-26.5'='-72';'-27.5'='-72';'-28.5'='-72'
        '-29.5'='-72';'-30.5'='-72';'-31.5'='-72';'-32.5'='-72';'-33.5'='-73';'-34.5'='-73'
        '-35.5'='-73';'-36.5'='-73';'-37.5'='-73';'-38.5'='-73';'-39.5'='-73';'-40.5'='-73'
        '-41.5'='-74';'-42.5'='-74';'-43.5'='-74';'-44.5'='-74';'-45.5'='-74';'-46.5'='-74'
        '-47.5'='-75';'-48.5'='-75';'-49.5'='-75';'-50.5'='-75';'-51.5'='-75';'-52.5'='-75'
        '-53.5'='-75';'-54.5'='-75';'-55.5'='-75'
    }
    $puntos = @()
    $lat = -17.5
    while ($lat -ge -56.0) {
        $latKey = $lat.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        $lonMax = if ($lonMaxTab.ContainsKey($latKey)) { [double]$lonMaxTab[$latKey] } else { -70.0 }
        $lonMin = if ($lonMinTab.ContainsKey($latKey)) { [double]$lonMinTab[$latKey] } else { -73.0 }
        $lon = $lonMin
        while ($lon -le $lonMax) {
            $puntos += [PSCustomObject]@{ Lat = $lat; Lon = $lon }
            $lon = [math]::Round($lon + 1.0, 1)
        }
        $lat = [math]::Round($lat - 1.0, 1)
    }
    # Islas oceanicas
    $puntos += [PSCustomObject]@{ Lat = -27.0; Lon = -109.5 }  # Isla de Pascua
    $puntos += [PSCustomObject]@{ Lat = -33.5; Lon = -79.0  }  # Robinson Crusoe
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
        # Temperatura y viento: solo informativos, no alteran la logica de alertas (precip+iso).
        HourlyTempEcmwf   = @($h.temperature_2m_ecmwf_ifs025)
        HourlyTempGfs     = @($h.temperature_2m_gfs_seamless)
        HourlyTempIcon    = @($h.temperature_2m_icon_seamless)
        HourlyGustEcmwf   = @($h.wind_gusts_10m_ecmwf_ifs025)
        HourlyGustGfs     = @($h.wind_gusts_10m_gfs_seamless)
        HourlyGustIcon    = @($h.wind_gusts_10m_icon_seamless)
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

function Get-MaxVentana([array]$serie, [int]$desde, [int]$hasta) {
    $max = $null
    for ($i = $desde; $i -le $hasta; $i++) {
        if ($null -ne $serie[$i]) {
            $v = [double]$serie[$i]
            if ($null -eq $max -or $v -gt $max) { $max = $v }
        }
    }
    return $max
}

function Get-ColorPronostico([double]$precip, $iso) {
    if ($null -eq $iso)       { return 'verde' }
    if ($precip -lt 5)        { return 'verde' }
    if ($iso -lt 2500)        { return 'verde' }
    if ($precip -ge 20 -and $iso -ge 3000) { return 'rojo' }
    return 'amarillo'
}

function Get-EstiloPronostico([string]$colorPeor, [int]$nModelos) {
    if ($colorPeor -eq 'verde') { return 'verde_p' }
    return "${colorPeor}_${nModelos}"
}

function Get-ColorPeorYN([array]$colores) {
    $orden = @{ verde=0; amarillo=1; rojo=2 }
    $peor  = $colores | Sort-Object { $orden[$_] } -Descending | Select-Object -First 1
    $n     = @($colores | Where-Object { $_ -eq $peor }).Count
    return [PSCustomObject]@{ Color=$peor; N=$n }
}

# Alerta ADICIONAL de solo precipitacion con los umbrales regionales aviso/alerta/alarma
# (RM a Los Lagos). NO reemplaza ColorFinal/EstiloKml (esos siguen siendo el combo
# precip+iso de siempre, sin cambios) -- esto es un dato extra para mostrar en el popup.
# Dia 1 = acumulado +0 a 24h del pronostico, Dia 2 = +24 a 48h (simplificacion: el
# pronostico no conoce la racha de lluvia real antes de su ventana, asi que asume que
# el propio dia 2 del pronostico es "el segundo dia de lluvia" si el dia 1 ya moja).
function Get-AlertaPrecipRegionalPunto($punto) {
    $region = Get-RegionPorLat $punto.Lat
    if (-not $region) { return $null }

    $sD1 = @(
        (Get-SumaVentana $punto.HourlyPrecipEcmwf 0 23),
        (Get-SumaVentana $punto.HourlyPrecipGfs   0 23),
        (Get-SumaVentana $punto.HourlyPrecipIcon  0 23)
    )
    $sD2 = @(
        (Get-SumaVentana $punto.HourlyPrecipEcmwf 24 47),
        (Get-SumaVentana $punto.HourlyPrecipGfs   24 47),
        (Get-SumaVentana $punto.HourlyPrecipIcon  24 47)
    )
    $uD1 = Get-UmbralesRegion $region 1
    $uD2 = Get-UmbralesRegion $region 2
    $cD1 = @($sD1 | ForEach-Object { Get-ColorPrecipRegional $_ $uD1 })
    $cD2 = @($sD2 | ForEach-Object { Get-ColorPrecipRegional $_ $uD2 })
    $pD1 = Get-ColorPeorYN $cD1
    $pD2 = Get-ColorPeorYN $cD2

    return [PSCustomObject]@{
        Region       = $region
        Dia1Color    = $pD1.Color; Dia1N = $pD1.N; Dia1Mm = ($sD1 | Measure-Object -Maximum).Maximum
        Dia2Color    = $pD2.Color; Dia2N = $pD2.N; Dia2Mm = ($sD2 | Measure-Object -Maximum).Maximum
        UmbralesDia1 = $uD1; UmbralesDia2 = $uD2
    }
}

function Build-VentanasPunto($punto) {
    $config = @(
        @{ Nombre='+0 a 6h';   Desde=0;  Hasta=5  }
        @{ Nombre='+6 a 12h';  Desde=6;  Hasta=11 }
        @{ Nombre='+12 a 24h'; Desde=12; Hasta=23 }
        @{ Nombre='+24 a 48h'; Desde=24; Hasta=47 }
    )
    $orden    = @{ verde=0; amarillo=1; rojo=2 }
    $ventanas = [System.Collections.ArrayList]::new()
    $alertaRegional = Get-AlertaPrecipRegionalPunto $punto
    foreach ($cfg in $config) {
        $pE = Get-SumaVentana $punto.HourlyPrecipEcmwf $cfg.Desde $cfg.Hasta
        $pG = Get-SumaVentana $punto.HourlyPrecipGfs   $cfg.Desde $cfg.Hasta
        $pI = Get-SumaVentana $punto.HourlyPrecipIcon  $cfg.Desde $cfg.Hasta
        $iE = Get-MinVentana  $punto.HourlyIsoEcmwf    $cfg.Desde $cfg.Hasta
        $iG = Get-MinVentana  $punto.HourlyIsoGfs      $cfg.Desde $cfg.Hasta
        $iI = Get-MinVentana  $punto.HourlyIsoIcon     $cfg.Desde $cfg.Hasta

        # Temperatura y viento (solo informativos, no entran en Get-ColorPronostico):
        # temperatura = promedio entre los 3 modelos; viento = rafaga maxima (peor caso).
        $tMins = @(
            (Get-MinVentana $punto.HourlyTempEcmwf $cfg.Desde $cfg.Hasta),
            (Get-MinVentana $punto.HourlyTempGfs   $cfg.Desde $cfg.Hasta),
            (Get-MinVentana $punto.HourlyTempIcon  $cfg.Desde $cfg.Hasta)
        ) | Where-Object { $null -ne $_ }
        $tMaxs = @(
            (Get-MaxVentana $punto.HourlyTempEcmwf $cfg.Desde $cfg.Hasta),
            (Get-MaxVentana $punto.HourlyTempGfs   $cfg.Desde $cfg.Hasta),
            (Get-MaxVentana $punto.HourlyTempIcon  $cfg.Desde $cfg.Hasta)
        ) | Where-Object { $null -ne $_ }
        $tempMin = if ($tMins.Count -gt 0) { [math]::Round(($tMins | Measure-Object -Average).Average, 1) } else { $null }
        $tempMax = if ($tMaxs.Count -gt 0) { [math]::Round(($tMaxs | Measure-Object -Average).Average, 1) } else { $null }
        $gustos  = @(
            (Get-MaxVentana $punto.HourlyGustEcmwf $cfg.Desde $cfg.Hasta),
            (Get-MaxVentana $punto.HourlyGustGfs   $cfg.Desde $cfg.Hasta),
            (Get-MaxVentana $punto.HourlyGustIcon  $cfg.Desde $cfg.Hasta)
        ) | Where-Object { $null -ne $_ }
        $vientoMax = if ($gustos.Count -gt 0) { [math]::Round(($gustos | Measure-Object -Maximum).Maximum) } else { $null }

        $cE = Get-ColorPronostico $pE $iE
        $cG = Get-ColorPronostico $pG $iG
        $cI = Get-ColorPronostico $pI $iI

        $colores = @($cE, $cG, $cI)
        $peor = $colores | Sort-Object { $orden[$_] } -Descending | Select-Object -First 1
        $n    = @($colores | Where-Object { $_ -eq $peor }).Count

        [void]$ventanas.Add([PSCustomObject]@{
            Nombre      = $cfg.Nombre
            Lat         = $punto.Lat
            Lon         = $punto.Lon
            PrecipEcmwf = $pE
            PrecipGfs   = $pG
            PrecipIcon  = $pI
            TempMinC    = $tempMin
            TempMaxC    = $tempMax
            VientoMaxKmh = $vientoMax
            IsoEcmwf    = $iE
            IsoGfs      = $iG
            IsoIcon     = $iI
            ColorEcmwf  = $cE
            ColorGfs    = $cG
            ColorIcon   = $cI
            ColorFinal  = $peor
            NModelos    = $n
            EstiloKml   = Get-EstiloPronostico $peor $n
            AlertaRegional = $alertaRegional
        })
    }
    return $ventanas.ToArray()
}

function Get-PronosticoGrilla([array]$grilla) {
    $allVentanas = [System.Collections.Generic.List[object]]::new()
    $i = 0
    while ($i -lt $grilla.Count) {
        $hasta = [Math]::Min($i + 99, $grilla.Count - 1)
        $lote  = $grilla[$i..$hasta]
        $lats  = @($lote | ForEach-Object { $_.Lat.ToString([System.Globalization.CultureInfo]::InvariantCulture) }) -join ','
        $lons  = @($lote | ForEach-Object { $_.Lon.ToString([System.Globalization.CultureInfo]::InvariantCulture) }) -join ','
        $url   = "https://api.open-meteo.com/v1/forecast?latitude=$lats&longitude=$lons" +
                 "&hourly=precipitation,freezing_level_height,temperature_2m,wind_gusts_10m" +
                 "&models=ecmwf_ifs025,gfs_seamless,icon_seamless&forecast_days=2"
        $resp  = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 60
        [array]$arr = $resp.Content | ConvertFrom-Json
        foreach ($obj in $arr) {
            $pt = Parse-OpenMeteoPoint $obj
            foreach ($v in Build-VentanasPunto $pt) { $allVentanas.Add($v) }
        }
        $i += 100
        if ($i -lt $grilla.Count) { Start-Sleep -Milliseconds 400 }
    }
    return $allVentanas.ToArray()
}
