function Get-GrillaChile {
    # lonMax por latitud: límite aproximado con Argentina/Bolivia
    $lonMaxTab = @{
        '-17.5'='-68'; '-19.5'='-68'; '-21.5'='-68'; '-23.5'='-68'
        '-25.5'='-68'; '-27.5'='-69'; '-29.5'='-70'; '-31.5'='-70'
        '-33.5'='-70'; '-35.5'='-71'; '-37.5'='-71'; '-39.5'='-71'
        '-41.5'='-72'; '-43.5'='-72'; '-45.5'='-72'; '-47.5'='-73'
        '-49.5'='-73'; '-51.5'='-73'; '-53.5'='-69'; '-55.5'='-69'
    }
    $puntos = @()
    $lat = -17.5
    while ($lat -ge -56.0) {
        $latKey = $lat.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        $lonMax = if ($lonMaxTab.ContainsKey($latKey)) { [double]$lonMaxTab[$latKey] } else { -70.0 }
        $lonMin = if ($lat -gt -43) { -75.0 } else { -77.0 }
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

function Build-VentanasPunto($punto) {
    $config = @(
        @{ Nombre='+0 a 6h';   Desde=0;  Hasta=5  }
        @{ Nombre='+6 a 12h';  Desde=6;  Hasta=11 }
        @{ Nombre='+12 a 24h'; Desde=12; Hasta=23 }
        @{ Nombre='+24 a 48h'; Desde=24; Hasta=47 }
    )
    $orden    = @{ verde=0; amarillo=1; rojo=2 }
    $ventanas = [System.Collections.ArrayList]::new()
    foreach ($cfg in $config) {
        $pE = Get-SumaVentana $punto.HourlyPrecipEcmwf $cfg.Desde $cfg.Hasta
        $pG = Get-SumaVentana $punto.HourlyPrecipGfs   $cfg.Desde $cfg.Hasta
        $pI = Get-SumaVentana $punto.HourlyPrecipIcon  $cfg.Desde $cfg.Hasta
        $iE = Get-MinVentana  $punto.HourlyIsoEcmwf    $cfg.Desde $cfg.Hasta
        $iG = Get-MinVentana  $punto.HourlyIsoGfs      $cfg.Desde $cfg.Hasta
        $iI = Get-MinVentana  $punto.HourlyIsoIcon     $cfg.Desde $cfg.Hasta

        $cE = Get-ColorPronostico $pE $iE
        $cG = Get-ColorPronostico $pG $iG
        $cI = Get-ColorPronostico $pI $iI

        $colores = @($cE, $cG, $cI)
        $peor = $colores | Sort-Object { $orden[$_] } -Descending | Select-Object -First 1
        $n    = ($colores | Where-Object { $_ -eq $peor }).Count

        [void]$ventanas.Add([PSCustomObject]@{
            Nombre      = $cfg.Nombre
            Lat         = $punto.Lat
            Lon         = $punto.Lon
            PrecipEcmwf = $pE
            PrecipGfs   = $pG
            PrecipIcon  = $pI
            IsoEcmwf    = $iE
            IsoGfs      = $iG
            IsoIcon     = $iI
            ColorEcmwf  = $cE
            ColorGfs    = $cG
            ColorIcon   = $cI
            ColorFinal  = $peor
            NModelos    = $n
            EstiloKml   = Get-EstiloPronostico $peor $n
        })
    }
    return $ventanas.ToArray()
}

function Get-PronosticoGrilla([array]$grilla) {
    $allVentanas = @()
    $i = 0
    while ($i -lt $grilla.Count) {
        $hasta = [Math]::Min($i + 99, $grilla.Count - 1)
        $lote  = $grilla[$i..$hasta]
        $lats  = @($lote | ForEach-Object { $_.Lat.ToString([System.Globalization.CultureInfo]::InvariantCulture) }) -join ','
        $lons  = @($lote | ForEach-Object { $_.Lon.ToString([System.Globalization.CultureInfo]::InvariantCulture) }) -join ','
        $url   = "https://api.open-meteo.com/v1/forecast?latitude=$lats&longitude=$lons" +
                 "&hourly=precipitation,freezing_level_height" +
                 "&models=ecmwf_ifs025,gfs_seamless,icon_seamless&forecast_days=2"
        $resp  = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 60
        [array]$arr = $resp.Content | ConvertFrom-Json
        foreach ($obj in $arr) {
            $pt = Parse-OpenMeteoPoint $obj
            $allVentanas += Build-VentanasPunto $pt
        }
        $i += 100
        if ($i -lt $grilla.Count) { Start-Sleep -Milliseconds 400 }
    }
    return $allVentanas
}
