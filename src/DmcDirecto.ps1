# Fuente alternativa DIRECTA de estaciones DMC (EMAs), sin pasar por vismet.cr2.cl.
# Motivo: se verifico 2026-07-08 que vismet devuelve 0.0 fijo para TODAS las estaciones
# DGA y DMC (686 estaciones, 48h, cero excepciones) mientras el portal publico de la DMC
# (climatologia.meteochile.gob.cl) muestra lluvia real y actual para las mismas estaciones
# codificadas. El feed DGA/DMC de vismet esta roto en origen; el de DMC directo funciona.
# Reutiliza el patron ya validado en el proyecto hermano emas-kmz (ver
# reference-dmc-visor-publico-sin-token en memoria).

function Get-DmcHtmlGzip {
    param(
        [string]$Url,
        [int]$TimeoutSeg = 30,
        [string]$UserAgent = 'alertas-redes/1.0 (uso institucional SERNAGEOMIN; geologia)'
    )
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.UserAgent = $UserAgent
    $req.Timeout = $TimeoutSeg * 1000
    $req.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $resp = $req.GetResponse()
    try {
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        try { return $sr.ReadToEnd() } finally { $sr.Close() }
    } finally { $resp.Close() }
}

function Get-CodigosEmaDmc {
    param([string]$Grupo = 'EMAPublicadas')
    $url = "https://climatologia.meteochile.gob.cl/application/informacion/estacionesEnGrupo/$Grupo"
    $r = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 60
    $codigos = [regex]::Matches($r.Content, '(?:visorDeDatosEma|fichaDeEstacion)/(\d+)') |
        ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique | Sort-Object { [int]$_ }
    if ($codigos.Count -lt 1) { throw "No se encontraron codigos DMC en el grupo $Grupo" }
    return ,@($codigos)
}

function Get-EmaInfoDirecto {
    param([string]$Html)
    $opt = [System.Text.RegularExpressions.RegexOptions]::Singleline

    $nombre = $null
    $mN = [regex]::Match($Html, '<h1>\s*([^<]+?)\s*</h1>\s*<h4>\s*<small>\s*Altura', $opt)
    if ($mN.Success) { $nombre = $mN.Groups[1].Value.Trim() }

    $alt = $null
    $mA = [regex]::Match($Html, 'Altura\s*:\s*([\d.]+)\s*mts')
    if ($mA.Success) { $alt = [double]$mA.Groups[1].Value }

    $lat = $null; $lon = $null
    $mC = [regex]::Match($Html, 'Coordenadas\s*:\s*(-?[\d.]+)[^,\d-]*,\s*(-?[\d.]+)')
    if ($mC.Success) { $lat = [double]$mC.Groups[1].Value; $lon = [double]$mC.Groups[2].Value }

    $ultimo = $null
    $mU = [regex]::Match($Html, '<h1>\s*(\d{1,2}:\d{2})\s*<small>\s*([^<]+?)\s*</small>\s*</h1>')
    if ($mU.Success) { $ultimo = ($mU.Groups[1].Value + ' ' + $mU.Groups[2].Value).Trim() }

    return [pscustomobject]@{
        Nombre = $nombre; Altitud = $alt; Lat = $lat; Lon = $lon; UltimoDato = $ultimo
    }
}

function Get-EmaTempActualDirecto {
    param([string]$Html)
    $opt = [System.Text.RegularExpressions.RegexOptions]::Singleline
    $m = [regex]::Match($Html, "chart\('temperatura'.*?series:\s*\[\{\s*name:\s*'[^']*',\s*data:\s*\[([^\]]*)\]", $opt)
    if (-not $m.Success) { return $null }
    $valores = $m.Groups[1].Value -split ','
    for ($i = $valores.Count - 1; $i -ge 0; $i--) {
        $v = $valores[$i].Trim()
        if ($v -and $v -ne 'null') { return [double]$v }
    }
    return $null
}

function Get-EmaPrecipHoyDirecto {
    param([string]$Html)
    $opt = [System.Text.RegularExpressions.RegexOptions]::Singleline
    $m = [regex]::Match($Html, '<h4>\s*Hoy\s*</h4>\s*</td>\s*<td[^>]*>\s*<h4>\s*([^<]+?)\s*</h4>', $opt)
    if (-not $m.Success) { return $null }
    $txt = $m.Groups[1].Value.Trim()
    if ($txt -match '(?i)^s/?p') { return 0.0 }
    $n = [regex]::Match($txt, '-?\d+([.,]\d+)?')
    if (-not $n.Success) { return $null }
    return [double]($n.Value -replace ',', '.')
}

# "UltimoDato" viene como "HH:mm dd MMM yyyy" en hora local de Chile (ej "08:30 08 Jul 2026").
# El mes puede venir en ingles o espanol abreviado segun el render del sitio -> mapa propio,
# no se confia en CultureInfo (ver gotchas PowerShell/Windows de este workspace).
function ConvertTo-EpochChile {
    param([string]$TextoFecha)
    if (-not $TextoFecha) { return $null }
    $meses = @{
        'ene'=1;'feb'=2;'mar'=3;'abr'=4;'may'=5;'jun'=6;'jul'=7;'ago'=8;'sep'=9;'oct'=10;'nov'=11;'dic'=12
        'jan'=1;'apr'=4;'aug'=8;'dec'=12
    }
    $m = [regex]::Match($TextoFecha, '^(\d{1,2}):(\d{2})\s+(\d{1,2})\s+([A-Za-z]{3})\.?\s+(\d{4})$')
    if (-not $m.Success) { return $null }
    $mesTxt = $m.Groups[4].Value.ToLowerInvariant()
    if (-not $meses.ContainsKey($mesTxt)) { return $null }
    try {
        $localDt = [datetime]::new(
            [int]$m.Groups[5].Value, $meses[$mesTxt], [int]$m.Groups[3].Value,
            [int]$m.Groups[1].Value, [int]$m.Groups[2].Value, 0, [DateTimeKind]::Unspecified)
        $tzChile = [System.TimeZoneInfo]::FindSystemTimeZoneById('Pacific SA Standard Time')
        $utcDt = [System.TimeZoneInfo]::ConvertTimeToUtc($localDt, $tzChile)
        return [int64]([DateTimeOffset]::new($utcDt, [TimeSpan]::Zero)).ToUnixTimeSeconds()
    } catch { return $null }
}

# Fecha calendario Chile (yyyy-MM-dd) de un epoch. Compartida por DMC directo, redes
# regionales y RedMeteo directo (todas las fuentes con "acumulado del dia" que se resetea
# a medianoche Chile).
function Get-FechaChileDeEpoch {
    param([long]$Epoch)
    $tzChile = [System.TimeZoneInfo]::FindSystemTimeZoneById('Pacific SA Standard Time')
    $utcDt = [DateTimeOffset]::FromUnixTimeSeconds($Epoch).UtcDateTime
    return ([System.TimeZoneInfo]::ConvertTimeFromUtc($utcDt, $tzChile)).ToString('yyyy-MM-dd')
}

# Epoch de la medianoche Chile del dia dado ('yyyy-MM-dd').
function Get-EpochMedianocheChile {
    param([string]$FechaChile)
    $tzChile = [System.TimeZoneInfo]::FindSystemTimeZoneById('Pacific SA Standard Time')
    $p = $FechaChile -split '-'
    $localDt = [datetime]::new([int]$p[0], [int]$p[1], [int]$p[2], 0, 0, 0, [DateTimeKind]::Unspecified)
    $utcDt = [System.TimeZoneInfo]::ConvertTimeToUtc($localDt, $tzChile)
    return [int64]([DateTimeOffset]::new($utcDt, [TimeSpan]::Zero)).ToUnixTimeSeconds()
}

# Siembra el "0 de medianoche" en la historia. NO es dato inventado: el acumulado diario
# se resetea a las 00:00 por definicion, asi que a esa hora el acumulado ERA 0.0. Esto:
#  (a) da grafico a una estacion lloviendo desde su PRIMERA corrida (rampa 00:00 -> ahora);
#  (b) ancla la BASE del dia aunque la historia ya tenga muestras de hoy — sin el 0, una
#      estacion que partio a mitad del dia con 94 mm ya caidos mostraba en el grafico solo
#      el delta entre corridas (p.ej. 16 mm) mientras el popup decia 110 mm (bug real
#      2026-07-17); y una muestra de AYER contra la primera de hoy descontaba el acumulado
#      de ayer (delta 110-44=66 en vez de 110).
# Idempotente: si ya existe la muestra de las 00:00 exactas, no agrega nada.
function Add-MedianocheCero {
    param([array]$Historia, [long]$MedianocheEpoch)
    $yaSembrado = @($Historia | Where-Object { [int64]$_.epoch -eq $MedianocheEpoch }).Count -gt 0
    if ($yaSembrado) { return ,@($Historia) }
    return ,@(@($Historia) + @(@{ epoch = $MedianocheEpoch; precip = 0.0 }))
}

# "Acumulado hoy" HONESTO cuando la fuente no entrego el dato ($PrecipHoy null).
# Gotcha real (2026-07-17 07:20): en la ventana de rollover matinal del sitio DMC la celda
# "Hoy" vino vacia para TODA la pasada (122 estaciones) y el codigo viejo lo convertia en
# "Acumulado hoy: 0 mm" -> 122 falsos ceros EN PLENO TEMPORAL (ademas cortaba la racha de
# lluvia continua de los umbrales regionales). Regla: null NO es 0.
#  1) si hay dato -> el dato;
#  2) si no, y el estado previo es DEL MISMO dia Chile -> se arrastra el ultimo acumulado
#     conocido del dia (cota inferior real);
#  3) si no -> $null (el KML lo muestra "s/d" y no se toca la racha).
function Get-AcumuladoHonesto {
    param($PrecipHoy, $PrevEntry, [string]$FechaChileHoy)
    if ($null -ne $PrecipHoy) { return [double]$PrecipHoy }
    if ($PrevEntry -and $null -ne $PrevEntry.precip -and
        (Get-FechaChileDeEpoch ([int64]$PrevEntry.epoch)) -eq $FechaChileHoy) {
        return [double]$PrevEntry.precip
    }
    return $null
}

# La DMC solo publica el acumulado del dia (se resetea a medianoche), no una serie horaria.
# La tasa mm/h se estima diferenciando contra la corrida anterior (EstadoPrev), igual que
# en emas-kmz. Mejora sobre el original: si hay reset de medianoche (delta negativo), se
# usa el propio PrecipActual como "caido desde el reset" en vez de descartarlo a 0 mm/h.
function Get-PrecipRateDirecto {
    param($PrecipActual, [long]$EpochActual, $PrecipPrev, $EpochPrev)
    if ($null -eq $PrecipActual -or $null -eq $PrecipPrev -or $null -eq $EpochPrev) { return $null }
    $horas = ($EpochActual - $EpochPrev) / 3600.0
    if ($horas -le 0) { return $null }
    $delta = [double]$PrecipActual - [double]$PrecipPrev
    if ($delta -lt 0) { $delta = [double]$PrecipActual }
    return [math]::Round($delta / $horas, 2)
}

# La DMC no publica una serie horaria, solo el acumulado del dia actual. Para poder
# graficar (igual que las demas redes) se guarda una MINI-HISTORIA de muestras
# {epoch;precip} tomadas en cada corrida del cron (irregulares, cada ~2-5h reales) y se
# reconstruye una serie de "mm caidos entre lecturas consecutivas" a partir de ellas.
# No es tan prolijo como una serie horaria real, pero es información real (no inventada)
# y hace que el grafico de acumulado funcione para DMC igual que para las demas redes.
function Get-SerieDesdeHistoria {
    param([array]$Historia)
    $ordenada = @($Historia | Sort-Object { [int64]$_.epoch })
    if ($ordenada.Count -lt 2) { return @{ Tiempos = @(); Valores = @() } }
    $tiempos = [System.Collections.Generic.List[long]]::new()
    $valores = [System.Collections.Generic.List[double]]::new()
    # Punto inicial: se emite solo si su acumulado es 0 (tipicamente el 0 sembrado de
    # medianoche, ver Add-MedianocheCero): un 0 alli es real, y permite que el grafico
    # exista con una sola muestra posterior (2 puntos: 00:00=0 -> ahora=X).
    if ([double]$ordenada[0].precip -eq 0) {
        $tiempos.Add([int64]$ordenada[0].epoch); $valores.Add(0.0)
    }
    for ($i = 1; $i -lt $ordenada.Count; $i++) {
        $delta = [double]$ordenada[$i].precip - [double]$ordenada[$i - 1].precip
        if ($delta -lt 0) { $delta = [double]$ordenada[$i].precip }   # reset de medianoche
        $tiempos.Add([int64]$ordenada[$i].epoch)
        $valores.Add([math]::Round($delta, 2))
    }
    return @{ Tiempos = $tiempos.ToArray(); Valores = $valores.ToArray() }
}

# Agrega una muestra nueva a la historia y descarta las mas viejas que $VentanaHoras
# (margen sobre 48h para que el grafico de 48h siempre tenga cobertura completa).
function Add-MuestraHistoria {
    param([array]$Historia, [long]$Epoch, $Precip, [long]$AhoraEpoch, [double]$VentanaHoras = 50.0)
    $nueva = @($Historia | Where-Object { ($AhoraEpoch - [int64]$_.epoch) -le ($VentanaHoras * 3600) })
    if ($null -ne $Precip) { $nueva += @{ epoch = $Epoch; precip = $Precip } }
    # operador coma: sin esto, PowerShell desenvuelve un array de 1 elemento al salir de
    # la funcion y el llamador recibe el hashtable suelto en vez de un array de 1 hashtable
    # (mismo patron del gotcha #11 ya documentado, pero en un "return" en vez de un pipeline)
    return ,$nueva
}

function Read-EstadoDmc {
    param([string]$Path)
    $estado = @{}
    if (Test-Path $Path) {
        try {
            $obj = Get-Content $Path -Raw | ConvertFrom-Json
            foreach ($p in $obj.PSObject.Properties) {
                $historia = @()
                if ($p.Value.PSObject.Properties['historia']) {
                    $historia = @($p.Value.historia | ForEach-Object {
                        @{ epoch = [int64]$_.epoch; precip = [double]$_.precip }
                    })
                }
                $estado[$p.Name] = @{ precip = [double]$p.Value.precip; epoch = [int64]$p.Value.epoch; historia = $historia }
            }
        } catch { Write-Warning "Cache estado DMC ilegible, se reinicia: $_" }
    }
    return $estado
}

function Save-EstadoDmc {
    param([string]$Path, [hashtable]$Estado)
    try {
        $ordenado = [ordered]@{}
        foreach ($k in ($Estado.Keys | Sort-Object)) { $ordenado[$k] = $Estado[$k] }
        $tmp = "$Path.tmp"
        ($ordenado | ConvertTo-Json -Depth 6) | Set-Content -Path $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $Path -Force
    } catch { Write-Warning "No se pudo guardar estado DMC: $_" }
}

# Orquesta el scraping de todas las EMAs DMC y arma ambas formas de salida que el resto
# del pipeline ya entiende: .Redes (esquema de Parse-RedesJson, Capa 1) y .Emas (esquema
# de Parse-EmasDmcJson, Capa 2) - asi Build-Kml no necesita cambios.
function Get-EstacionesDmcDirecto {
    param(
        [array]$Codigos,
        [hashtable]$EstadoPrev = @{},
        [int]$ThrottleMs = 400,
        [int]$TimeoutSeg = 30,
        [string]$UserAgent = 'alertas-redes/1.0 (uso institucional SERNAGEOMIN; geologia)'
    )
    $redes = [System.Collections.Generic.List[object]]::new()
    $emas  = [System.Collections.Generic.List[object]]::new()
    $estadoNuevo = @{}
    $ok = 0; $fallidas = 0
    $ahoraEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $fechaChileHoy = Get-FechaChileDeEpoch $ahoraEpoch
    $medianocheEpoch = Get-EpochMedianocheChile $fechaChileHoy

    foreach ($cod in $Codigos) {
        $codStr = [string]$cod
        try {
            $url  = "https://climatologia.meteochile.gob.cl/application/diariob/visorDeDatosEma/$codStr"
            $html = Get-DmcHtmlGzip -Url $url -TimeoutSeg $TimeoutSeg -UserAgent $UserAgent

            $info  = Get-EmaInfoDirecto -Html $html
            $temp  = Get-EmaTempActualDirecto -Html $html
            $precH = Get-EmaPrecipHoyDirecto -Html $html
            if ($null -eq $precH) {
                # La celda "Agua caida / Hoy" a veces viene vacia o en regeneracion
                # (ventana matinal del sitio DMC) -> un reintento corto por estacion
                Start-Sleep -Milliseconds 1200
                $html2 = Get-DmcHtmlGzip -Url $url -TimeoutSeg $TimeoutSeg -UserAgent $UserAgent
                $p2 = Get-EmaPrecipHoyDirecto -Html $html2
                if ($null -ne $p2) {
                    $html = $html2; $precH = $p2
                    $info = Get-EmaInfoDirecto -Html $html2
                    $temp = Get-EmaTempActualDirecto -Html $html2
                }
            }

            if ($null -eq $info.Lat -or $null -eq $info.Lon) { $fallidas++; continue }

            $ultimoEpoch = ConvertTo-EpochChile $info.UltimoDato
            if ($null -eq $ultimoEpoch) { $ultimoEpoch = $ahoraEpoch }

            $prevEntry = $EstadoPrev[$codStr]
            $tasa = $null
            if ($prevEntry -and $null -ne $precH) {
                $tasa = Get-PrecipRateDirecto -PrecipActual $precH -EpochActual $ultimoEpoch `
                    -PrecipPrev $prevEntry.precip -EpochPrev $prevEntry.epoch
            }
            $tasaFinal = if ($null -ne $tasa) { $tasa } else { 0.0 }

            $iso = if ($null -ne $temp -and $null -ne $info.Altitud) {
                [int][math]::Floor($info.Altitud + ($temp / 6.5) * 1000)
            } else { $null }

            $acumuladoHoy = Get-AcumuladoHonesto -PrecipHoy $precH -PrevEntry $prevEntry -FechaChileHoy $fechaChileHoy

            $historiaPrev  = if ($prevEntry -and $prevEntry.historia) { $prevEntry.historia } else { @() }
            if ($null -ne $precH) { $historiaPrev = Add-MedianocheCero -Historia $historiaPrev -MedianocheEpoch $medianocheEpoch }
            $historiaNueva = Add-MuestraHistoria -Historia $historiaPrev -Epoch $ultimoEpoch -Precip $precH -AhoraEpoch $ahoraEpoch
            $serie = Get-SerieDesdeHistoria $historiaNueva

            $redes.Add([PSCustomObject]@{
                Id = $null; Nombre = $info.Nombre; Codigo = $codStr
                Lat = $info.Lat; Lon = $info.Lon
                TasaMmH = $tasaFinal; Epoch = $ultimoEpoch; UltimoDatoEpoch = $ultimoEpoch
                OrgConfirmada = 'DMC directo'; Red = 'DMC'
                AcumuladoHoy = $acumuladoHoy
                ValoresSerie = $serie.Valores; TiemposSerie = $serie.Tiempos
            })

            $emas.Add([PSCustomObject]@{
                Id = $null; Nombre = $info.Nombre; Codigo = $codStr
                Lat = $info.Lat; Lon = $info.Lon; Altitud = $info.Altitud
                TasaMmH = $tasaFinal; TempC = $temp; Isoterma = $iso
                Epoch = $ultimoEpoch; UltimoDatoEpoch = $ultimoEpoch
                OrgConfirmada = 'DMC directo'
                AcumuladoHoy = $acumuladoHoy
                ValoresPrecip = $serie.Valores; ValoresTemp = @(); ValoresIso = @(); TiemposSerie = $serie.Tiempos
            })

            if ($null -ne $precH) {
                $estadoNuevo[$codStr] = @{ precip = $precH; epoch = $ultimoEpoch; historia = $historiaNueva }
            } elseif ($prevEntry) {
                $estadoNuevo[$codStr] = $prevEntry
            }
            $ok++
        } catch {
            $fallidas++
            Write-Warning "DMC directo, estacion $codStr : $_"
        }
        Start-Sleep -Milliseconds $ThrottleMs
    }

    return [PSCustomObject]@{
        Redes = $redes.ToArray(); Emas = $emas.ToArray()
        EstadoNuevo = $estadoNuevo; Ok = $ok; Fallidas = $fallidas
    }
}
