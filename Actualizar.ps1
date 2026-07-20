$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Path -Parent }
. "$here\src\RedesApi.ps1"
. "$here\src\DmcDirecto.ps1"
. "$here\src\RedesRegionalesDmc.ps1"
. "$here\src\RedMeteoDirecto.ps1"
. "$here\src\UmbralesRegionales.ps1"
. "$here\src\AlertasKml.ps1"
. "$here\src\PronosticoApi.ps1"
. "$here\src\SismosApi.ps1"
. "$here\src\Notificaciones.ps1"

$kmlPath            = "$here\red_alertas.kml"
$kmlPronostico      = "$here\red_pronostico.kml"
$kmlSismos          = "$here\red_sismos.kml"
$estadoDmcPath      = "$here\dmc_estado.json"
$estadoRachaPath    = "$here\racha_lluvia.json"
$estadoRegPath      = "$here\redes_regionales_estado.json"
$estadoRedMeteoPath = "$here\redmeteo_estado.json"
$alertasDiariasPath = "$here\alertas_diarias.json"

# vismet.cr2.cl (DGA/Agromet/CEAZA/UFRO/Davis) -- se excluye DMC de aqui: se
# verifico 2026-07-08 que vismet devuelve 0.0 fijo para TODA la red DMC (y tambien DGA)
# mientras el portal publico de la DMC muestra lluvia real para las mismas estaciones.
# DGA sigue viniendo de vismet (no tiene fuente directa sin CAPTCHA, ver DGASAT en memoria);
# DMC se reemplaza integramente por scraping directo mas abajo.
# RedMeteo TAMBIEN se excluye de vismet (2026-07-17): vismet devuelve 0.0 fijo para las 66
# estaciones de la red en toda la ventana de 48h (verificado con la API real durante un
# temporal en que Agromet/INIA/DMC vecinas marcaban 50-296 mm/dia) — mismo patron del feed
# roto de DMC. La red se reintegra mas abajo desde su fuente DIRECTA (liveupdate.php, ver
# RedMeteoDirecto.ps1 y la seccion RedMeteo del CLAUDE.md).
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Consultando DGA/Agromet/CEAZA (vismet, sin DMC ni RedMeteo)..." -ForegroundColor Cyan
$fechaHoy = Get-FechaChile
try {
    $redesVismet = @(Get-AllRedes | Where-Object { $_.Red -ne 'DMC' -and $_.Red -ne 'RedMeteo' })
    foreach ($e in $redesVismet) {
        $acum = Get-AcumuladoCalendario $e.TiemposSerie $e.ValoresSerie $fechaHoy
        Add-Member -InputObject $e -NotePropertyName AcumuladoHoy -NotePropertyValue $acum -Force
    }
    Write-Host "  -> $($redesVismet.Count) estaciones" -ForegroundColor Gray
} catch {
    Write-Warning "Error en vismet (DGA/Agromet/CEAZA): $_"
    $redesVismet = @()
}

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Consultando DMC directo (climatologia.meteochile.gob.cl)..." -ForegroundColor Cyan
$redesDmc = @(); $emas = @()
try {
    $codigosDmc    = Get-CodigosEmaDmc
    $estadoPrevDmc = Read-EstadoDmc $estadoDmcPath
    $resultDmc     = Get-EstacionesDmcDirecto -Codigos $codigosDmc -EstadoPrev $estadoPrevDmc
    Save-EstadoDmc $estadoDmcPath $resultDmc.EstadoNuevo
    $redesDmc = $resultDmc.Redes
    $emas     = $resultDmc.Emas
    Write-Host "  -> $($resultDmc.Ok) EMAs DMC ok, $($resultDmc.Fallidas) fallidas" -ForegroundColor Gray
} catch {
    Write-Warning "Error en DMC directo: $_"
}

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Consultando INIA/FDF/ESO/INACH (boletin regional DMC, 16 regiones)..." -ForegroundColor Cyan
$redesRegionales = @()
try {
    $codigosRegionales = Get-CodigosRedesRegionales -FechaChile $fechaHoy
    Write-Host "  -> $($codigosRegionales.Count) estaciones no-DMC encontradas en los boletines" -ForegroundColor Gray
    $estadoPrevReg = Read-EstadoDmc $estadoRegPath
    $resultReg     = Get-EstacionesRegionalesDirecto -Estaciones $codigosRegionales -EstadoPrev $estadoPrevReg
    Save-EstadoDmc $estadoRegPath $resultReg.EstadoNuevo
    $redesRegionales = $resultReg.Redes
    Write-Host "  -> $($resultReg.Ok) ok, $($resultReg.Fallidas) fallidas" -ForegroundColor Gray
} catch {
    Write-Warning "Error en redes regionales (INIA/FDF/ESO/INACH): $_"
}

# RedMeteo directo (redmeteo.cl/liveupdate.php, el JSON del mapa publico de su home):
# 1 solo request (~75 KB) por ciclo; los datos se sirven en espejo desde nuestro KML,
# como pide su politica de uso; atribucion visible como Red: RedMeteo en el visor.
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Consultando RedMeteo directo (redmeteo.cl)..." -ForegroundColor Cyan
$redesRedMeteo = @()
try {
    $obsRm         = Get-RedMeteoLive
    $estadoPrevRm  = Read-EstadoDmc $estadoRedMeteoPath
    $resultRm      = Get-EstacionesRedMeteoDirecto -Observaciones $obsRm -EstadoPrev $estadoPrevRm -FechaChile $fechaHoy
    Save-EstadoDmc $estadoRedMeteoPath $resultRm.EstadoNuevo
    $redesRedMeteo = $resultRm.Redes
    Write-Host "  -> $($resultRm.Ok) estaciones RedMeteo ok, $($resultRm.Descartadas) descartadas" -ForegroundColor Gray
} catch {
    Write-Warning "Error en RedMeteo directo (no bloqueante): $_"
}

$redes = @($redesVismet) + @($redesDmc) + @($redesRegionales) + @($redesRedMeteo)

# --- Umbrales regionales aviso/alerta/alarma (solo precipitacion, RM a Los Lagos) ---
# Reemplaza el color de Capa 1 (Get-ColorRedes 5/10 mm/h) para estaciones dentro de esas
# 8 regiones; fuera de tabla se mantiene el umbral simple sin cambios. NO toca las alertas
# EMA (precip+iso, Capa 2) ni el pronostico, que siguen igual que antes.
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Aplicando umbrales regionales (aviso/alerta/alarma)..." -ForegroundColor Cyan
try {
    $estadoRachaPrev  = Read-EstadoRacha $estadoRachaPath
    $estadoRachaNuevo = Add-InfoRegional -Estaciones $redes -EstadoPrev $estadoRachaPrev -FechaHoy $fechaHoy
    Save-EstadoRacha $estadoRachaPath $estadoRachaNuevo
    $conRegion = @($redes | Where-Object { $_.Region }).Count
    Write-Host "  -> $conRegion/$($redes.Count) estaciones con region asignada" -ForegroundColor Gray
} catch {
    Write-Warning "Error aplicando umbrales regionales (no bloqueante, cae al umbral simple): $_"
}

# --- Fuente/organizacion CONFIRMADA por vismet/CR2 (solo informativa, no reemplaza Get-RedFromCode) ---
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Consultando organizacion confirmada (raw-measure)..." -ForegroundColor Cyan
try {
    $nuevasOrg = Get-OrganizacionesRaw
    $orgMap    = Merge-OrganizacionCache "$here\organizaciones.json" $nuevasOrg
    Write-Host "  organizaciones: $($orgMap.Keys.Count) en cache (nuevas este ciclo: $($nuevasOrg.Keys.Count))" -ForegroundColor Gray

    $coinciden = 0; $difieren = 0
    foreach ($e in @($redes) + @($emas)) {
        if ($e.Id -and $orgMap.ContainsKey("$($e.Id)")) {
            $e.OrgConfirmada = $orgMap["$($e.Id)"]
            $heur = $e.Red
            if ($heur -and ($e.OrgConfirmada -match [regex]::Escape($heur) -or $heur -match [regex]::Escape($e.OrgConfirmada))) {
                $coinciden++
            } elseif ($heur) {
                $difieren++
                Write-Host "    DIFIERE: id=$($e.Id) '$($e.Nombre)' heuristica='$heur' vs confirmada='$($e.OrgConfirmada)'" -ForegroundColor Yellow
            }
        }
    }
    Write-Host "  comparacion heuristica vs confirmada: coinciden=$coinciden difieren=$difieren" -ForegroundColor Gray
} catch {
    Write-Warning "Error en organizacion confirmada (no bloqueante): $_"
}

if ($redes.Count -eq 0 -and $emas.Count -eq 0) {
    Write-Warning "Sin datos de ninguna fuente. Se mantiene el KML anterior."
    exit 1
}

$kml = Build-Kml $redes $emas
[System.IO.File]::WriteAllText($kmlPath, $kml, [System.Text.Encoding]::UTF8)

$alertasRedes = @($redes | Where-Object { (Get-ColorRedesFinal $_) -ne 'verde' }).Count
$alertasEmas  = @($emas  | Where-Object { (Get-ColorEmas $_.TasaMmH $_.Isoterma) -ne 'verde' }).Count

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] KML escrito: $kmlPath" -ForegroundColor Green
$redes | Group-Object Red | Sort-Object Count -Desc | ForEach-Object {
    Write-Host "    $($_.Name): $($_.Count) est." -ForegroundColor Gray
}
Write-Host "  Total: $($redes.Count) est. | $alertasRedes con precip>=5 mm/h" -ForegroundColor Yellow
Write-Host "  EMAs DMC:  $($emas.Count) est.  | $alertasEmas con alerta activa" -ForegroundColor Yellow

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Consultando pronostico (Open-Meteo grilla Chile)..." -ForegroundColor Cyan
try {
    $grilla       = Get-GrillaChile
    $allVentanas  = Get-PronosticoGrilla $grilla
    $kmlPron      = Build-PronosticoKml $allVentanas
    [System.IO.File]::WriteAllText($kmlPronostico, $kmlPron, [System.Text.Encoding]::UTF8)

    $alertasPron = @($allVentanas | Where-Object { $_.EstiloKml -ne 'verde' }).Count
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] KML pronostico escrito: $kmlPronostico" -ForegroundColor Green
    Write-Host "  Grilla: $($grilla.Count) pts | $alertasPron ventanas con alerta" -ForegroundColor Yellow
} catch {
    Write-Warning "Error en pronostico Open-Meteo: $_. Se mantiene el KML anterior."
}

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Consultando sismos (CSN + USGS)..." -ForegroundColor Cyan
$sismosCsn  = @()
$sismosUsgs = @()
try {
    $sismosCsn  = Get-SismosCSN
    $sismosUsgs = Get-SismosUSGS
    $kmlS = Build-SismosKml $sismosCsn $sismosUsgs
    [System.IO.File]::WriteAllText($kmlSismos, $kmlS, [System.Text.Encoding]::UTF8)
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] KML sismos escrito: $($sismosCsn.Count) CSN + $($sismosUsgs.Count) USGS" -ForegroundColor Green
} catch {
    Write-Warning "Error en sismos: $_. Se mantiene el KML anterior."
}

# --- Sistema de consolidacion diaria de alertas (Telegram) ---
$tgToken  = $env:TELEGRAM_TOKEN
$tgChatId = $env:TELEGRAM_CHAT_ID
if ($tgToken -and $tgChatId) {
    try {
        if ($env:PRUEBA -eq 'true') {
            # Modo prueba: enviar un mensaje de ejemplo con estaciones ficticias
            $demo = @(
                [pscustomobject]@{ Nombre = 'Demo Talca';   Red = 'DGA'; TasaMmH = 12.4; Lat = -35.42; Lon = -71.66 }
                [pscustomobject]@{ Nombre = 'Demo Chillan';  Red = 'DMC'; TasaMmH = 15.1; Lat = -36.61; Lon = -72.10 }
            )
            $msg = "🧪 PRUEBA (resumen diario)`n" + (Build-ResumenAlertas-Diario @{
                Dia = (Get-Date).ToString('yyyy-MM-dd')
                RegionalizadasRojas = $demo
                RegionalizadasAmarillas = @()
                EmasRojas = @()
                EmasAmarillas = @()
                VentanasRojas = @()
                VentanasAmarillas = @()
                SismosFuertes = @()
            })
            if (Send-TelegramMensaje $tgToken $tgChatId $msg) {
                Write-Host "  -> Mensaje de PRUEBA enviado." -ForegroundColor Green
            }
            return
        }

        # Leer estado diario previo y actualizar con datos actuales
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Actualizando consolidado diario de alertas..." -ForegroundColor Cyan
        $estadoActual = Read-AlertasDiarias $alertasDiariasPath
        $ventanasParaConsolidado = if ($null -ne $allVentanas) { $allVentanas } else { @() }
        $estadoNuevo = Update-EstadoAlertas $estadoActual $redes $emas $ventanasParaConsolidado

        # Registrar sismos M >= 6 en el estado
        $sismosTodos = @(); $sismosTodos += $sismosCsn; $sismosTodos += $sismosUsgs
        $sismosFuertes = @(Get-SismosFuertes $sismosTodos 6.0 90)
        if ($sismosFuertes.Count -gt 0) {
            $estadoNuevo.SismosFuertes = $sismosFuertes
        }

        # Guardar estado actualizado
        Save-AlertasDiarias $alertasDiariasPath $estadoNuevo

        # Decidir si enviar:
        # 1. Siempre: si hay sismos M >= 6 (alerta critica inmediata)
        # 2. Una vez al dia: si es la hora de envio (20:00 UTC = 16:00 hora Chile) y hay alertas
        $hayAlertasCriticas = $sismosFuertes.Count -gt 0
        $esHoraEnvio = Test-EsHoraEnvio
        $hayAlertasConsolidadas = $estadoNuevo.RegionalizadasRojas.Count -gt 0 -or
                                   $estadoNuevo.RegionalizadasAmarillas.Count -gt 0 -or
                                   $estadoNuevo.EmasRojas.Count -gt 0 -or
                                   $estadoNuevo.EmasAmarillas.Count -gt 0 -or
                                   $estadoNuevo.VentanasRojas.Count -gt 0 -or
                                   $estadoNuevo.VentanasAmarillas.Count -gt 0

        if ($hayAlertasCriticas) {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ALERTA CRITICA: Sismos M≥6 detectados." -ForegroundColor Red
            $msg = Build-AlertaSismo $sismosFuertes
            if ($msg -and (Send-TelegramMensaje $tgToken $tgChatId $msg)) {
                Write-Host "  -> Alerta crítica enviada inmediatamente." -ForegroundColor Green
            }
        } elseif ($esHoraEnvio -and $hayAlertasConsolidadas) {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Es hora de envio diario (20:00 UTC). Enviando consolidado..." -ForegroundColor Cyan
            $msg = Build-ResumenAlertas-Diario $estadoNuevo
            if ($msg -and (Send-TelegramMensaje $tgToken $tgChatId $msg)) {
                Write-Host "  -> Resumen diario enviado." -ForegroundColor Green
                $estadoNuevo.UltimoEnvio = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                Save-AlertasDiarias $alertasDiariasPath $estadoNuevo
            }
        } else {
            $proxHora = if ($esHoraEnvio) { "mañana" } else { "20:00 UTC ($([math]::Round((20 - (Get-Date).ToUniversalTime().Hour)) horas) horas)" }
            if ($hayAlertasConsolidadas) {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Alertas consolidadas. Proximo envio: $proxHora" -ForegroundColor Yellow
            } else {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Sin alertas consolidadas en el dia." -ForegroundColor Gray
            }
        }
    } catch {
        Write-Warning "Error en consolidado diario Telegram: $_"
    }
} else {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Telegram no configurado (sin secrets)." -ForegroundColor Gray
}
