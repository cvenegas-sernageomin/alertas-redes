# Diseño: gráficos en popup por estación (últimas horas)

**Fecha:** 2026-06-25  
**Estado:** aprobado por usuario

## Objetivo

Agregar un gráfico histórico en el popup (description balloon) de cada estación en el KMZ de alertas-redes. El gráfico muestra los valores de las últimas horas disponibles en una sola llamada API.

- **Capa 1** (todas las redes, ~1276 est.): barras de precipitación (mm/h) por hora.
- **Capa 2** (EMAs DMC, ~105 est.): gráfico combinado — barras precip + línea temp + línea isoterma + umbral 3000 m.

---

## Tecnología de renderizado

**quickchart.io** — servicio gratuito que genera imágenes Chart.js vía URL GET. Se incrusta como `<img src="https://quickchart.io/chart?w=300&h=160&c=...">` dentro del CDATA del KML. Requiere internet al abrir el popup (uso habitual: escritorio con conectividad).

No requiere JS, cuentas ni tokens. La URL se genera completamente en PowerShell.

---

## Cambios en la capa de datos (RedesApi.ps1)

### Llamadas API — reorganización sin aumentar el total (3 llamadas)

| # | Endpoint | Propósito | Cambio |
|---|---|---|---|
| 1 | `measure/type/1/by-timestamp/{epoch}/by-interval/3` | Serie precip ~1276 est. | existente |
| 2 | `raw-measure/type/1/last` | Altitud EMAs DMC | existente |
| 3 | `measure/type/2/by-timestamp/{epoch}/by-interval/3` | Serie temp DMC | **nuevo** — reemplaza `raw-measure/type/2/last` |

### `Parse-RedesJson` — preservar serie

Actualmente descarta `values[]`/`timestamps[]` después de extraer el último no-nulo. Se cambia para retener ambos arrays en el objeto de salida:

```
objeto resultado agrega:
  ValoresSerie  = [array de doubles, nulls incluidos]
  TiemposSerie  = [array de epoch int64]
```

`TasaMmH` sigue siendo el último valor no-nulo (sin cambios para la lógica de alerta).

### `Parse-EmasDmcJson` — nueva firma

La función recibe tres argumentos en vez de dos:

```
Parse-EmasDmcJson(
  [array]$precipSerie,   # filtrado de llamada 1 (códigos DMC)
  [array]$tempSerie,     # de llamada 3 (windowed tipo 2)
  [hashtable]$altitudMap # codigo → altitud, de llamada 2
)
```

Por cada estación EMAs:
- `TasaMmH` = último no-nulo de `precipSerie.values[]`
- `TempC` = último no-nulo de `tempSerie.values[]`
- `Isoterma` = `altitud + (TempC / 6.5) * 1000` (igual que hoy)
- `ValoresPrecip` / `TiemposPrecip` = arrays completos de precip
- `ValoresTemp` / `TiemposTemp` = arrays completos de temp
- `ValoresIso` = array calculado timestamp a timestamp (null donde temp es null)

### `Get-EmasDmc` — actualización

Reemplaza la llamada 3 (`raw-measure/type/2/last`) por `measure/type/2/by-timestamp/{epoch}/by-interval/3`. Mantiene la llamada 2 (`raw-measure/type/1/last`) para el mapa de altitud. Extrae la serie de precip para EMAs filtrando el resultado de la llamada 1 por código: solo los códigos que aparecen en el mapa de altitud (llamada 2). Así se evita confundir estaciones DGA (también numéricas) con DMC.

Si la llamada 3 falla o devuelve formato inesperado: fallback a `TempC = null`, `ValoresTemp = @()`. Las alertas y el gráfico de precip siguen funcionando.

---

## Generación del gráfico (AlertasKml.ps1)

### Nueva función `Build-ChartUrl`

```
Build-ChartUrl(
  [array]$tiempos,       # epoch[] — eje X
  [array]$precip,        # double[] — barras azules, eje izquierdo (mm/h)
  [array]$temp = @(),    # double[] — línea roja, eje derecho (°C)
  [array]$iso  = @()     # double[] — línea naranja, eje derecho (km = m/1000)
)
→ [string] URL de quickchart.io
```

**Config Chart.js generada:**
- Labels: hora local `HH:mm` de cada epoch
- Dataset precip: `type: bar`, color azul `rgba(55,138,221,0.7)`, eje `yP` (izquierdo)
- Dataset temp: `type: line`, color rojo `#E24B4A`, eje `yR` (derecho), solo si `$temp.Count -gt 0`
- Dataset isoterma: `type: line`, color naranja `#EF9F27`, línea punteada, eje `yR`, valores en km, solo si `$iso.Count -gt 0`
- Dataset umbral 3 km: línea punteada semitransparente en `y = 3.0` del eje `yR`, solo si hay isoterma
- Leyenda: desactivada (`legend.display: false`) — la leyenda va en texto HTML sobre el `<img>`

La URL se construye con `[Uri]::EscapeDataString()` sobre el JSON serializado.

### Actualización de `Build-PlacemarkRedes`

Agrega al CDATA existente:
```html
<br/>
<small>Precip mm/h | Temp °C | Isoterma km</small><br/>
<img src="[URL]" width="300"/>
```

Solo si `$e.ValoresSerie.Count -gt 1` (al menos 2 puntos — con 1 no tiene sentido un gráfico).

### Actualización de `Build-PlacemarkEmas`

Igual, con la leyenda correspondiente. Incluye los tres datasets cuando los datos están disponibles.

---

## Tests

### `RedesApi.Tests.ps1`

- `Parse-RedesJson` retiene `ValoresSerie` y `TiemposSerie` con los valores del fixture.
- `Parse-EmasDmcJson` con nueva firma: calcula `ValoresIso` correctamente timestamp a timestamp.
- `Parse-EmasDmcJson` con temp vacía: `ValoresTemp = @()`, alertas no se ven afectadas.

### `AlertasKml.Tests.ps1`

- `Build-ChartUrl` con solo precip: URL contiene `quickchart.io` y no contiene `temp` ni `iso`.
- `Build-ChartUrl` con precip+temp+iso: URL contiene los tres datasets.
- `Build-ChartUrl` con array vacío de temp: URL no contiene dataset de temp.
- `Build-PlacemarkRedes` con serie de 2+ puntos: descripción contiene `<img`.
- `Build-PlacemarkRedes` con serie de 1 punto: descripción no contiene `<img`.

---

## Fixtures

Actualizar `tests/fixtures/redes_3h.json` para que tenga al menos 3 valores no-nulos en `values[]` (ya tiene 3 puntos — OK).

Agregar `tests/fixtures/temp_3h.json`: mismo formato que `redes_3h.json` pero con `measureType: 2` y valores de temperatura.

---

## Archivos afectados

| Archivo | Tipo de cambio |
|---|---|
| `src/RedesApi.ps1` | Modificar `Parse-RedesJson`, `Parse-EmasDmcJson`, `Get-EmasDmc` |
| `src/AlertasKml.ps1` | Agregar `Build-ChartUrl`, modificar `Build-PlacemarkRedes`, `Build-PlacemarkEmas` |
| `tests/RedesApi.Tests.ps1` | Actualizar tests existentes, agregar nuevos |
| `tests/AlertasKml.Tests.ps1` | Agregar tests de `Build-ChartUrl` |
| `tests/fixtures/temp_3h.json` | Nuevo fixture |
