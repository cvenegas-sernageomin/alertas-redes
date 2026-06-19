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
            Red     = if ($d.organizationName) { $d.organizationName } else { '' }
        }
    }
    return $result
}

function Get-Cr2AllRedes {
    $epoch = Get-EpochHora
    $ruta = "api/measure/by-measure-type/1/by-timestamp/$epoch/by-interval/3"
    $k = Sign $ruta
    $r = Invoke-WebRequest -Uri "https://vismet.cr2.cl/$ruta" `
        -Headers @{ckey = $k} -UseBasicParsing -TimeoutSec 90
    if ($r.Content -match '<!DOCTYPE') { throw "CR2 devolvio HTML en vez de JSON" }
    $datos = $r.Content | ConvertFrom-Json
    return Parse-RedesJson $datos
}
