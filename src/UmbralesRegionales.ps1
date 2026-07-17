# Sistema de alertas verde/amarillo/rojo por SOLO precipitacion, con umbrales oficiales
# tipo SENAPRED (aviso/alerta/alarma) que dependen de la region y del dia de lluvia
# continua (el umbral baja con cada dia de lluvia porque el suelo ya esta saturado).
# Tabla entregada por el usuario 2026-07-08. Verificado: aviso_mm(dia N) =
# round(aviso_mm(dia 1) * factor_saturacion(dia N)) -- el factor ya viene en la tabla,
# se usan los mm ya calculados directamente (no hace falta recalcular el factor).
#
# Mapeo de color (decidido con el usuario): verde = bajo aviso, amarillo = [aviso,alerta),
# rojo = >= alerta. "alarma" queda solo como dato extra (no agrega un 4to color).

$script:TablaUmbralesRegionales = @{
    'Metropolitana' = @{
        1 = @{ aviso=35; alerta=71;  alarma=97  }
        2 = @{ aviso=30; alerta=60;  alarma=82  }
        3 = @{ aviso=25; alerta=50;  alarma=68  }
        4 = @{ aviso=21; alerta=43;  alarma=58  }
    }
    'OHiggins' = @{
        1 = @{ aviso=46; alerta=73;  alarma=97  }
        2 = @{ aviso=39; alerta=62;  alarma=82  }
        3 = @{ aviso=32; alerta=51;  alarma=68  }
        4 = @{ aviso=28; alerta=44;  alarma=58  }
    }
    'Maule' = @{
        1 = @{ aviso=43; alerta=66;  alarma=90  }
        2 = @{ aviso=37; alerta=56;  alarma=77  }
        3 = @{ aviso=30; alerta=46;  alarma=63  }
        4 = @{ aviso=26; alerta=40;  alarma=54  }
    }
    'Nuble' = @{
        1 = @{ aviso=43; alerta=75;  alarma=104 }
        2 = @{ aviso=37; alerta=64;  alarma=88  }
        3 = @{ aviso=30; alerta=53;  alarma=73  }
        4 = @{ aviso=26; alerta=45;  alarma=62  }
    }
    'Biobio' = @{
        1 = @{ aviso=45; alerta=75;  alarma=108 }
        2 = @{ aviso=38; alerta=64;  alarma=92  }
        3 = @{ aviso=32; alerta=53;  alarma=76  }
        4 = @{ aviso=27; alerta=45;  alarma=65  }
    }
    'Araucania' = @{
        1 = @{ aviso=54; alerta=96;  alarma=121 }
        2 = @{ aviso=46; alerta=82;  alarma=103 }
        3 = @{ aviso=38; alerta=67;  alarma=85  }
        4 = @{ aviso=32; alerta=58;  alarma=73  }
    }
    'LosRios' = @{
        1 = @{ aviso=73; alerta=220; alarma=220 }
        2 = @{ aviso=62; alerta=187; alarma=187 }
        3 = @{ aviso=51; alerta=154; alarma=154 }
        4 = @{ aviso=44; alerta=132; alarma=132 }
    }
    'LosLagos' = @{
        1 = @{ aviso=97; alerta=124; alarma=294 }
        2 = @{ aviso=82; alerta=105; alarma=250 }
        3 = @{ aviso=68; alerta=87;  alarma=206 }
        4 = @{ aviso=58; alerta=74;  alarma=176 }
    }
}

# Region asignada por latitud del "ancla" (capital regional) mas cercana -- metodo
# aproximado aceptado explicitamente (no hay campo "region" en ninguna fuente de datos).
# Fuera del rango RM-Los Lagos (~-32.5 a ~-44.0) no hay tabla -> $null (usa el sistema
# simple 5/10 mm/h existente).
$script:AnclasRegionLat = [ordered]@{
    'Metropolitana' = -33.45
    'OHiggins'      = -34.17
    'Maule'         = -35.43
    'Nuble'         = -36.61
    'Biobio'        = -36.83
    'Araucania'     = -38.74
    'LosRios'       = -39.81
    'LosLagos'      = -41.47
}

function Get-RegionPorLat {
    param([double]$Lat)
    if ($Lat -gt -32.5 -or $Lat -lt -44.0) { return $null }
    $mejorRegion = $null; $mejorDist = [double]::MaxValue
    foreach ($r in $script:AnclasRegionLat.Keys) {
        $d = [math]::Abs($Lat - $script:AnclasRegionLat[$r])
        if ($d -lt $mejorDist) { $mejorDist = $d; $mejorRegion = $r }
    }
    return $mejorRegion
}

function Get-UmbralesRegion {
    param([string]$Region, [int]$DiaRacha)
    if (-not $Region -or -not $script:TablaUmbralesRegionales.ContainsKey($Region)) { return $null }
    $dia = [math]::Min([math]::Max($DiaRacha, 1), 4)
    return $script:TablaUmbralesRegionales[$Region][$dia]
}

function Get-ColorPrecipRegional {
    param([double]$MmAcumulado, $Umbrales)
    if ($null -eq $Umbrales) { return $null }
    if ($MmAcumulado -ge $Umbrales.alerta) { return 'rojo' }
    if ($MmAcumulado -ge $Umbrales.aviso)  { return 'amarillo' }
    return 'verde'
}

function Get-FechaChile {
    $tzChile = [System.TimeZoneInfo]::FindSystemTimeZoneById('Pacific SA Standard Time')
    $nowChile = [System.TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $tzChile)
    return $nowChile.ToString('yyyy-MM-dd')
}

# Suma los valores cuya marca de tiempo (epoch) cae en el dia calendario de Chile indicado.
# Sirve para las redes que vienen de vismet (serie horaria rolling de 48h) -- las DMC
# directas ya traen el acumulado del dia hecho por la propia DMC ("Hoy"), no necesitan esto.
function Get-AcumuladoCalendario {
    param([array]$Tiempos, [array]$Valores, [string]$FechaChile)
    if (-not $Tiempos -or $Tiempos.Count -eq 0) { return 0.0 }
    $tzChile = [System.TimeZoneInfo]::FindSystemTimeZoneById('Pacific SA Standard Time')
    $suma = 0.0
    for ($i = 0; $i -lt $Tiempos.Count; $i++) {
        if ($null -eq $Valores[$i]) { continue }
        $utcDt   = [DateTimeOffset]::FromUnixTimeSeconds([long]$Tiempos[$i]).UtcDateTime
        $localDt = [System.TimeZoneInfo]::ConvertTimeFromUtc($utcDt, $tzChile)
        if ($localDt.ToString('yyyy-MM-dd') -eq $FechaChile) { $suma += [double]$Valores[$i] }
    }
    return [math]::Round($suma, 2)
}

function Read-EstadoRacha {
    param([string]$Path)
    $estado = @{}
    if (Test-Path $Path) {
        try {
            $obj = Get-Content $Path -Raw | ConvertFrom-Json
            foreach ($p in $obj.PSObject.Properties) {
                $estado[$p.Name] = @{
                    fecha = [string]$p.Value.fecha
                    acumuladoDia = [double]$p.Value.acumuladoDia
                    racha = [int]$p.Value.racha
                }
            }
        } catch { Write-Warning "Cache racha de lluvia ilegible, se reinicia: $_" }
    }
    return $estado
}

function Save-EstadoRacha {
    param([string]$Path, [hashtable]$Estado)
    try {
        $ordenado = [ordered]@{}
        foreach ($k in ($Estado.Keys | Sort-Object)) { $ordenado[$k] = $Estado[$k] }
        $tmp = "$Path.tmp"
        ($ordenado | ConvertTo-Json -Depth 4) | Set-Content -Path $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $Path -Force
    } catch { Write-Warning "No se pudo guardar estado de racha: $_" }
}

# Actualiza la racha de dias de lluvia continua de una estacion.
# Regla (confirmada con el usuario): cualquier mm>0 en el dia cuenta como "dia de lluvia";
# un dia en 0.0mm corta la racha. Un salto de mas de 1 dia calendario sin corridas (cron
# caido) tambien corta la racha, porque no se puede saber que paso en el medio.
function Update-RachaEstacion {
    param([hashtable]$EstadoPrev, [string]$Codigo, [string]$FechaHoy, [double]$MmHoy)
    $prev = $EstadoPrev[$Codigo]

    if (-not $prev) {
        $racha = if ($MmHoy -gt 0) { 1 } else { 0 }
        return @{ fecha = $FechaHoy; acumuladoDia = $MmHoy; racha = $racha }
    }

    if ($prev.fecha -eq $FechaHoy) {
        # mismo dia calendario: se actualiza el acumulado corrido; la racha del dia recien
        # se confirma cuando ya hay algo de lluvia (si el dia sigue en 0, todavia no cuenta).
        $racha = if ($prev.racha -eq 0 -and $MmHoy -gt 0) { 1 } else { $prev.racha }
        return @{ fecha = $FechaHoy; acumuladoDia = $MmHoy; racha = $racha }
    }

    $diasGap = ([datetime]$FechaHoy - [datetime]$prev.fecha).Days
    $continuaDesdeAyer = ($diasGap -eq 1) -and ($prev.acumuladoDia -gt 0)
    $rachaBase = if ($continuaDesdeAyer) { $prev.racha + 1 } else { 0 }
    $racha = if ($MmHoy -gt 0) { [math]::Max($rachaBase, 1) } else { 0 }
    return @{ fecha = $FechaHoy; acumuladoDia = $MmHoy; racha = $racha }
}

# Anota cada estacion (objeto con .Lat/.Codigo/.AcumuladoHoy) con Region/DiaRacha/
# UmbralesRegion/ColorPrecipRegional, y devuelve el nuevo estado de racha para persistir.
function Add-InfoRegional {
    param([array]$Estaciones, [hashtable]$EstadoPrev, [string]$FechaHoy)
    $estadoNuevo = @{}
    foreach ($e in $Estaciones) {
        $region = Get-RegionPorLat $e.Lat

        if ($null -eq $e.AcumuladoHoy) {
            # SIN DATO de acumulado (la fuente no lo entrego en esta corrida): no fingir
            # 0 mm — un 0 falso corta la racha de lluvia continua y pinta verde en pleno
            # temporal (gotcha DMC 2026-07-17). Se conserva el estado de racha previo tal
            # cual y la estacion queda sin color regional (cae al umbral simple de tasa).
            $prevRacha = $null
            if ($EstadoPrev.ContainsKey($e.Codigo)) {
                $prevRacha = $EstadoPrev[$e.Codigo]
                $estadoNuevo[$e.Codigo] = $prevRacha
            }
            $rachaPrev = if ($prevRacha) { [int]$prevRacha.racha } else { 0 }
            $umbrales  = if ($region) { Get-UmbralesRegion $region $rachaPrev } else { $null }
            Add-Member -InputObject $e -NotePropertyName Region              -NotePropertyValue $region     -Force
            Add-Member -InputObject $e -NotePropertyName DiaRacha            -NotePropertyValue $rachaPrev  -Force
            Add-Member -InputObject $e -NotePropertyName AcumuladoHoy        -NotePropertyValue $null       -Force
            Add-Member -InputObject $e -NotePropertyName UmbralesRegion      -NotePropertyValue $umbrales   -Force
            Add-Member -InputObject $e -NotePropertyName ColorPrecipRegional -NotePropertyValue $null       -Force
            continue
        }

        $mmHoy = [double]$e.AcumuladoHoy
        $r = Update-RachaEstacion -EstadoPrev $EstadoPrev -Codigo $e.Codigo -FechaHoy $FechaHoy -MmHoy $mmHoy
        $estadoNuevo[$e.Codigo] = $r
        $umbrales = if ($region) { Get-UmbralesRegion $region $r.racha } else { $null }
        $colorReg = if ($umbrales) { Get-ColorPrecipRegional $mmHoy $umbrales } else { $null }

        Add-Member -InputObject $e -NotePropertyName Region              -NotePropertyValue $region    -Force
        Add-Member -InputObject $e -NotePropertyName DiaRacha            -NotePropertyValue $r.racha    -Force
        Add-Member -InputObject $e -NotePropertyName AcumuladoHoy        -NotePropertyValue $mmHoy      -Force
        Add-Member -InputObject $e -NotePropertyName UmbralesRegion      -NotePropertyValue $umbrales   -Force
        Add-Member -InputObject $e -NotePropertyName ColorPrecipRegional -NotePropertyValue $colorReg   -Force
    }
    return $estadoNuevo
}
