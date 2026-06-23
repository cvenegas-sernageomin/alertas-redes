function Sign([string]$u) {
    [int64]$h = 0
    foreach ($ch in $u.ToCharArray()) {
        $h = (($h * 31) + [int][char]$ch) -band 0xFFFFFFFFL
    }
    return ('{0:x}' -f $h)
}

function Get-EpochHora {
    $now = [DateTimeOffset]::UtcNow
    $hora = [DateTimeOffset]::new($now.Year, $now.Month, $now.Day, $now.Hour, 0, 0, [TimeSpan]::Zero)
    return [int64]$hora.ToUnixTimeSeconds()
}

function Get-RedFromCode([string]$code) {
    if ($code -match '^AG')   { return 'Agromet' }
    if ($code -match '^CE')   { return 'CEAZA' }
    if ($code -match '^(yy|zx):') { return 'RedMeteo' }
    if ($code -match '^\d{2}') { return 'DGA/DMC' }
    return 'Otras'
}

function Parse-RedesJson([array]$datos) {
    $result = @()
    foreach ($d in $datos) {
        $tasa = 0.0
        if ($d.values -and $d.values.Count -gt 0) {
            for ($i = $d.values.Count - 1; $i -ge 0; $i--) {
                if ($null -ne $d.values[$i]) {
                    $tasa = [double]$d.values[$i]
                    break
                }
            }
        }
        $ultimoTs = if ($d.timestamps -and $d.timestamps.Count -gt 0) { $d.timestamps[-1] } else { 0 }
        $result += [PSCustomObject]@{
            Nombre  = $d.name
            Codigo  = $d.nationalCode
            Lat     = [double]$d.lat
            Lon     = [double]$d.lng
            TasaMmH = $tasa
            Epoch   = $ultimoTs
            Red     = Get-RedFromCode $d.nationalCode
        }
    }
    return $result
}

function Get-AllRedes {
    $epoch = Get-EpochHora
    $ruta = "api/measure/by-measure-type/1/by-timestamp/$epoch/by-interval/3"
    $k = Sign $ruta
    $r = Invoke-WebRequest -Uri "https://vismet.cr2.cl/$ruta" `
        -Headers @{ckey = $k} -UseBasicParsing -TimeoutSec 90
    if ($r.Content -match '<!DOCTYPE') { throw "API devolvio HTML en vez de JSON" }
    $datos = $r.Content | ConvertFrom-Json
    return Parse-RedesJson $datos
}

function Parse-EmasDmcJson([array]$precipArr, [array]$tempArr) {
    $tempIdx = @{}
    foreach ($t in $tempArr) { $tempIdx[$t.station.nationalCode] = $t }

    $result = @()
    foreach ($p in $precipArr) {
        $s    = $p.station
        $tObj = $tempIdx[$s.nationalCode]
        $tempC   = if ($tObj) { [double]$tObj.aggregatedValue } else { $null }
        $iso     = $null
        if ($null -ne $tempC -and $null -ne $s.altitude) {
            $iso = [int][math]::Floor($s.altitude + ($tempC / 6.5) * 1000)
        }
        $result += [PSCustomObject]@{
            Nombre   = $s.name
            Codigo   = $s.nationalCode
            Lat      = [double]$s.latitude
            Lon      = [double]$s.longitude
            Altitud  = $s.altitude
            TasaMmH  = [double]$p.aggregatedValue
            TempC    = $tempC
            Isoterma = $iso
            Epoch    = $p.targetTimestamp
        }
    }
    return $result
}

function Get-EmasDmc {
    $rutaP = "api/raw-measure/by-measure-type/1/last"
    $rutaT = "api/raw-measure/by-measure-type/2/last"
    $rP = Invoke-WebRequest -Uri "https://vismet.cr2.cl/$rutaP" `
        -Headers @{ckey = (Sign $rutaP)} -UseBasicParsing -TimeoutSec 60
    $rT = Invoke-WebRequest -Uri "https://vismet.cr2.cl/$rutaT" `
        -Headers @{ckey = (Sign $rutaT)} -UseBasicParsing -TimeoutSec 60
    if ($rP.Content -match '<!DOCTYPE') { throw "API devolvio HTML (precip)" }
    if ($rT.Content -match '<!DOCTYPE') { throw "API devolvio HTML (temp)" }
    return Parse-EmasDmcJson ($rP.Content | ConvertFrom-Json) ($rT.Content | ConvertFrom-Json)
}
