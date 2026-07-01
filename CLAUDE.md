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
