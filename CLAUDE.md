# alertas-redes

Sistema de alertas hidrometeorológicas y sísmicas para Chile: descarga datos de vismet.cr2.cl (DGA/DMC/Agromet/CEAZA/RedMeteo), Open-Meteo (pronóstico) y CSN/USGS (sismos), genera KML y notifica por Telegram. Visor web en Leaflet + React.

## Estructura y despliegue (IMPORTANTE, no obvio)

- **El visor publicado (`https://cvenegas-sernageomin.github.io/alertas-redes/`) se sirve desde la rama `gh-pages`, NO desde `main`.** El código fuente vive en `main` en `visor-web/index.html`; `gh-pages/index.html` es una copia manual. Cualquier cambio al visor requiere sincronizar ambas ramas:
  ```
  git checkout gh-pages
  git checkout main -- visor-web/index.html
  cp visor-web/index.html index.html
  git add index.html && git commit -m "..." && git push origin gh-pages
  ```
- Datos (`red_alertas.kml`, `red_pronostico.kml`, `red_sismos.kml`, `altitudes.json`, `organizaciones.json`) viven en la rama `live`, generados por el workflow `.github/workflows/publicar.yml` (corre cada hora + manual).
- **Gotcha de persistencia:** cualquier archivo de caché nuevo debe agregarse en DOS lugares de `publicar.yml`: el paso "Restaurar KMLs previos desde live" (`git checkout origin/live -- archivo`) Y el paso "Publicar en rama live" (`git add archivo`). Si falta uno de los dos, el archivo se pierde en cada corrida.
- El workflow tiene un input `prueba` (workflow_dispatch) que envía un Telegram de ejemplo sin esperar alertas reales — útil para probar el formato del mensaje.

## Bug histórico importante: doble montaje de React

Babel Standalone **auto-ejecuta** scripts `type="text/jsx"`. Como el HTML también tiene un bootstrap manual que evalúa el mismo script, el código corría dos veces → dos `L.map()` → mapa huérfano cuyo `_onDown` crasheaba al iniciar un arrastre → **bloqueaba el pan con un dedo en móvil** (zoom de 2 dedos sí funcionaba). Fix: `type="text/plain"` en el script (Babel no lo auto-ejecuta, solo el bootstrap lo corre una vez).

## Fuente de datos DMC: directa, NO vismet (desde 2026-07-08)

Se verificó que **vismet.cr2.cl devuelve 0.0 fijo para TODA la red DMC (y también DGA)** —
686 estaciones, 48h, cero excepciones — mientras el portal público de la DMC
(`climatologia.meteochile.gob.cl`) muestra lluvia real y actual para las mismas estaciones
en el mismo momento (comparación directa confirmada, ej. estación 390015 Isla Teja: vismet
0.0mm vs DMC directo 0.7mm). El feed DGA/DMC de vismet está roto en origen (problema de
CR2, no nuestro); DGA no tiene alternativa sin CAPTCHA (ver DGASAT abajo) así que se
mantiene vía vismet, pero **DMC se reemplaza íntegramente por scraping directo**:

- `src/DmcDirecto.ps1` — scrapea `climatologia.meteochile.gob.cl/application/diariob/visorDeDatosEma/<codigo>`
  para las ~149 EMAs del grupo `EMAPublicadas` (mismo patrón validado en el proyecto hermano
  `emas-kmz`, ver `reference-dmc-visor-publico-sin-token` en memoria). Cada fetch trae nombre,
  altitud, lat/lon, temperatura actual (serie por minuto) y precipitación **acumulada del día**
  (se resetea a medianoche) — no hay serie horaria de lluvia en este endpoint.
- La tasa mm/h se estima **diferenciando contra la corrida anterior** (`dmc_estado.json`,
  cacheado en la rama `live` igual que `organizaciones.json`): `Get-PrecipRateDirecto`.
  Primera corrida tras un reinicio de caché: TasaMmH=0.0 en todas (sin base para diferenciar,
  se autocorrige en el siguiente ciclo).
- Reemplaza también la vieja mecánica de `Get-EmasDmc`/`Get-AltitudesRaw`/`altitudes.json`
  (cache de altitud vía `raw-measure/last` de vismet, tardaba 24-48h en calentarse) — ya no
  se llama desde `Actualizar.ps1`, porque el scrape directo trae la altitud en el mismo fetch,
  sin caché. Las funciones siguen en `RedesApi.ps1` con tests, pero quedaron sin uso activo.
- Tasa de éxito real: ~132/149 (17 fallidas, códigos que devuelven pagina sin lat/lon).
- Costo: ~150 requests gzip por ciclo, throttle 400ms → ~1.5 min. Con el cron real de
  ~2-5h (ver [[reference-github-actions-cron-poco-confiable]] o sección de abajo) esto es
  bajo tráfico total para el servidor de la DMC.

## RedMeteo excluida del KML (desde 2026-07-17)

Durante un temporal real en la zona central se verificó con la API de vismet que **las 66
estaciones RedMeteo devuelven 0.0 fijo en toda la ventana de 48h** (`by-measure-type/1`;
en `raw-measure/last` la red ni siquiera aparece), mientras Agromet/INIA/DMC vecinas
marcaban 50–296 mm/día — mismo patrón del feed roto de DMC/DGA en vismet. Como un 0 falso
en un sistema de alertas induce decisiones erradas, RedMeteo se excluye del ingest en
`Actualizar.ps1` (filtro junto al de DMC). **Camino de reintegro:** RedMeteo tiene API
propia (JSON/CSV, refresco 5 min, `redmeteo.cl/api.html`) que exige solicitud formal por
correo (`redmeteoaficionadachile@gmail.com`), citar la fuente y servir los datos en espejo
desde sistema propio (no leer su API en caliente). Cuando otorguen acceso: ingestar como
fuente directa nueva (patrón `DmcDirecto.ps1`) y quitar el filtro.

## Umbrales regionales aviso/alerta/alarma (solo precipitacion, desde 2026-07-08)

Sistema ADICIONAL de alerta verde/amarillo/rojo basado SOLO en precipitacion acumulada
del dia, con umbrales oficiales tipo SENAPRED que varian por region y por dia de lluvia
continua (el umbral baja con cada dia porque el suelo se satura). Fuente: tabla entregada
por el usuario (PDF de referencia sin trackear en el repo,
`Determinacion-de-umbrales-criticos-de-precipitacion-...pdf`).

- `src/UmbralesRegionales.ps1` — tabla hardcodeada (8 regiones: Metropolitana a Los Lagos,
  4 filas de dia de racha cada una con aviso/alerta/alarma en mm), `Get-RegionPorLat`
  (asigna region por la capital regional mas cercana en latitud — metodo APROXIMADO,
  aceptado explicitamente porque ninguna fuente de datos trae "region" como campo),
  `Get-AcumuladoCalendario` (suma una serie horaria por dia calendario Chile),
  `Update-RachaEstacion` (dia de lluvia continua: cualquier mm>0 cuenta, un dia en 0mm
  corta la racha, igual que un salto de cron >1 dia sin corridas).
- **Mapeo de color:** verde=bajo aviso, amarillo=[aviso,alerta), rojo=>=alerta. "alarma"
  es solo informativo en el popup (no agrega un 4to color) — decision tomada con el usuario.
- **Capa 1 (estaciones, `red_alertas.kml`):** REEMPLAZA el color de `Get-ColorRedes`
  (5/10 mm/h flat) por el sistema regional cuando la estacion cae en las 8 regiones
  cubiertas (`Get-ColorRedesFinal` en `AlertasKml.ps1`); fuera de tabla se mantiene el
  umbral simple sin cambios. Estado persistido en `racha_lluvia.json` (nuevo cache en
  rama `live`, mismo patron que `dmc_estado.json`/`organizaciones.json`).
- **Capa 2 (EMAs) y pronostico (`Get-ColorPronostico`, combo precip+iso):** SIN CAMBIOS,
  decision explicita del usuario. El pronostico SI gana un badge adicional
  ("Alerta pura por precipitacion") en el popup de cada punto con region conocida
  (`Get-AlertaPrecipRegionalPunto` en `PronosticoApi.ps1`) — dia 1 = acumulado +0 a 24h
  del pronostico contra umbrales dia 1, dia 2 = +24 a 48h contra umbrales dia 2 (asume
  que el propio dia 2 del pronostico es el "segundo dia de lluvia"; no conoce racha real
  antes de la ventana de 48h). NO cambia el icono del placemark.
- **Grafico de estaciones:** `Build-ChartAcumulado`/`Build-GraficosAcumulado` aceptan un
  `$umbralRojo` opcional (el umbral "alerta" de la region) y dibujan una linea roja
  horizontal punteada en el eje "Acum mm".
- **Grafico para DMC directo (desde 2026-07-08):** la DMC no publica serie horaria, solo
  el acumulado del dia actual — se reconstruye una serie a partir de una MINI-HISTORIA de
  muestras `{epoch;precip}` guardadas en `dmc_estado.json` en cada corrida del cron
  (`Add-MuestraHistoria`, ventana de 50h, se poda solo). `Get-SerieDesdeHistoria` calcula
  el delta entre muestras consecutivas (maneja reset de medianoche igual que
  `Get-PrecipRateDirecto`) y esas series alimentan `TiemposSerie`/`ValoresSerie` (Redes) y
  `ValoresPrecip`/`TiemposSerie` (EMAs) como si fueran de vismet — Build-GraficosAcumulado
  no necesito ningun cambio. Como el cron es irregular (~2-5h), el grafico tiene menos
  puntos y mas ruido que el de las redes con serie horaria real, pero es dato real (no
  inventado). Necesita al menos 3 corridas exitosas seguidas (2 deltas) para que aparezca
  el grafico (Build-GraficosAcumulado exige >=2 puntos).
  - **Bug real encontrado y corregido en el camino:** `Add-MuestraHistoria` devolvia el
    hashtable SUELTO en vez de un array de 1 elemento cuando la historia previa estaba
    vacia — PowerShell desenvuelve un array de 1 elemento al hacer `return` (mismo patron
    del gotcha #11, pero en el `return` de una funcion, no en un pipeline de
    `Where-Object`). Fix: `return ,$nueva` (operador coma unario). Mismo fix aplicado
    preventivamente en `Get-CodigosEmaDmc`.
- `AcumuladoHoy` en cada estacion: DMC directo ya trae el "Hoy" nativo de la DMC; vismet
  se calcula sumando `ValoresSerie` cuyas `TiemposSerie` caen en el dia calendario Chile
  actual (`Get-AcumuladoCalendario`, TZ `Pacific SA Standard Time`).

## Redes adicionales INIA/FDF/ESO/INACH (desde 2026-07-09)

Investigando si se podia sacar DGA de otro lado (`menuTematicoEmas` de la DMC), se encontro
que el "Boletin Pluviometrico Regional DGA-DMC-INIA" (producto RE5015) **NO trae DGA en
absoluto** (verificado en las 16 regiones, 0 estaciones con propietario "DGA") pero SI trae
INIA/FDF/ESO/INACH con codigo nacional igual al de las EMAs DMC -> se puede reusar el mismo
`visorDeDatosEma/{codigo}` para sacarles datos reales.

- **Boletin regional, publico y sin auth** (confirmado con curl real, sin cookie ni CSRF):
  `https://climatologia.meteochile.gob.cl/application/diario/boletinPluviometricoAutomaticoRegional/{region}/{yyyy}/{mm}/{dd}`
  con `{region}` en `15,01,02,03,04,05,13,06,07,16,08,09,14,10,11,12` (todas las regiones
  de Chile continental+insular, excepto Aysen=11 y Magallanes=12 que SI estan en la lista).
  Tabla HTML con codigo/nombre/provincia/comuna/**propietario**/agua-caida-diaria. Solo se
  usa para DESCUBRIR que codigos existen y su dueño — los datos reales (temp/precip/lat/lon)
  se sacan del mismo scrape por estacion que ya usa DMC directo.
- `src/RedesRegionalesDmc.ps1`: `Get-EstacionesBoletinRegion` (parsea la tabla — ojo, el HTML
  real cierra la celda "Propietario" con `</th>` en vez de `</td>`, typo del sitio no
  nuestro), `Get-CodigosRedesRegionales` (recorre las 16 regiones, excluye propietario=DMC,
  dedupe por codigo), `Get-EstacionesRegionalesDirecto` (reusa TAL CUAL las funciones de
  `DmcDirecto.ps1`: Get-DmcHtmlGzip/Get-EmaInfoDirecto/Get-EmaPrecipHoyDirecto/
  ConvertTo-EpochChile/Get-PrecipRateDirecto/Add-MuestraHistoria/Get-SerieDesdeHistoria/
  Read-EstadoDmc/Save-EstadoDmc — debe cargarse DESPUES de DmcDirecto.ps1).
- **Solo van a Capa 1 (Redes), NO a Capa 2 (EMAs):** estas estaciones no tienen temperatura
  confiable (son red climatologica/agricola, no EMA automatica completa), asi que no aportan
  isoterma. `Red = Propietario` (INIA/FDF/ESO/INACH) -> `Build-SubfoldersRedes` las agrupa en
  su propia carpeta sin ningun cambio (ya agrupaba por Red).
- Estado propio persistido en `redes_regionales_estado.json` (mismo esquema y mismo patron
  de historia/grafico que `dmc_estado.json`, archivo separado para no mezclar).
- **Escala real (verificado 2026-07-09):** 377 estaciones descubiertas (INIA 180, FDF 179,
  INACH 15, ESO 3). Tasa de exito: INIA 147/180 (82%), FDF 136/179 (76%), ESO 3/3 (100%),
  **INACH 0/15 (0%)** — las estaciones INACH (Antartica, codigo `95xxxx`) aparecen en el
  boletin pero su pagina `visorDeDatosEma` no tiene contenido real (probable estaciones
  manuales/descontinuadas sin ficha digital) — fallo estructural, no transitorio, no vale
  la pena seguir insistiendo. Tiempo total del paso: ~2.5-3 min con throttle 400ms.

## API de vismet.cr2.cl (no documentada)

- Auth: header `ckey` = hash rolling sobre la ruta `h=(h*31+char)&0xFFFFFFFF` en hex. Ver `Sign()` en `src/RedesApi.ps1`.
- `api/measure/by-measure-type/{1|2}/by-timestamp/{epoch}/by-interval/{h}` — feed principal. `organizationName` siempre null.
- `api/raw-measure/by-measure-type/{1|2}/last` — muestra rotativa pequeña, pero trae `station.altitude` y `station.organization.name` (fuente real). Se cachea entre corridas (`altitudes.json`, `organizaciones.json`).
- Cruzar por `id` numérico (estable entre endpoints), NUNCA por `nationalCode` (formatos distintos entre endpoints).
- Cualquier ruta no válida devuelve el SPA (HTML, HTTP 200) — revisar el contenido, no solo el status code.
- Redes se clasifican por formato de `nationalCode` en `Get-RedFromCode` (src/RedesApi.ps1): Agromet=`AG*`, CEAZA=`CE*`, RedMeteo=`yy:`/`zx:`, UFRO=`UFRO*`, Davis=`wl:`/formato MAC, DGA=`NNNNNNNN-X`, DMC=numérico puro.

## Rendimiento del visor

- `fetch(url, {cache:"no-cache"})` en vez de `?t=timestamp`, permite 304 si el KML no cambió.
- Parseo de KML en Web Worker (parser propio por regex, sin DOMParser — no existe en Workers). Validado idéntico a DOMParser contra datos reales.
- `buildMarkers()` construye los marcadores una vez; `applyFilters()` solo alterna visibilidad (`addLayer`/`removeLayer`) — los filtros no recrean ni re-sanitizan popups.
- `preferCanvas: true` en Leaflet (estaciones en canvas, no SVG individual).

## Convenciones de este proyecto

- Antes de escribir a los `.ps1` reales, validar la lógica en aislado con el tool de PowerShell (datos sintéticos + reales) — varios bugs sutiles de PowerShell (arrays de un elemento colapsan a escalar en contexto booleano, comas finales ambiguas en llamadas multi-línea dentro de `@(...)`) se evitaron así.
- Cambios a la clasificación de datos (ej. qué red es cada estación) deben ser aditivos y cautelosos: no reemplazar heurísticas existentes sin validar contra una fuente más confiable primero.
- Tras cualquier cambio de backend, disparar el workflow real (`workflow_dispatch` con `prueba:false`) y esperar a que termine antes de dar por hecho el cambio.
