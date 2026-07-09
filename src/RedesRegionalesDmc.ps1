# Estaciones NO-DMC del catalogo nacional de la DMC (INIA, FDF, ESO, INACH y otras) --
# descubiertas via el "Boletin Pluviometrico Regional" publico de climatologia.meteochile.gob.cl
# (menuTematicoEmas -> RE5015), que aunque se llama "DGA-DMC-INIA" en la practica NO incluye
# estaciones DGA (verificado: 0 en las 16 regiones) pero SI incluye INIA/FDF/ESO/INACH con
# codigo nacional -> se pueden scrapear con el MISMO endpoint visorDeDatosEma/{codigo} que
# ya usa DMC directo (confirmado con datos reales: estacion INIA 330026 "La Platina" trae
# nombre/altitud/lat/lon igual que una EMA DMC). Reutiliza toda la infra de src/DmcDirecto.ps1
# (debe cargarse ANTES que este archivo): Get-DmcHtmlGzip, Get-EmaInfoDirecto,
# Get-EmaPrecipHoyDirecto, ConvertTo-EpochChile, Get-PrecipRateDirecto, Add-MuestraHistoria,
# Get-SerieDesdeHistoria, Read-EstadoDmc, Save-EstadoDmc.
#
# Sin temperatura confiable en estas estaciones (son de red climatologica/agricola, no EMA
# automatica completa) -> no se agregan a Capa 2 (EMAs), solo a Capa 1 (Redes), con su propio
# nombre de red (Red = Propietario: INIA/FDF/ESO/INACH/...) para que Build-SubfoldersRedes
# las agrupe en su propia carpeta automaticamente (ya agrupa por Red sin cambios).

$script:RegionesBoletin = @('15','01','02','03','04','05','13','06','07','16','08','09','14','10','11','12')

# Parsea la tabla del boletin regional (codigo/nombre/provincia/comuna/propietario/diaria).
# El HTML real cierra la celda de propietario con </th> en vez de </td> (typo del sitio,
# no nuestro) -> regex tolera ambos.
function Get-EstacionesBoletinRegion {
    param([string]$Html)
    $tablaMatch = [regex]::Match($Html, '<table.*?</table>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $tablaMatch.Success) { return ,@() }
    $filas = $tablaMatch.Value -split '<tr>\s*<td class="text-center">' | Select-Object -Skip 1
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $filas) {
        $codigoM = [regex]::Match($f, '^\s*([\w-]+)')
        $nombreM = [regex]::Match($f, '<td>\s*([^<]*?)\s*</td>')
        $ownerM  = [regex]::Match($f, 'text-center">\s*([A-Z]+)\s*</t[hd]>')
        if ($codigoM.Success -and $ownerM.Success) {
            $out.Add([PSCustomObject]@{
                Codigo      = $codigoM.Groups[1].Value.Trim()
                Nombre      = if ($nombreM.Success) { $nombreM.Groups[1].Value.Trim() } else { '' }
                Propietario = $ownerM.Groups[1].Value.Trim()
            })
        }
    }
    return ,@($out.ToArray())
}

# Recorre las 16 regiones y arma la lista de estaciones NO-DMC (dedupe por codigo, por si
# el mismo codigo apareciera en mas de un boletin).
function Get-CodigosRedesRegionales {
    param(
        [string]$FechaChile,
        [array]$PropietariosExcluir = @('DMC'),
        [int]$ThrottleMs = 300,
        [int]$TimeoutSeg = 60
    )
    $partes = $FechaChile -split '-'
    $anio = $partes[0]; $mes = $partes[1]; $dia = $partes[2]
    $todas = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $script:RegionesBoletin) {
        try {
            $url = "https://climatologia.meteochile.gob.cl/application/diario/boletinPluviometricoAutomaticoRegional/$r/$anio/$mes/$dia"
            $resp = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec $TimeoutSeg
            foreach ($e in (Get-EstacionesBoletinRegion -Html $resp.Content)) {
                if ($PropietariosExcluir -notcontains $e.Propietario) { $todas.Add($e) }
            }
        } catch { Write-Warning "Boletin region $r no disponible: $_" }
        Start-Sleep -Milliseconds $ThrottleMs
    }
    $unicas = @($todas | Sort-Object Codigo -Unique)
    return ,@($unicas)
}

# Orquesta el scraping de las estaciones NO-DMC descubiertas. Mismo esquema de salida (Capa 1
# solamente) que Get-EstacionesDmcDirecto, reutilizando sus funciones internas.
function Get-EstacionesRegionalesDirecto {
    param(
        [array]$Estaciones,
        [hashtable]$EstadoPrev = @{},
        [int]$ThrottleMs = 400,
        [int]$TimeoutSeg = 30,
        [string]$UserAgent = 'alertas-redes/1.0 (uso institucional SERNAGEOMIN; geologia)'
    )
    $redes = [System.Collections.Generic.List[object]]::new()
    $estadoNuevo = @{}
    $ok = 0; $fallidas = 0
    $ahoraEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    foreach ($est in $Estaciones) {
        $codStr = [string]$est.Codigo
        try {
            $url  = "https://climatologia.meteochile.gob.cl/application/diariob/visorDeDatosEma/$codStr"
            $html = Get-DmcHtmlGzip -Url $url -TimeoutSeg $TimeoutSeg -UserAgent $UserAgent

            $info  = Get-EmaInfoDirecto -Html $html
            $precH = Get-EmaPrecipHoyDirecto -Html $html

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
            $acumuladoHoy = if ($null -ne $precH) { $precH } else { 0.0 }

            $historiaPrev  = if ($prevEntry -and $prevEntry.historia) { $prevEntry.historia } else { @() }
            $historiaNueva = Add-MuestraHistoria -Historia $historiaPrev -Epoch $ultimoEpoch -Precip $precH -AhoraEpoch $ahoraEpoch
            $serie = Get-SerieDesdeHistoria $historiaNueva

            $nombreFinal = if ($info.Nombre) { $info.Nombre } else { $est.Nombre }

            $redes.Add([PSCustomObject]@{
                Id = $null; Nombre = $nombreFinal; Codigo = $codStr
                Lat = $info.Lat; Lon = $info.Lon
                TasaMmH = $tasaFinal; Epoch = $ultimoEpoch; UltimoDatoEpoch = $ultimoEpoch
                OrgConfirmada = "$($est.Propietario) directo"; Red = $est.Propietario
                AcumuladoHoy = $acumuladoHoy
                ValoresSerie = $serie.Valores; TiemposSerie = $serie.Tiempos
            })

            if ($null -ne $precH) {
                $estadoNuevo[$codStr] = @{ precip = $precH; epoch = $ultimoEpoch; historia = $historiaNueva }
            } elseif ($prevEntry) {
                $estadoNuevo[$codStr] = $prevEntry
            }
            $ok++
        } catch {
            $fallidas++
            Write-Warning "Red regional directo, estacion $codStr : $_"
        }
        Start-Sleep -Milliseconds $ThrottleMs
    }

    return [PSCustomObject]@{
        Redes = $redes.ToArray()
        EstadoNuevo = $estadoNuevo; Ok = $ok; Fallidas = $fallidas
    }
}
