# Spec: Capa de Pronóstico Meteorológico — alertas-redes

**Fecha:** 2026-06-25  
**Proyecto:** `alertas-redes` (`C:\Users\carlos.venegas\Documents\Claude\alertas-redes\`)  
**Repo:** `cvenegas-sernageomin/alertas-redes`

---

## Objetivo

Agregar pronóstico meteorológico proactivo al visor Google Earth existente. Actualmente el sistema muestra condiciones en tiempo real (reactivo). Con esta feature, una carpeta nueva "Pronostico" en el KMZ mostrará la amenaza de aluvión esperada en las próximas 48h sobre una grilla regular de Chile, usando tres modelos NWP simultáneos para indicar confianza.

---

## Fuente de datos

**API:** Open-Meteo (`api.open-meteo.com/v1/forecast`)
- Gratuita, sin token, sin registro
- Soporta múltiples coordenadas por llamada (hasta 100)
- Soporta múltiples modelos NWP en la misma llamada

**Modelos NWP consultados:**
| Parámetro API | Modelo |
|---|---|
| `ecmwf_ifs025` | ECMWF IFS (europeo, el más confiable globalmente) |
| `gfs_seamless` | GFS NOAA (norteamericano) |
| `icon_seamless` | DWD ICON (alemán) |

**Variables:**
- `precipitation` — precipitación horaria (mm)
- `freezing_level_height` — isoterma 0°C (metros)

**Llamada ejemplo (1 punto):**
```
GET https://api.open-meteo.com/v1/forecast
  ?latitude=-33.4&longitude=-70.6
  &hourly=precipitation,freezing_level_height
  &models=ecmwf_ifs025,gfs_seamless,icon_seamless
  &forecast_days=2
```

Para múltiples puntos: `latitude=lat1,lat2,...&longitude=lon1,lon2,...` (máx 100 por llamada). La respuesta es un array de objetos, uno por punto.

---

## Grilla de Chile

Función `Get-GrillaChile` genera los puntos automáticamente:

- **Espaciado:** 1° (~110 km)
- **Horizonte:** lat −17.5 a −56.0, con rango de longitud por banda para excluir océano y Argentina

| Banda lat | Lon mín | Lon máx |
|---|---|---|
| −17 a −30 (Norte) | −75 | −67 |
| −30 a −43 (Centro) | −76 | −68 |
| −43 a −56 (Sur) | −77 | −68 |

Resultado esperado: ~140–160 puntos sobre Chile continental y altiplano.

Con 100 puntos por lote → **2 llamadas API** con throttle de 400 ms entre ellas.

---

## Ventanas de tiempo

Cuatro ventanas incrementales (no acumuladas):

| Capa KML | Ventana | Horas de la serie |
|---|---|---|
| `+0 a 6h` | Próximas 6 horas | índices 0–5 |
| `+6 a 12h` | Horas 6 a 12 | índices 6–11 |
| `+12 a 24h` | Horas 12 a 24 | índices 12–23 |
| `+24 a 48h` | Horas 24 a 48 | índices 24–47 |

Para cada ventana y cada modelo:
- `precip_mm` = suma de valores horarios de `precipitation` en la ventana
- `min_iso` = mínimo de `freezing_level_height` en la ventana

---

## Lógica de alerta

**Color base por modelo:**

| Condición | Color |
|---|---|
| `precip_mm < 5` **O** `min_iso < 2500` | Verde |
| `precip_mm ≥ 5` **Y** `min_iso ≥ 2500` | Amarillo |
| `precip_mm ≥ 20` **Y** `min_iso ≥ 3000` | Rojo |

**Confianza multi-modelo** — color final = peor color entre los 3 modelos; N = cantidad de modelos que coinciden en ese peor color:

| N modelos en el peor color | Estilo KML | Tamaño ícono |
|---|---|---|
| 3/3 | `amarillo_3` / `rojo_3` | Grande (scale 1.0) |
| 2/3 | `amarillo_2` / `rojo_2` | Mediano (scale 0.8) |
| 1/3 | `amarillo_1` / `rojo_1` | Pequeño, semitransparente (scale 0.6) |
| 0/3 (todos verdes) | `verde` | Pequeño (scale 0.5) |

Función `Get-ColorPronostico($precip, $iso)` devuelve el color base para un modelo. Función `Get-EstiloPronostico($colorBase, $nModelos)` combina ambas dimensiones en el nombre del estilo KML.

Ejemplo: ECMWF=rojo, GFS=amarillo, ICON=rojo → peor=rojo, N (en rojo)=2 → estilo `rojo_2`.
Ejemplo: ECMWF=amarillo, GFS=verde, ICON=amarillo → peor=amarillo, N (en amarillo)=2 → estilo `amarillo_2`.

**Manejo de nulos:** Open-Meteo puede devolver `null` en algunas horas (gaps de inicialización). En `precipitation`: null se trata como 0. En `freezing_level_height`: null se excluye del mínimo (si todos son null, min_iso = null → color verde por falta de dato).

---

## Popup del placemark

Al hacer clic en un punto de la grilla se muestra:

```
Lat: -33.50 | Lon: -70.50
Ventana: +6 a 12h

         Precip (mm)  Isoterma (m)  Alerta
ECMWF      18.3         3200         🔴
GFS         6.1         2800         🟡
ICON       22.0         3100         🔴

Acuerdo: 2/3 modelos en rojo
```

---

## Archivos

### Nuevos

| Archivo | Contenido |
|---|---|
| `src/PronosticoApi.ps1` | `Get-GrillaChile`, `Get-PronosticoGrilla`, `Get-ColorPronostico`, `Get-EstiloPronostico` |
| `tests/PronosticoApi.Tests.ps1` | Tests Pester con fixture JSON de Open-Meteo |
| `tests/fixtures/openmeteo_sample.json` | Respuesta real grabada (2 puntos, 48h, 3 modelos) |

### Modificados

| Archivo | Cambio |
|---|---|
| `src/AlertasKml.ps1` | Agregar 7 estilos nuevos en `Build-Styles`; agregar `Build-PlacemarkPronostico`, `Build-FolderPronostico`; `Build-Kml` acepta `$pronostico` opcional |
| `Actualizar.ps1` | Dot-source `PronosticoApi.ps1`; llamar `Get-GrillaChile` + `Get-PronosticoGrilla`; escribir `red_pronostico.kml` en bloque separado con su propio `try/catch` |
| `Crear-KMZ.ps1` | Modo `-Online`: KMZ incluye dos `<NetworkLink>` (uno para `red_alertas.kml`, uno para `red_pronostico.kml`) |
| `.gitignore` | Agregar `red_pronostico.kml` |
| `.github/workflows/publicar.yml` | Agregar `red_pronostico.kml` al `git add` en el paso de publicar |

---

## Archivo KML de pronóstico

`red_pronostico.kml` es un documento KML independiente:

```xml
<Document>
  <name>Pronostico Chile - {timestamp}</name>
  <!-- estilos -->
  <Folder>
    <name>+0 a 6h ({N} puntos)</name>
    <!-- placemarks grilla -->
  </Folder>
  <Folder>
    <name>+6 a 12h ({N} puntos)</name>
  </Folder>
  <Folder>
    <name>+12 a 24h ({N} puntos)</name>
  </Folder>
  <Folder>
    <name>+24 a 48h ({N} puntos)</name>
  </Folder>
</Document>
```

---

## KMZ compartible (Crear-KMZ.ps1 -Online)

El `alertas-redes-online.kmz` pasa a tener dos NetworkLinks:

```xml
<NetworkLink>
  <name>Alertas actuales</name>
  <refreshMode>onInterval</refreshMode>
  <refreshInterval>900</refreshInterval>
  <Link><href>https://raw.githubusercontent.com/cvenegas-sernageomin/alertas-redes/live/red_alertas.kml</href></Link>
</NetworkLink>
<NetworkLink>
  <name>Pronostico 48h</name>
  <refreshMode>onInterval</refreshMode>
  <refreshInterval>900</refreshInterval>
  <Link><href>https://raw.githubusercontent.com/cvenegas-sernageomin/alertas-redes/live/red_pronostico.kml</href></Link>
</NetworkLink>
```

---

## Fallback y robustez

- Si Open-Meteo falla (timeout, 429, error red): `Actualizar.ps1` registra `Write-Warning` y **no escribe** `red_pronostico.kml` → el archivo anterior en la rama `live` se mantiene sin cambios (el workflow restaura el archivo previo al inicio, igual que `red_alertas.kml`)
- `red_alertas.kml` se genera siempre independientemente del resultado del pronóstico
- Throttle 400 ms entre lotes Open-Meteo (mismo patrón que vismet)

---

## Despliegue en GitHub Actions

El workflow `publicar.yml` agrega `red_pronostico.kml` al paso de publicar:

```yaml
- name: Restaurar KMLs previos desde live
  # restaura red_alertas.kml Y red_pronostico.kml

- name: Generar KML
  run: powershell -File Actualizar.ps1
  # escribe red_alertas.kml y red_pronostico.kml (si no hay error)

- name: Publicar en rama live
  run: |
    ...
    git add red_alertas.kml
    git add red_pronostico.kml  # nuevo
    git commit ...
    git push origin HEAD:live --force
```

---

## Tests

`tests/PronosticoApi.Tests.ps1` cubre:

1. `Get-GrillaChile` → devuelve array de PSCustomObject con Lat/Lon; todos los puntos en rango esperado
2. Parseo de fixture JSON → extrae series horarias correctamente para los 3 modelos
3. `Get-ColorPronostico` → tabla de verdad para los umbrales (5 mm / 20 mm, 2500 m / 3000 m)
4. `Get-EstiloPronostico` → combinación correcta de color peor + N modelos
5. Suma de ventana → suma horaria correcta para cada ventana (0-6, 6-12, 12-24, 24-48)
6. Mínimo de isoterma → retorna el mínimo correcto en la ventana

---

## Tiempo de ejecución estimado

| Paso | Tiempo |
|---|---|
| Scraping vismet (1276 est.) | ~45 s |
| EMAs DMC (103 est.) | ~15 s |
| Open-Meteo grilla (~150 pts, 2 lotes) | ~5 s |
| Generación KML | ~2 s |
| **Total** | **~67 s** |
