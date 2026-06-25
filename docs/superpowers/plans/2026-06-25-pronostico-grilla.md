# Pronóstico Grilla Chile — Plan de Implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agregar 4 capas de pronóstico meteorológico (grilla 1°, horizonte 48h, 3 modelos NWP con indicador de confianza) al proyecto alertas-redes, publicadas como `red_pronostico.kml` independiente de `red_alertas.kml`.

**Architecture:** Open-Meteo API (sin token) provee datos horarios de precipitación e isoterma 0°C para los modelos ECMWF IFS, GFS e ICON sobre ~150 puntos en Chile continental. Se calculan 4 ventanas incrementales (+0-6h, +6-12h, +12-24h, +24-48h); cada punto muestra el peor color entre modelos y cuántos coinciden. El resultado es un KML independiente publicado junto a `red_alertas.kml` en la rama `live`.

**Tech Stack:** PowerShell 5.1, Pester 3.4, Open-Meteo REST API (sin auth), KML/KMZ, GitHub Actions windows-latest.

**Spec:** `docs/superpowers/specs/2026-06-25-pronostico-grilla-design.md`

---

## Estructura de archivos

```
src/PronosticoApi.ps1           NUEVO  — Get-GrillaChile, Parse-OpenMeteoPoint,
                                         Get-SumaVentana, Get-MinVentana,
                                         Get-ColorPronostico, Get-EstiloPronostico,
                                         Build-VentanasPunto, Get-PronosticoGrilla
src/AlertasKml.ps1              MOD    — agregar Build-StylesPronostico,
                                         Build-PlacemarkPronostico,
                                         Build-PronosticoFolders, Build-PronosticoKml
tests/PronosticoApi.Tests.ps1   NUEVO  — tests para todas las funciones puras
tests/AlertasKml.Tests.ps1      MOD    — agregar tests para KML de pronóstico
tests/fixtures/openmeteo_2pts.json NUEVO — fixture respuesta Open-Meteo (2 pts, 48h, 3 modelos)
Actualizar.ps1                  MOD    — llamar PronosticoApi + escribir red_pronostico.kml
Crear-KMZ.ps1                   MOD    — doble NetworkLink en modo -Online
.gitignore                      MOD    — agregar red_pronostico.kml
.github/workflows/publicar.yml  MOD    — restaurar + publicar red_pronostico.kml
```

## Tipos de datos (referencia para todas las tareas)

**Ventana** — objeto devuelto por `Build-VentanasPunto` (4 por punto de grilla):
```powershell
[PSCustomObject]@{
    Nombre       = '+12 a 24h'   # '+0 a 6h' | '+6 a 12h' | '+12 a 24h' | '+24 a 48h'
    Lat          = [double]
    Lon          = [double]
    PrecipEcmwf  = [double]      # mm acumulados en la ventana
    PrecipGfs    = [double]
    PrecipIcon   = [double]
    IsoEcmwf     = [int]/[null]  # mínima isoterma en la ventana (null si todos los valores son null)
    IsoGfs       = [int]/[null]
    IsoIcon      = [int]/[null]
    ColorEcmwf   = 'verde'|'amarillo'|'rojo'
    ColorGfs     = 'verde'|'amarillo'|'rojo'
    ColorIcon    = 'verde'|'amarillo'|'rojo'
    ColorFinal   = 'verde'|'amarillo'|'rojo'   # peor color entre los 3
    NModelos     = [int]                        # cuántos coinciden en ColorFinal
    EstiloKml    = 'verde'|'amarillo_1'|...|'rojo_3'
}
```

**PuntoParseado** — salida de `Parse-OpenMeteoPoint`:
```powershell
[PSCustomObject]@{
    Lat                    = [double]
    Lon                    = [double]
    HourlyPrecipEcmwf      = [array]  # 48 valores double/null
    HourlyPrecipGfs        = [array]
    HourlyPrecipIcon       = [array]
    HourlyIsoEcmwf         = [array]  # 48 valores int/null
    HourlyIsoGfs           = [array]
    HourlyIsoIcon          = [array]
}
```

---

## Task 1: Fixture JSON + Get-GrillaChile

**Files:**
- Create: `tests/fixtures/openmeteo_2pts.json`
- Create: `src/PronosticoApi.ps1` (solo Get-GrillaChile por ahora)
- Create: `tests/PronosticoApi.Tests.ps1` (solo tests de grilla)

**Valores del fixture (para referencia en los tests):**

| Punto | Modelo | Ventana | Precip (mm) | Iso mínima (m) | Color esperado |
|---|---|---|---|---|---|
| 1 (-33.5,-70.5) | ECMWF | +0a6h | 0 | 3200 | verde |
| 1 | ECMWF | +6a12h | 7 | 3200 | amarillo |
| 1 | ECMWF | +12a24h | 26 | 3200 | rojo |
| 1 | ECMWF | +24a48h | 2 | 3200 | verde |
| 1 | GFS | +6a12h | 1 | 3100 | verde |
| 1 | GFS | +12a24h | 18 | 3100 | amarillo |
| 1 | ICON | +6a12h | 12 | 3400 | amarillo |
| 1 | ICON | +12a24h | 30 | 3400 | rojo |
| 1 | ICON | +0a6h | 0 | 3400 (null en idx 2) | verde |
| 2 (-45.0,-72.0) | todos | todas | 0 | 1500 | verde |

**Resultado de ventanas del punto 1:**
- +0 a 6h: verde (todos verdes) → EstiloKml = `verde`
- +6 a 12h: ECMWF=amarillo, GFS=verde, ICON=amarillo → ColorFinal=amarillo, N=2 → `amarillo_2`
- +12 a 24h: ECMWF=rojo, GFS=amarillo, ICON=rojo → ColorFinal=rojo, N=2 → `rojo_2`
- +24 a 48h: verde (todos verdes) → `verde`

- [ ] **Step 1: Crear fixture `tests/fixtures/openmeteo_2pts.json`**

```json
[
  {
    "latitude": -33.5,
    "longitude": -70.5,
    "hourly": {
      "time": [
        "T00","T01","T02","T03","T04","T05",
        "T06","T07","T08","T09","T10","T11",
        "T12","T13","T14","T15","T16","T17","T18","T19","T20","T21","T22","T23",
        "T24","T25","T26","T27","T28","T29","T30","T31","T32","T33","T34","T35",
        "T36","T37","T38","T39","T40","T41","T42","T43","T44","T45","T46","T47"
      ],
      "precipitation_ecmwf_ifs025":   [0,0,0,0,0,0, 1,2,1,1,1,1, 3,3,2,2,2,2,2,2,2,2,2,2, 0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
      "precipitation_gfs_seamless":   [0,0,0,0,0,0, 0,0,1,0,0,0, 2,2,1,1,2,2,1,1,2,2,1,1, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
      "precipitation_icon_seamless":  [0,0,0,0,0,0, 2,2,2,2,2,2, 3,3,2,2,3,3,2,2,3,3,2,2, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
      "freezing_level_height_ecmwf_ifs025":  [3200,3200,3200,3200,3200,3200, 3200,3200,3200,3200,3200,3200, 3200,3200,3200,3200,3200,3200,3200,3200,3200,3200,3200,3200, 3200,3200,3200,3200,3200,3200,3200,3200,3200,3200,3200,3200,3200,3200,3200,3200,3200,3200,3200,3200,3200,3200,3200,3200],
      "freezing_level_height_gfs_seamless":  [3100,3100,3100,3100,3100,3100, 3100,3100,3100,3100,3100,3100, 3100,3100,3100,3100,3100,3100,3100,3100,3100,3100,3100,3100, 3100,3100,3100,3100,3100,3100,3100,3100,3100,3100,3100,3100,3100,3100,3100,3100,3100,3100,3100,3100,3100,3100,3100,3100],
      "freezing_level_height_icon_seamless": [3400,3400,null,3400,3400,3400, 3400,3400,3400,3400,3400,3400, 3400,3400,3400,3400,3400,3400,3400,3400,3400,3400,3400,3400, 3400,3400,3400,3400,3400,3400,3400,3400,3400,3400,3400,3400,3400,3400,3400,3400,3400,3400,3400,3400,3400,3400,3400,3400]
    }
  },
  {
    "latitude": -45.0,
    "longitude": -72.0,
    "hourly": {
      "time": [
        "T00","T01","T02","T03","T04","T05",
        "T06","T07","T08","T09","T10","T11",
        "T12","T13","T14","T15","T16","T17","T18","T19","T20","T21","T22","T23",
        "T24","T25","T26","T27","T28","T29","T30","T31","T32","T33","T34","T35",
        "T36","T37","T38","T39","T40","T41","T42","T43","T44","T45","T46","T47"
      ],
      "precipitation_ecmwf_ifs025":   [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
      "precipitation_gfs_seamless":   [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
      "precipitation_icon_seamless":  [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
      "freezing_level_height_ecmwf_ifs025":  [1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500],
      "freezing_level_height_gfs_seamless":  [1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500],
      "freezing_level_height_icon_seamless": [1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500,1500]
    }
  }
]
```

- [ ] **Step 2: Crear `src/PronosticoApi.ps1` con Get-GrillaChile**

```powershell
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
```

- [ ] **Step 3: Crear `tests/PronosticoApi.Tests.ps1` con tests de grilla**

```powershell
$here = $PSScriptRoot
. "$here\..\src\PronosticoApi.ps1"

Describe "Get-GrillaChile" {
    $grilla = Get-GrillaChile

    It "devuelve mas de 50 puntos" {
        $grilla.Count | Should BeGreaterThan 50
    }
    It "todos los puntos tienen Lat y Lon" {
        $grilla | ForEach-Object {
            $_.Lat | Should Not BeNullOrEmpty
            $_.Lon | Should Not BeNullOrEmpty
        }
    }
    It "todas las latitudes dentro del rango de Chile" {
        $grilla | ForEach-Object {
            $_.Lat | Should BeGreaterThan -57.0
            $_.Lat | Should BeLessThan  -17.0
        }
    }
    It "todas las longitudes dentro del rango de Chile" {
        $grilla | ForEach-Object {
            $_.Lon | Should BeGreaterThan -78.0
            $_.Lon | Should BeLessThan  -66.0
        }
    }
    It "no hay puntos al este de Argentina (lon > -65)" {
        ($grilla | Where-Object { $_.Lon -gt -65 }).Count | Should Be 0
    }
}
```

- [ ] **Step 4: Ejecutar tests para verificar que pasan**

```powershell
# Ejecutar desde el directorio del proyecto
Invoke-Pester .\tests\PronosticoApi.Tests.ps1 -Verbose
```

Resultado esperado: **5 tests PASS**

- [ ] **Step 5: Commit**

```powershell
git add src/PronosticoApi.ps1 tests/PronosticoApi.Tests.ps1 tests/fixtures/openmeteo_2pts.json
git commit -m "feat: Get-GrillaChile + fixture Open-Meteo"
```

---

## Task 2: Parse-OpenMeteoPoint + Get-SumaVentana + Get-MinVentana

**Files:**
- Modify: `src/PronosticoApi.ps1` (agregar 3 funciones)
- Modify: `tests/PronosticoApi.Tests.ps1` (agregar tests)

- [ ] **Step 1: Agregar las 3 funciones al final de `src/PronosticoApi.ps1`**

```powershell
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
```

- [ ] **Step 2: Agregar tests de parseo al final de `tests/PronosticoApi.Tests.ps1`**

```powershell
Describe "Parse-OpenMeteoPoint" {
    $fixture = Get-Content "$here\fixtures\openmeteo_2pts.json" -Raw | ConvertFrom-Json

    It "parsea lat del punto 1" {
        (Parse-OpenMeteoPoint $fixture[0]).Lat | Should Be -33.5
    }
    It "parsea lon del punto 1" {
        (Parse-OpenMeteoPoint $fixture[0]).Lon | Should Be -70.5
    }
    It "HourlyPrecipEcmwf tiene 48 valores" {
        (Parse-OpenMeteoPoint $fixture[0]).HourlyPrecipEcmwf.Count | Should Be 48
    }
    It "HourlyIsoIcon tiene null en indice 2" {
        (Parse-OpenMeteoPoint $fixture[0]).HourlyIsoIcon[2] | Should BeNullOrEmpty
    }
    It "HourlyIsoEcmwf[0] es 3200" {
        (Parse-OpenMeteoPoint $fixture[0]).HourlyIsoEcmwf[0] | Should Be 3200
    }
}

Describe "Get-SumaVentana" {
    $fixture  = Get-Content "$here\fixtures\openmeteo_2pts.json" -Raw | ConvertFrom-Json
    $punto1   = Parse-OpenMeteoPoint $fixture[0]

    It "suma ECMWF ventana +6 a 12h = 7" {
        Get-SumaVentana $punto1.HourlyPrecipEcmwf 6 11 | Should Be 7.0
    }
    It "suma ECMWF ventana +12 a 24h = 26" {
        Get-SumaVentana $punto1.HourlyPrecipEcmwf 12 23 | Should Be 26.0
    }
    It "suma GFS ventana +12 a 24h = 18" {
        Get-SumaVentana $punto1.HourlyPrecipGfs 12 23 | Should Be 18.0
    }
    It "suma ICON ventana +6 a 12h = 12" {
        Get-SumaVentana $punto1.HourlyPrecipIcon 6 11 | Should Be 12.0
    }
    It "suma ECMWF ventana +0 a 6h = 0" {
        Get-SumaVentana $punto1.HourlyPrecipEcmwf 0 5 | Should Be 0.0
    }
    It "null cuenta como 0 en suma" {
        $serie = @(1.0, $null, 2.0)
        Get-SumaVentana $serie 0 2 | Should Be 3.0
    }
}

Describe "Get-MinVentana" {
    $fixture = Get-Content "$here\fixtures\openmeteo_2pts.json" -Raw | ConvertFrom-Json
    $punto1  = Parse-OpenMeteoPoint $fixture[0]

    It "min ECMWF en cualquier ventana = 3200" {
        Get-MinVentana $punto1.HourlyIsoEcmwf 0 5 | Should Be 3200
    }
    It "min ICON ventana +0 a 6h = 3400 (ignora null)" {
        Get-MinVentana $punto1.HourlyIsoIcon 0 5 | Should Be 3400
    }
    It "min GFS en cualquier ventana = 3100" {
        Get-MinVentana $punto1.HourlyIsoGfs 6 11 | Should Be 3100
    }
    It "retorna null cuando todos los valores son null" {
        $serie = @($null, $null, $null)
        Get-MinVentana $serie 0 2 | Should BeNullOrEmpty
    }
}
```

- [ ] **Step 3: Ejecutar tests**

```powershell
Invoke-Pester .\tests\PronosticoApi.Tests.ps1 -Verbose
```

Resultado esperado: **todos los tests PASS** (5 grilla + 6 suma + 4 min = 15 en total)

- [ ] **Step 4: Commit**

```powershell
git add src/PronosticoApi.ps1 tests/PronosticoApi.Tests.ps1
git commit -m "feat: Parse-OpenMeteoPoint + Get-SumaVentana + Get-MinVentana"
```

---

## Task 3: Get-ColorPronostico + Get-EstiloPronostico + Build-VentanasPunto

**Files:**
- Modify: `src/PronosticoApi.ps1` (agregar 3 funciones)
- Modify: `tests/PronosticoApi.Tests.ps1` (agregar tests)

- [ ] **Step 1: Agregar 3 funciones al final de `src/PronosticoApi.ps1`**

```powershell
function Get-ColorPronostico([double]$precip, $iso) {
    if ($null -eq $iso)       { return 'verde' }
    if ($precip -lt 5)        { return 'verde' }
    if ($iso -lt 2500)        { return 'verde' }
    if ($precip -ge 20 -and $iso -ge 3000) { return 'rojo' }
    return 'amarillo'
}

function Get-EstiloPronostico([string]$colorPeor, [int]$nModelos) {
    if ($colorPeor -eq 'verde') { return 'verde' }
    return "${colorPeor}_${nModelos}"
}

function Build-VentanasPunto($punto) {
    $config = @(
        @{ Nombre='+0 a 6h';   Desde=0;  Hasta=5  }
        @{ Nombre='+6 a 12h';  Desde=6;  Hasta=11 }
        @{ Nombre='+12 a 24h'; Desde=12; Hasta=23 }
        @{ Nombre='+24 a 48h'; Desde=24; Hasta=47 }
    )
    $ventanas = @()
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

        $orden = @{ verde=0; amarillo=1; rojo=2 }
        $colores = @($cE, $cG, $cI)
        $peor = $colores | Sort-Object { $orden[$_] } -Descending | Select-Object -First 1
        $n    = ($colores | Where-Object { $_ -eq $peor }).Count

        $ventanas += [PSCustomObject]@{
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
        }
    }
    return $ventanas
}
```

- [ ] **Step 2: Agregar tests al final de `tests/PronosticoApi.Tests.ps1`**

```powershell
Describe "Get-ColorPronostico" {
    It "verde cuando precip=0"                     { Get-ColorPronostico 0.0  3200 | Should Be 'verde'    }
    It "verde cuando precip < 5"                   { Get-ColorPronostico 4.9  3200 | Should Be 'verde'    }
    It "verde cuando iso < 2500 aunque precip alta"{ Get-ColorPronostico 30.0 2499 | Should Be 'verde'    }
    It "verde cuando iso es null"                  { Get-ColorPronostico 30.0 $null | Should Be 'verde'   }
    It "amarillo cuando precip=5 e iso=2500"       { Get-ColorPronostico 5.0  2500 | Should Be 'amarillo' }
    It "amarillo cuando precip=19 e iso=3000"      { Get-ColorPronostico 19.0 3000 | Should Be 'amarillo' }
    It "rojo cuando precip=20 e iso=3000"          { Get-ColorPronostico 20.0 3000 | Should Be 'rojo'     }
    It "rojo cuando precip=30 e iso=3500"          { Get-ColorPronostico 30.0 3500 | Should Be 'rojo'     }
}

Describe "Get-EstiloPronostico" {
    It "verde da verde"       { Get-EstiloPronostico 'verde'    0 | Should Be 'verde'     }
    It "amarillo_1"           { Get-EstiloPronostico 'amarillo' 1 | Should Be 'amarillo_1' }
    It "amarillo_2"           { Get-EstiloPronostico 'amarillo' 2 | Should Be 'amarillo_2' }
    It "amarillo_3"           { Get-EstiloPronostico 'amarillo' 3 | Should Be 'amarillo_3' }
    It "rojo_2"               { Get-EstiloPronostico 'rojo'     2 | Should Be 'rojo_2'     }
    It "rojo_3"               { Get-EstiloPronostico 'rojo'     3 | Should Be 'rojo_3'     }
}

Describe "Build-VentanasPunto" {
    $fixture = Get-Content "$here\fixtures\openmeteo_2pts.json" -Raw | ConvertFrom-Json
    $punto1  = Parse-OpenMeteoPoint $fixture[0]
    $punto2  = Parse-OpenMeteoPoint $fixture[1]
    $v1      = Build-VentanasPunto $punto1
    $v2      = Build-VentanasPunto $punto2

    It "devuelve 4 ventanas por punto" {
        $v1.Count | Should Be 4
    }
    It "ventana +0 a 6h de punto 1 es verde" {
        ($v1 | Where-Object { $_.Nombre -eq '+0 a 6h' }).EstiloKml | Should Be 'verde'
    }
    It "ventana +6 a 12h de punto 1 es amarillo_2" {
        ($v1 | Where-Object { $_.Nombre -eq '+6 a 12h' }).EstiloKml | Should Be 'amarillo_2'
    }
    It "ventana +12 a 24h de punto 1 es rojo_2" {
        ($v1 | Where-Object { $_.Nombre -eq '+12 a 24h' }).EstiloKml | Should Be 'rojo_2'
    }
    It "ventana +24 a 48h de punto 1 es verde" {
        ($v1 | Where-Object { $_.Nombre -eq '+24 a 48h' }).EstiloKml | Should Be 'verde'
    }
    It "todas las ventanas de punto 2 son verde (iso baja)" {
        ($v2 | Where-Object { $_.EstiloKml -ne 'verde' }).Count | Should Be 0
    }
    It "ventana +12 a 24h de punto 1 tiene PrecipEcmwf = 26" {
        ($v1 | Where-Object { $_.Nombre -eq '+12 a 24h' }).PrecipEcmwf | Should Be 26.0
    }
    It "ventana +12 a 24h de punto 1 ColorGfs = amarillo" {
        ($v1 | Where-Object { $_.Nombre -eq '+12 a 24h' }).ColorGfs | Should Be 'amarillo'
    }
    It "ventana +12 a 24h de punto 1 NModelos = 2" {
        ($v1 | Where-Object { $_.Nombre -eq '+12 a 24h' }).NModelos | Should Be 2
    }
}
```

- [ ] **Step 3: Ejecutar tests**

```powershell
Invoke-Pester .\tests\PronosticoApi.Tests.ps1 -Verbose
```

Resultado esperado: **todos los tests PASS** (15 previos + 8 color + 6 estilo + 9 ventanas = 38 en total)

- [ ] **Step 4: Commit**

```powershell
git add src/PronosticoApi.ps1 tests/PronosticoApi.Tests.ps1
git commit -m "feat: Get-ColorPronostico + Get-EstiloPronostico + Build-VentanasPunto"
```

---

## Task 4: Get-PronosticoGrilla (llamada a la API)

**Files:**
- Modify: `src/PronosticoApi.ps1` (agregar 1 función)

No hay test unitario (llama a red). La verificación es manual en el Step 3.

- [ ] **Step 1: Agregar Get-PronosticoGrilla al final de `src/PronosticoApi.ps1`**

```powershell
function Get-PronosticoGrilla([array]$grilla) {
    $allVentanas = @()
    $i = 0
    while ($i -lt $grilla.Count) {
        $hasta = [Math]::Min($i + 99, $grilla.Count - 1)
        $lote  = $grilla[$i..$hasta]
        $lats  = ($lote | ForEach-Object { $_.Lat }) -join ','
        $lons  = ($lote | ForEach-Object { $_.Lon }) -join ','
        $url   = "https://api.open-meteo.com/v1/forecast?latitude=$lats&longitude=$lons" +
                 "&hourly=precipitation,freezing_level_height" +
                 "&models=ecmwf_ifs025,gfs_seamless,icon_seamless&forecast_days=2"
        $resp  = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 60
        $arr   = @($resp.Content | ConvertFrom-Json)
        foreach ($obj in $arr) {
            $pt = Parse-OpenMeteoPoint $obj
            $allVentanas += Build-VentanasPunto $pt
        }
        $i += 100
        if ($i -lt $grilla.Count) { Start-Sleep -Milliseconds 400 }
    }
    return $allVentanas
}
```

- [ ] **Step 2: Prueba manual en consola**

```powershell
. .\src\PronosticoApi.ps1
$g = Get-GrillaChile
Write-Host "Grilla: $($g.Count) puntos"
$v = Get-PronosticoGrilla $g
Write-Host "Ventanas totales: $($v.Count)  (esperado: $($g.Count * 4))"
$v | Where-Object { $_.EstiloKml -ne 'verde' } | Select-Object Nombre, Lat, Lon, EstiloKml, PrecipEcmwf, PrecipGfs, PrecipIcon | Format-Table
```

Verificar: `Ventanas totales` = `Grilla * 4`. Si hay precipitación, aparecen filas no-verdes.

- [ ] **Step 3: Commit**

```powershell
git add src/PronosticoApi.ps1
git commit -m "feat: Get-PronosticoGrilla (Open-Meteo API call)"
```

---

## Task 5: KML building — estilos, placemarks y Build-PronosticoKml

**Files:**
- Modify: `src/AlertasKml.ps1` (agregar 4 funciones al final)
- Modify: `tests/AlertasKml.Tests.ps1` (agregar tests al final)

- [ ] **Step 1: Agregar funciones al final de `src/AlertasKml.ps1`**

```powershell
function Build-StylesPronostico {
    $xml = ''
    foreach ($color in @('amarillo', 'rojo')) {
        $kmlColor = if ($color -eq 'rojo') { 'ff0000ff' } else { 'ff00ffff' }
        foreach ($n in @(1, 2, 3)) {
            $scale = if ($n -eq 3) { 1.0 } elseif ($n -eq 2) { 0.8 } else { 0.6 }
            $opac  = if ($n -eq 1) { 'bb' } else { 'ff' }
            $kmlC  = "$opac$($kmlColor.Substring(2))"
            $xml  += @"
  <Style id="${color}_${n}">
    <IconStyle>
      <color>$kmlC</color><scale>$scale</scale>
      <Icon><href>http://maps.google.com/mapfiles/kml/shapes/placemark_circle.png</href></Icon>
    </IconStyle>
    <LabelStyle><scale>0</scale></LabelStyle>
  </Style>
"@
        }
    }
    return $xml
}

function Build-PlacemarkPronostico($v) {
    $isoE = if ($null -ne $v.IsoEcmwf) { "$($v.IsoEcmwf) m" } else { 'sin dato' }
    $isoG = if ($null -ne $v.IsoGfs)   { "$($v.IsoGfs) m"   } else { 'sin dato' }
    $isoI = if ($null -ne $v.IsoIcon)  { "$($v.IsoIcon) m"  } else { 'sin dato' }
    $desc = "<![CDATA[<b>$($v.Lat) / $($v.Lon)</b><br/>Ventana: $($v.Nombre)<br/><br/>" +
            "<table><tr><th></th><th>Precip (mm)</th><th>Isoterma (m)</th><th>Alerta</th></tr>" +
            "<tr><td>ECMWF</td><td>$($v.PrecipEcmwf)</td><td>$isoE</td><td>$($v.ColorEcmwf)</td></tr>" +
            "<tr><td>GFS</td><td>$($v.PrecipGfs)</td><td>$isoG</td><td>$($v.ColorGfs)</td></tr>" +
            "<tr><td>ICON</td><td>$($v.PrecipIcon)</td><td>$isoI</td><td>$($v.ColorIcon)</td></tr>" +
            "</table><br/>Acuerdo: $($v.NModelos)/3 modelos en $($v.ColorFinal)]]>"
    return @"
    <Placemark>
      <name>$($v.Lat),$($v.Lon)</name>
      <styleUrl>#$($v.EstiloKml)</styleUrl>
      <description>$desc</description>
      <Point><coordinates>$($v.Lon),$($v.Lat),0</coordinates></Point>
    </Placemark>
"@
}

function Build-PronosticoFolders([array]$allVentanas) {
    $nombres = @('+0 a 6h', '+6 a 12h', '+12 a 24h', '+24 a 48h')
    $xml = ''
    foreach ($nombre in $nombres) {
        $grupo = $allVentanas | Where-Object { $_.Nombre -eq $nombre }
        $pm    = ($grupo | ForEach-Object { Build-PlacemarkPronostico $_ }) -join "`n"
        $xml  += @"
  <Folder>
    <name>$nombre ($($grupo.Count) pts)</name>
    <open>0</open>
$pm
  </Folder>

"@
    }
    return $xml
}

function Build-PronosticoKml([array]$allVentanas) {
    $estilosBase  = Build-Styles
    $estilosPron  = Build-StylesPronostico
    $folders      = Build-PronosticoFolders $allVentanas
    $ts           = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    return @"
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document>
  <name>Pronostico Chile - $ts</name>
$estilosBase
$estilosPron
$folders
</Document>
</kml>
"@
}
```

- [ ] **Step 2: Agregar tests al final de `tests/AlertasKml.Tests.ps1`**

```powershell
# Cargar PronosticoApi.ps1 también (necesario para construir las ventanas de prueba)
. "$here\..\src\PronosticoApi.ps1"

Describe "Build-StylesPronostico" {
    $estilos = Build-StylesPronostico

    It "contiene style amarillo_1" { $estilos | Should Match 'id="amarillo_1"' }
    It "contiene style amarillo_3" { $estilos | Should Match 'id="amarillo_3"' }
    It "contiene style rojo_2"     { $estilos | Should Match 'id="rojo_2"'     }
    It "contiene 6 estilos en total" {
        ($estilos | Select-String '<Style id=' -AllMatches).Matches.Count | Should Be 6
    }
}

Describe "Build-PlacemarkPronostico" {
    $v = [PSCustomObject]@{
        Nombre='+12 a 24h'; Lat=-33.5; Lon=-70.5
        PrecipEcmwf=26.0; PrecipGfs=18.0; PrecipIcon=30.0
        IsoEcmwf=3200; IsoGfs=3100; IsoIcon=3400
        ColorEcmwf='rojo'; ColorGfs='amarillo'; ColorIcon='rojo'
        ColorFinal='rojo'; NModelos=2; EstiloKml='rojo_2'
    }
    $pm = Build-PlacemarkPronostico $v

    It "es un elemento Placemark"          { $pm | Should Match '<Placemark>'   }
    It "usa styleUrl rojo_2"               { $pm | Should Match '#rojo_2'       }
    It "contiene ECMWF en descripcion"     { $pm | Should Match 'ECMWF'         }
    It "contiene GFS en descripcion"       { $pm | Should Match 'GFS'           }
    It "contiene ICON en descripcion"      { $pm | Should Match 'ICON'          }
    It "coordenadas lon,lat"               { $pm | Should Match '-70.5,-33.5'   }
}

Describe "Build-PronosticoKml" {
    $fixture = Get-Content "$here\fixtures\openmeteo_2pts.json" -Raw | ConvertFrom-Json
    $puntos  = $fixture | ForEach-Object { Parse-OpenMeteoPoint $_ }
    $ventanas = @()
    foreach ($p in $puntos) { $ventanas += Build-VentanasPunto $p }
    $kml = Build-PronosticoKml $ventanas

    It "contiene declaracion XML"        { $kml | Should Match '<?xml'        }
    It "contiene carpeta +0 a 6h"        { $kml | Should Match '\+0 a 6h'     }
    It "contiene carpeta +12 a 24h"      { $kml | Should Match '\+12 a 24h'   }
    It "contiene carpeta +24 a 48h"      { $kml | Should Match '\+24 a 48h'   }
    It "contiene 8 placemarks (2pts x 4ventanas)" {
        ($kml | Select-String '<Placemark>' -AllMatches).Matches.Count | Should Be 8
    }
    It "contiene estilo rojo_2" { $kml | Should Match 'rojo_2' }
}
```

- [ ] **Step 3: Ejecutar todos los tests**

```powershell
Invoke-Pester .\tests\ -Verbose
```

Resultado esperado: **todos los tests PASS** (tests existentes + 4 + 6 + 5 nuevos)

- [ ] **Step 4: Commit**

```powershell
git add src/AlertasKml.ps1 tests/AlertasKml.Tests.ps1
git commit -m "feat: Build-PronosticoKml + estilos multi-modelo"
```

---

## Task 6: Modificar Actualizar.ps1

**Files:**
- Modify: `Actualizar.ps1`

- [ ] **Step 1: Reemplazar el contenido de `Actualizar.ps1`**

```powershell
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Path -Parent }
. "$here\src\RedesApi.ps1"
. "$here\src\AlertasKml.ps1"
. "$here\src\PronosticoApi.ps1"

$kmlPath         = "$here\red_alertas.kml"
$kmlPronostico   = "$here\red_pronostico.kml"

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Consultando DMC/DGA/Agromet (todas las redes)..." -ForegroundColor Cyan
try {
    $redes = Get-AllRedes
    Write-Host "  -> $($redes.Count) estaciones" -ForegroundColor Gray
} catch {
    Write-Warning "Error en DMC/DGA/Agromet: $_"
    $redes = @()
}

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Consultando EMAs DMC..." -ForegroundColor Cyan
try {
    $emas = Get-EmasDmc
    Write-Host "  -> $($emas.Count) estaciones" -ForegroundColor Gray
} catch {
    Write-Warning "Error en EMAs DMC: $_"
    $emas = @()
}

if ($redes.Count -eq 0 -and $emas.Count -eq 0) {
    Write-Warning "Sin datos de ninguna fuente. Se mantiene el KML anterior."
    exit 1
}

$kml = Build-Kml $redes $emas
[System.IO.File]::WriteAllText($kmlPath, $kml, [System.Text.Encoding]::UTF8)

$alertasRedes = ($redes | Where-Object { $_.TasaMmH -ge 5 }).Count
$alertasEmas  = ($emas  | Where-Object { (Get-ColorEmas $_.TasaMmH $_.Isoterma) -ne 'verde' }).Count

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

    $alertasPron = ($allVentanas | Where-Object { $_.EstiloKml -ne 'verde' }).Count
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] KML pronostico escrito: $kmlPronostico" -ForegroundColor Green
    Write-Host "  Grilla: $($grilla.Count) pts | $alertasPron ventanas con alerta" -ForegroundColor Yellow
} catch {
    Write-Warning "Error en pronostico Open-Meteo: $_. Se mantiene el KML anterior."
}
```

- [ ] **Step 2: Prueba local completa**

```powershell
powershell -File Actualizar.ps1
```

Verificar:
- `red_alertas.kml` se escribe sin errores
- `red_pronostico.kml` se escribe sin errores
- En consola aparece: `KML pronostico escrito: ...red_pronostico.kml`

Abrir `red_pronostico.kml` en Google Earth Pro para verificar que las 4 carpetas aparecen.

- [ ] **Step 3: Commit**

```powershell
git add Actualizar.ps1
git commit -m "feat: Actualizar.ps1 escribe red_pronostico.kml separado"
```

---

## Task 7: Modificar Crear-KMZ.ps1 (doble NetworkLink)

**Files:**
- Modify: `Crear-KMZ.ps1`

- [ ] **Step 1: Reemplazar el contenido de `Crear-KMZ.ps1`**

```powershell
param([switch]$Online)

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Path -Parent }

if ($Online) {
    $remoto = git -C $here remote get-url origin 2>$null
    if (-not $remoto) { throw "No hay remoto git configurado. Usa Crear-KMZ.ps1 sin -Online primero." }
    $rawBase        = $remoto -replace 'https://github.com/', 'https://raw.githubusercontent.com/'
    $rawBase        = $rawBase -replace '\.git$', ''
    $kmlUrl         = "$rawBase/live/red_alertas.kml"
    $pronosticoUrl  = "$rawBase/live/red_pronostico.kml"
    $kmzPath        = "$here\alertas-redes-online.kmz"
} else {
    $base           = $here -replace '\\', '/'
    $kmlUrl         = "file:///$base/red_alertas.kml"
    $pronosticoUrl  = "file:///$base/red_pronostico.kml"
    $kmzPath        = "$here\alertas-redes.kmz"
}

$kmlContenido = @"
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document>
  <name>Alertas Redes Chile</name>
  <NetworkLink>
    <name>Alertas actuales</name>
    <open>1</open>
    <Link>
      <href>$kmlUrl</href>
      <refreshMode>onInterval</refreshMode>
      <refreshInterval>900</refreshInterval>
    </Link>
  </NetworkLink>
  <NetworkLink>
    <name>Pronostico 48h</name>
    <open>1</open>
    <Link>
      <href>$pronosticoUrl</href>
      <refreshMode>onInterval</refreshMode>
      <refreshInterval>900</refreshInterval>
    </Link>
  </NetworkLink>
</Document>
</kml>
"@

$tmpKml = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.kml'
[System.IO.File]::WriteAllText($tmpKml, $kmlContenido, [System.Text.Encoding]::UTF8)

if (Test-Path $kmzPath) { Remove-Item $kmzPath -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($kmzPath, 'Create')
[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $tmpKml, 'doc.kml') | Out-Null
$zip.Dispose()
Remove-Item $tmpKml

Write-Host "KMZ generado: $kmzPath" -ForegroundColor Green
Write-Host "  Alertas:    $kmlUrl"        -ForegroundColor Gray
Write-Host "  Pronostico: $pronosticoUrl" -ForegroundColor Gray
```

- [ ] **Step 2: Prueba local**

```powershell
powershell -File Crear-KMZ.ps1
```

Abrir `alertas-redes.kmz` en Google Earth Pro y verificar que aparecen los dos NetworkLinks ("Alertas actuales" y "Pronostico 48h").

- [ ] **Step 3: Prueba con -Online (si hay remoto configurado)**

```powershell
powershell -File Crear-KMZ.ps1 -Online
```

Verificar que `alertas-redes-online.kmz` se genera y la URL del pronóstico apunta a `raw.githubusercontent.com/.../live/red_pronostico.kml`.

- [ ] **Step 4: Ejecutar todos los tests para verificar que no hay regresiones**

```powershell
Invoke-Pester .\tests\ -Verbose
```

Resultado esperado: **todos los tests PASS**

- [ ] **Step 5: Commit**

```powershell
git add Crear-KMZ.ps1
git commit -m "feat: Crear-KMZ con doble NetworkLink (alertas + pronostico)"
```

---

## Task 8: .gitignore + publicar.yml

**Files:**
- Modify: `.gitignore`
- Modify: `.github/workflows/publicar.yml`

- [ ] **Step 1: Agregar `red_pronostico.kml` a `.gitignore`**

Agregar esta línea al final de `.gitignore`:
```
red_pronostico.kml
```

El archivo completo queda:
```
estado.json
*.kmz
red_alertas.kml
red_pronostico.kml
```

- [ ] **Step 2: Reemplazar el contenido de `.github/workflows/publicar.yml`**

```yaml
name: Publicar KML

on:
  schedule:
    - cron: '0 * * * *'   # cada 60 min
  workflow_dispatch:

permissions:
  contents: write

jobs:
  actualizar:
    runs-on: windows-latest
    steps:
      - name: Checkout main
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Restaurar KMLs previos desde live (si existe)
        shell: pwsh
        run: |
          git fetch origin live 2>$null
          if (git branch -r | Select-String 'origin/live') {
            git checkout origin/live -- red_alertas.kml    2>$null
            git checkout origin/live -- red_pronostico.kml 2>$null
          }

      - name: Generar KMLs
        shell: pwsh
        run: powershell -File Actualizar.ps1

      - name: Publicar en rama live
        shell: pwsh
        run: |
          git config user.name  "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git checkout --orphan live-tmp
          git rm -rf --cached . 2>$null
          Remove-Item .gitignore -ErrorAction SilentlyContinue
          git add red_alertas.kml
          if (Test-Path red_pronostico.kml) { git add red_pronostico.kml }
          git commit -m "data: actualizar KMLs $(Get-Date -Format 'yyyy-MM-dd HH:mm') UTC"
          git push origin HEAD:live --force
```

Nota: `if (Test-Path red_pronostico.kml)` hace que el workflow siga funcionando aunque el pronóstico falle y no genere el archivo.

- [ ] **Step 3: Ejecutar todos los tests una vez más**

```powershell
Invoke-Pester .\tests\ -Verbose
```

Resultado esperado: **todos los tests PASS**

- [ ] **Step 4: Commit final**

```powershell
git add .gitignore .github/workflows/publicar.yml
git commit -m "feat: workflow publica red_pronostico.kml a rama live"
```

- [ ] **Step 5: Push a main y verificar Actions**

```powershell
git push origin main
```

Ir a `https://github.com/cvenegas-sernageomin/alertas-redes/actions` y ejecutar el workflow manualmente ("Run workflow"). Verificar que:
1. El step "Generar KMLs" produce ambos archivos sin errores
2. El step "Publicar en rama live" hace commit con ambos KMLs
3. La rama `live` contiene `red_alertas.kml` y `red_pronostico.kml`

- [ ] **Step 6: Regenerar KMZ compartible**

```powershell
powershell -File Crear-KMZ.ps1 -Online
```

Compartir `alertas-redes-online.kmz` — ahora incluye las 4 capas de pronóstico.
