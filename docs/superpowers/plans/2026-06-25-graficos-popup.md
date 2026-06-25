# Gráficos Popup por Estación — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agregar gráfico histórico (quickchart.io) en el popup KML de cada estación — barras de precip para todas las redes, más líneas de temp/isoterma para EMAs DMC.

**Architecture:** `Parse-RedesJson` pasa a retener los arrays `values[]`/`timestamps[]` completos. `Get-EmasDmc` reemplaza la llamada `raw-measure/type/2/last` por el endpoint ventana tipo 2 (mantiene altitud desde tipo 1). Nueva función `Build-ChartUrl` genera URL de quickchart.io a partir de los arrays; `Build-PlacemarkRedes` y `Build-PlacemarkEmas` incrustan `<img src="...">` en el CDATA cuando hay 2+ puntos.

**Tech Stack:** PowerShell 5.1, Pester 3.4, quickchart.io (Chart.js vía URL GET)

---

### Task 1: Parse-RedesJson — preservar ValoresSerie y TiemposSerie

**Files:**
- Modify: `src/RedesApi.ps1`
- Modify: `tests/RedesApi.Tests.ps1`

- [ ] **Agregar tests fallidos para ValoresSerie y TiemposSerie**

Agregar al final del `Describe "Parse-RedesJson"` existente en `tests/RedesApi.Tests.ps1`:

```powershell
    It "preserva ValoresSerie completo" {
        $r = Parse-RedesJson $fixture
        $v = $r | Where-Object { $_.Codigo -eq '01000005-K' }
        $v.ValoresSerie.Count | Should Be 3
        $v.ValoresSerie[2]    | Should Be 3.2
    }
    It "preserva TiemposSerie completo" {
        $r = Parse-RedesJson $fixture
        $v = $r | Where-Object { $_.Codigo -eq '01000005-K' }
        $v.TiemposSerie.Count | Should Be 3
        $v.TiemposSerie[0]    | Should Be 1781794800
    }
```

- [ ] **Correr tests — verificar que fallan**

```
Invoke-Pester tests\RedesApi.Tests.ps1 -Verbose
```

Esperado: los 2 tests nuevos fallan con `The property 'ValoresSerie' cannot be found`.

- [ ] **Actualizar Parse-RedesJson en src/RedesApi.ps1**

Reemplazar el bloque del objeto resultado dentro de `Parse-RedesJson`:

```powershell
        $result += [PSCustomObject]@{
            Nombre       = $d.name
            Codigo       = $d.nationalCode
            Lat          = [double]$d.lat
            Lon          = [double]$d.lng
            TasaMmH      = $tasa
            Epoch        = $ultimoTs
            Red          = Get-RedFromCode $d.nationalCode
            ValoresSerie = if ($d.values)     { $d.values }     else { @() }
            TiemposSerie = if ($d.timestamps) { $d.timestamps } else { @() }
        }
```

- [ ] **Correr tests — verificar que pasan**

```
Invoke-Pester tests\RedesApi.Tests.ps1 -Verbose
```

Esperado: 23 passed, 0 failed.

- [ ] **Commit**

```
git add src/RedesApi.ps1 tests/RedesApi.Tests.ps1
git commit -m "feat: Parse-RedesJson preserva ValoresSerie y TiemposSerie"
```

---

### Task 2: Fixture temp_3h.json + reescribir Parse-EmasDmcJson

**Files:**
- Create: `tests/fixtures/temp_3h.json`
- Modify: `src/RedesApi.ps1`
- Modify: `tests/RedesApi.Tests.ps1`

- [ ] **Crear tests/fixtures/temp_3h.json**

```json
[
  {
    "id": 1,
    "name": "Visviri",
    "nationalCode": "01000005-K",
    "organizationName": "dmc",
    "lat": -17.595,
    "lng": -69.4831,
    "timestamps": [1781794800, 1781798400, 1781802000],
    "values": [12.0, 11.5, 10.8],
    "measureType": 2,
    "confidence": 0
  },
  {
    "id": 2,
    "name": "Arica Oficina",
    "nationalCode": "01001001-K",
    "organizationName": "dmc",
    "lat": -18.347,
    "lng": -70.338,
    "timestamps": [1781794800, 1781798400, 1781802000],
    "values": [null, null, null],
    "measureType": 2,
    "confidence": 0
  }
]
```

- [ ] **Reemplazar el Describe "Parse-EmasDmcJson" en tests/RedesApi.Tests.ps1**

Eliminar el bloque existente y reemplazarlo por:

```powershell
Describe "Parse-EmasDmcJson" {
    $redesFixture = Get-Content "$here\fixtures\redes_3h.json" -Raw | ConvertFrom-Json
    $precipSerie  = Parse-RedesJson $redesFixture
    $tempSerie    = Get-Content "$here\fixtures\temp_3h.json" -Raw | ConvertFrom-Json
    $altitudMap   = @{ '01000005-K' = 3800.0; '01001001-K' = 25.0; '02001001-K' = 2260.0 }

    It "extrae TasaMmH del ultimo no-nulo de ValoresSerie" {
        $r = Parse-EmasDmcJson $precipSerie $tempSerie $altitudMap
        ($r | Where-Object { $_.Codigo -eq '01000005-K' }).TasaMmH | Should Be 3.2
    }
    It "extrae TempC del ultimo no-nulo de tempSerie" {
        $r = Parse-EmasDmcJson $precipSerie $tempSerie $altitudMap
        ($r | Where-Object { $_.Codigo -eq '01000005-K' }).TempC | Should Be 10.8
    }
    It "calcula Isoterma correctamente" {
        # altitud=3800, temp=10.8 -> 3800 + floor((10.8/6.5)*1000) = 3800+1661 = 5461
        $r = Parse-EmasDmcJson $precipSerie $tempSerie $altitudMap
        ($r | Where-Object { $_.Codigo -eq '01000005-K' }).Isoterma | Should Be 5461
    }
    It "calcula ValoresIso por timestamp" {
        $r = Parse-EmasDmcJson $precipSerie $tempSerie $altitudMap
        $e = $r | Where-Object { $_.Codigo -eq '01000005-K' }
        $e.ValoresIso.Count | Should Be 3
        $e.ValoresIso[0]    | Should Be 5646
        $e.ValoresIso[2]    | Should Be 5461
    }
    It "TempC es null cuando todos los valores de temp son null" {
        $r = Parse-EmasDmcJson $precipSerie $tempSerie $altitudMap
        ($r | Where-Object { $_.Codigo -eq '01001001-K' }).TempC | Should BeNullOrEmpty
    }
    It "ValoresTemp vacio cuando no hay entrada en tempSerie" {
        $altSolo = @{ '02001001-K' = 2260.0 }
        $soloCalama = $precipSerie | Where-Object { $_.Codigo -eq '02001001-K' }
        $r = Parse-EmasDmcJson @($soloCalama) @() $altSolo
        ($r | Where-Object { $_.Codigo -eq '02001001-K' }).ValoresTemp.Count | Should Be 0
    }
}
```

- [ ] **Correr tests — verificar que fallan**

```
Invoke-Pester tests\RedesApi.Tests.ps1 -Verbose
```

Esperado: los 6 tests nuevos de `Parse-EmasDmcJson` fallan.

- [ ] **Reescribir Parse-EmasDmcJson en src/RedesApi.ps1**

Reemplazar la función completa:

```powershell
function Parse-EmasDmcJson([array]$precipSerie, [array]$tempSerie, [hashtable]$altitudMap) {
    $tempIdx = @{}
    foreach ($t in $tempSerie) { $tempIdx[$t.nationalCode] = $t }

    $result = @()
    foreach ($s in $precipSerie) {
        $alt  = $altitudMap[$s.Codigo]
        $tObj = $tempIdx[$s.Codigo]

        $tempC = $null
        if ($tObj -and $tObj.values) {
            for ($i = $tObj.values.Count - 1; $i -ge 0; $i--) {
                if ($null -ne $tObj.values[$i]) { $tempC = [double]$tObj.values[$i]; break }
            }
        }

        $iso = $null
        if ($null -ne $tempC -and $null -ne $alt) {
            $iso = [int][math]::Floor($alt + ($tempC / 6.5) * 1000)
        }

        $tempByEpoch = @{}
        if ($tObj -and $tObj.timestamps -and $tObj.values) {
            for ($i = 0; $i -lt $tObj.timestamps.Count; $i++) {
                $tempByEpoch[$tObj.timestamps[$i]] = $tObj.values[$i]
            }
        }

        $valoresTemp = [System.Collections.ArrayList]::new()
        $valoresIso  = [System.Collections.ArrayList]::new()
        foreach ($ts in $s.TiemposSerie) {
            $tv = $tempByEpoch[$ts]
            if ($null -ne $tv) {
                [void]$valoresTemp.Add([double]$tv)
                [void]$valoresIso.Add(if ($null -ne $alt) { [int][math]::Floor($alt + ([double]$tv / 6.5) * 1000) } else { $null })
            } else {
                [void]$valoresTemp.Add($null)
                [void]$valoresIso.Add($null)
            }
        }

        $result += [PSCustomObject]@{
            Nombre        = $s.Nombre
            Codigo        = $s.Codigo
            Lat           = $s.Lat
            Lon           = $s.Lon
            Altitud       = $alt
            TasaMmH       = $s.TasaMmH
            TempC         = $tempC
            Isoterma      = $iso
            Epoch         = $s.Epoch
            ValoresPrecip = $s.ValoresSerie
            ValoresTemp   = $valoresTemp.ToArray()
            ValoresIso    = $valoresIso.ToArray()
            TiemposSerie  = $s.TiemposSerie
        }
    }
    return $result
}
```

- [ ] **Correr tests — verificar que pasan**

```
Invoke-Pester tests\RedesApi.Tests.ps1 -Verbose
```

Esperado: 27 passed, 0 failed.

- [ ] **Commit**

```
git add src/RedesApi.ps1 tests/RedesApi.Tests.ps1 tests/fixtures/temp_3h.json
git commit -m "feat: Parse-EmasDmcJson nueva firma con serie temp e isoterma por timestamp"
```

---

### Task 3: Actualizar Get-EmasDmc y Actualizar.ps1

**Files:**
- Modify: `src/RedesApi.ps1`
- Modify: `Actualizar.ps1`

No hay tests unitarios para funciones de red; se verifica manualmente al final.

- [ ] **Reemplazar Get-EmasDmc en src/RedesApi.ps1**

```powershell
function Get-EmasDmc([array]$redesData) {
    $rutaP = "api/raw-measure/by-measure-type/1/last"
    $rP = Invoke-WebRequest -Uri "https://vismet.cr2.cl/$rutaP" `
        -Headers @{ckey = (Sign $rutaP)} -UseBasicParsing -TimeoutSec 60
    if ($rP.Content -match '<!DOCTYPE') { throw "API devolvio HTML (precip raw)" }
    $precipRaw = $rP.Content | ConvertFrom-Json

    $altitudMap = @{}
    foreach ($p in $precipRaw) { $altitudMap[$p.station.nationalCode] = $p.station.altitude }

    $epoch = Get-EpochHora
    $rutaT = "api/measure/by-measure-type/2/by-timestamp/$epoch/by-interval/3"
    $tempSerie = @()
    try {
        $rT = Invoke-WebRequest -Uri "https://vismet.cr2.cl/$rutaT" `
            -Headers @{ckey = (Sign $rutaT)} -UseBasicParsing -TimeoutSec 90
        if ($rT.Content -notmatch '<!DOCTYPE') {
            $tempSerie = $rT.Content | ConvertFrom-Json
        }
    } catch {
        Write-Warning "Serie temperatura no disponible (se omite grafico temp): $_"
    }

    $precipSerie = @($redesData | Where-Object { $altitudMap.ContainsKey($_.Codigo) })
    return Parse-EmasDmcJson $precipSerie $tempSerie $altitudMap
}
```

- [ ] **Actualizar Actualizar.ps1 — pasar $redes a Get-EmasDmc**

Cambiar la línea:

```powershell
    $emas = Get-EmasDmc
```

por:

```powershell
    $emas = Get-EmasDmc $redes
```

- [ ] **Correr todos los tests para verificar que no se rompió nada**

```
Invoke-Pester tests\RedesApi.Tests.ps1 -Verbose
Invoke-Pester tests\AlertasKml.Tests.ps1 -Verbose
```

Esperado: 27 + 17 = 44 passed, 0 failed.

- [ ] **Commit**

```
git add src/RedesApi.ps1 Actualizar.ps1
git commit -m "feat: Get-EmasDmc usa endpoint windowed tipo 2 para serie de temperatura"
```

---

### Task 4: Build-ChartUrl

**Files:**
- Modify: `src/AlertasKml.ps1`
- Modify: `tests/AlertasKml.Tests.ps1`

- [ ] **Agregar tests fallidos al final de tests/AlertasKml.Tests.ps1**

```powershell
Describe "Build-ChartUrl" {
    $tiempos = @(1781794800, 1781798400, 1781802000)
    $precip  = @(0.0, 3.2, 7.5)
    $temp    = @(12.0, 11.5, 10.8)
    $iso     = @(5646, 5569, 5461)

    It "retorna URL de quickchart.io" {
        Build-ChartUrl $tiempos $precip | Should Match 'quickchart\.io'
    }
    It "con solo precip no incluye Temp ni Isoterma" {
        $url = Build-ChartUrl $tiempos $precip
        $url | Should Not Match 'Temp'
        $url | Should Not Match 'Isoterma'
    }
    It "con temp incluye dataset Temp C" {
        Build-ChartUrl $tiempos $precip $temp | Should Match 'Temp'
    }
    It "con iso incluye dataset Isoterma km" {
        Build-ChartUrl $tiempos $precip $temp $iso | Should Match 'Isoterma'
    }
    It "retorna cadena vacia cuando hay menos de 2 puntos" {
        Build-ChartUrl @(1781794800) @(0.0) | Should Be ''
    }
}
```

- [ ] **Correr tests — verificar que fallan**

```
Invoke-Pester tests\AlertasKml.Tests.ps1 -Verbose
```

Esperado: los 5 tests de `Build-ChartUrl` fallan con `Build-ChartUrl is not recognized`.

- [ ] **Agregar Build-ChartUrl al inicio de src/AlertasKml.ps1 (antes de Get-ColorRedes)**

```powershell
function Build-ChartUrl([array]$tiempos, [array]$precip, [array]$temp = @(), [array]$iso = @()) {
    if ($tiempos.Count -lt 2) { return '' }

    $labels = @($tiempos | ForEach-Object {
        [DateTimeOffset]::FromUnixTimeSeconds([long]$_).ToLocalTime().ToString('HH:mm')
    })

    $ds = [System.Collections.Generic.List[hashtable]]::new()
    $ds.Add(@{
        type='bar'; label='Precip mm/h'; data=$precip
        backgroundColor='rgba(55,138,221,0.7)'; yAxisID='yP'; order=2
    })

    if ($temp.Count -gt 0) {
        $ds.Add(@{
            type='line'; label='Temp C'; data=$temp
            borderColor='#E24B4A'; borderWidth=2; pointRadius=2; tension=0.3; yAxisID='yR'; order=1
        })
    }

    if ($iso.Count -gt 0) {
        $isoKm = @($iso | ForEach-Object {
            if ($null -ne $_) { [math]::Round([double]$_ / 1000.0, 2) } else { $null }
        })
        $ds.Add(@{
            type='line'; label='Isoterma km'; data=$isoKm
            borderColor='#EF9F27'; borderWidth=2; borderDash=@(4,3); pointRadius=2; tension=0.3; yAxisID='yR'; order=1
        })
        $ds.Add(@{
            type='line'; label='Umbral 3km'; data=@($tiempos | ForEach-Object { 3.0 })
            borderColor='rgba(162,45,45,0.4)'; borderWidth=1; borderDash=@(6,4); pointRadius=0; yAxisID='yR'; order=0
        })
    }

    $escalas = @{
        x  = @{ ticks = @{ font = @{ size = 10 } } }
        yP = @{ position='left';  title=@{ display=$true; text='mm/h' }; ticks=@{ font=@{ size=10 } } }
    }
    if ($temp.Count -gt 0 -or $iso.Count -gt 0) {
        $escalas['yR'] = @{
            position='right'; grid=@{ drawOnChartArea=$false }
            title=@{ display=$true; text='C/km' }; ticks=@{ font=@{ size=10 } }
        }
    }

    $cfg = @{
        type = 'bar'
        data = @{ labels=$labels; datasets=$ds.ToArray() }
        options = @{ plugins=@{ legend=@{ display=$false } }; scales=$escalas }
    }
    $json    = $cfg | ConvertTo-Json -Depth 15 -Compress
    $encoded = [Uri]::EscapeDataString($json)
    return "https://quickchart.io/chart?w=300&h=160&c=$encoded"
}

```

- [ ] **Correr tests — verificar que pasan**

```
Invoke-Pester tests\AlertasKml.Tests.ps1 -Verbose
```

Esperado: 22 passed, 0 failed.

- [ ] **Commit**

```
git add src/AlertasKml.ps1 tests/AlertasKml.Tests.ps1
git commit -m "feat: Build-ChartUrl genera URL quickchart.io con precip/temp/isoterma"
```

---

### Task 5: Actualizar Build-PlacemarkRedes y Build-PlacemarkEmas

**Files:**
- Modify: `src/AlertasKml.ps1`
- Modify: `tests/AlertasKml.Tests.ps1`

- [ ] **Agregar tests fallidos al final de tests/AlertasKml.Tests.ps1**

```powershell
Describe "Build-PlacemarkRedes con serie" {
    It "incluye img cuando ValoresSerie tiene 2+ puntos" {
        $e = [PSCustomObject]@{
            Nombre='Visviri'; Codigo='01K'; Lat=-17.5; Lon=-69.4
            TasaMmH=3.2; Epoch=1781802000; Red='DGA/DMC'
            ValoresSerie=@(0.0,1.5,3.2); TiemposSerie=@(1781794800,1781798400,1781802000)
        }
        Build-PlacemarkRedes $e | Should Match '<img'
    }
    It "no incluye img cuando ValoresSerie tiene 1 punto" {
        $e = [PSCustomObject]@{
            Nombre='Visviri'; Codigo='01K'; Lat=-17.5; Lon=-69.4
            TasaMmH=3.2; Epoch=1781802000; Red='DGA/DMC'
            ValoresSerie=@(3.2); TiemposSerie=@(1781802000)
        }
        Build-PlacemarkRedes $e | Should Not Match '<img'
    }
}

Describe "Build-PlacemarkEmas con serie" {
    It "incluye img con temp e iso cuando TiemposSerie tiene 2+ puntos" {
        $e = [PSCustomObject]@{
            Nombre='El Paico'; Codigo='330113'; Lat=-33.7; Lon=-71.0
            Altitud=275.0; TasaMmH=6.5; TempC=8.0; Isoterma=1505; Epoch=1781807400
            ValoresPrecip=@(3.0,5.5,6.5); ValoresTemp=@(9.0,8.5,8.0)
            ValoresIso=@(1659,1582,1505)
            TiemposSerie=@(1781794800,1781798400,1781802000)
        }
        Build-PlacemarkEmas $e | Should Match '<img'
    }
}
```

- [ ] **Correr tests — verificar que fallan**

```
Invoke-Pester tests\AlertasKml.Tests.ps1 -Verbose
```

Esperado: 3 tests nuevos fallan.

- [ ] **Actualizar Build-PlacemarkRedes en src/AlertasKml.ps1**

Reemplazar la función completa:

```powershell
function Build-PlacemarkRedes($e) {
    $color = Get-ColorRedes $e.TasaMmH
    $hora  = Format-Epoch $e.Epoch
    $chartImg = ''
    if ($e.ValoresSerie -and $e.ValoresSerie.Count -ge 2) {
        $url = Build-ChartUrl $e.TiemposSerie $e.ValoresSerie
        if ($url) { $chartImg = "<br/><small>Precip (mm/h)</small><br/><img src='$url' width='300'/>" }
    }
    $desc = "<![CDATA[<b>$($e.Nombre)</b><br/>Red: $($e.Red)<br/>Precip: $($e.TasaMmH) mm/h<br/>Dato: $hora$chartImg]]>"
    return @"
    <Placemark>
      <name>$($e.Nombre) - $($e.TasaMmH) mm/h</name>
      <styleUrl>#$color</styleUrl>
      <description>$desc</description>
      <Point><coordinates>$($e.Lon),$($e.Lat),0</coordinates></Point>
    </Placemark>
"@
}
```

- [ ] **Actualizar Build-PlacemarkEmas en src/AlertasKml.ps1**

Reemplazar la función completa:

```powershell
function Build-PlacemarkEmas($e) {
    $color   = Get-ColorEmas $e.TasaMmH $e.Isoterma
    $hora    = Format-Epoch $e.Epoch
    $isoStr  = if ($null -ne $e.Isoterma) { "$($e.Isoterma) m" } else { 'sin dato' }
    $tempStr = if ($null -ne $e.TempC)    { "$($e.TempC) grados C" } else { 'sin dato' }
    $chartImg = ''
    if ($e.TiemposSerie -and $e.TiemposSerie.Count -ge 2) {
        $url = Build-ChartUrl $e.TiemposSerie $e.ValoresPrecip $e.ValoresTemp $e.ValoresIso
        if ($url) { $chartImg = "<br/><small>Precip mm/h | Temp C | Isoterma km</small><br/><img src='$url' width='300'/>" }
    }
    $desc = "<![CDATA[<b>$($e.Nombre)</b><br/>Precip: $($e.TasaMmH) mm/h<br/>Temp: $tempStr<br/>Isoterma 0C: $isoStr<br/>Altitud: $($e.Altitud) m<br/>Dato: $hora$chartImg]]>"
    return @"
    <Placemark>
      <name>$($e.Nombre) - $($e.TasaMmH) mm/h</name>
      <styleUrl>#$color</styleUrl>
      <description>$desc</description>
      <Point><coordinates>$($e.Lon),$($e.Lat),0</coordinates></Point>
    </Placemark>
"@
}
```

- [ ] **Correr todos los tests**

```
Invoke-Pester tests\RedesApi.Tests.ps1 -Verbose
Invoke-Pester tests\AlertasKml.Tests.ps1 -Verbose
```

Esperado: 27 + 25 = 52 passed, 0 failed.

- [ ] **Commit**

```
git add src/AlertasKml.ps1 tests/AlertasKml.Tests.ps1
git commit -m "feat: incrustar grafico quickchart.io en popup de cada estacion"
```

---

### Task 6: Integración — generar KML, verificar popup, push

**Files:**
- No changes — solo verificación y publicación.

- [ ] **Correr Actualizar.ps1**

```
powershell -NoProfile -ExecutionPolicy Bypass -File Actualizar.ps1
```

Esperado: salida similar a:
```
[HH:mm:ss] Consultando DMC/DGA/Agromet (todas las redes)...
  -> 1276 estaciones
[HH:mm:ss] Consultando EMAs DMC...
  -> 105 estaciones
[HH:mm:ss] KML escrito: ...\red_alertas.kml
```

Si `Get-EmasDmc` falla (endpoint tipo 2 no disponible): el script reporta warning y `$emas = @()`. El KML se genera igual con solo Capa 1.

- [ ] **Verificar que el KML contiene URLs de quickchart.io**

```
Select-String -Path red_alertas.kml -Pattern 'quickchart' | Select-Object -First 3
```

Esperado: al menos 1 match con `quickchart.io/chart?w=300`.

- [ ] **Generar KMZ online**

```
powershell -NoProfile -ExecutionPolicy Bypass -File Crear-KMZ.ps1 -Online
```

- [ ] **Push código y datos**

```
git add src/RedesApi.ps1 src/AlertasKml.ps1 tests/RedesApi.Tests.ps1 tests/AlertasKml.Tests.ps1 tests/fixtures/temp_3h.json Actualizar.ps1
git status
git push origin master:main
```

Publicar KML actualizado a rama `live`:

```powershell
git stash -- red_alertas.kml
git checkout --orphan live-pub
git rm -rf --cached . 2>$null
Remove-Item .gitignore -ErrorAction SilentlyContinue
git stash pop
git add red_alertas.kml
git commit -m "data: red_alertas.kml con graficos quickchart"
git push origin HEAD:live --force
git checkout master
```

- [ ] **Abrir alertas-redes-online.kmz en Google Earth y verificar**

Hacer clic en cualquier estación → debe aparecer el popup con gráfico de barras de precipitación. Para EMAs DMC debe mostrar además las líneas de temperatura e isoterma.
