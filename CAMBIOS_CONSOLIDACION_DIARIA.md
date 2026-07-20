# Consolidación Diaria de Alertas Telegram

## Resumen del cambio

El sistema de notificaciones pasó de **múltiples alertas por día** (una por cada corrida del cron, cada 2-5 horas) a **un resumen consolidado diario** enviado a las **20:00 UTC** (16:00 hora Chile en invierno).

## Comportamiento nuevo

### Alertas críticas (inmediatas)
- **Sismos M ≥ 6:** se envían al instante sin esperar el consolidado
- Incluyen magnitud, profundidad, coordenadas y fuente (CSN/USGS)

### Resumen consolidado (diario)
- **Hora de envío:** 20:00 UTC = 16:00 hora Chile (invierno) / 15:00 hora Chile (verano)
- **Contenido:** máximos del día para cada estación/ventana
  - Redes rojas/amarillas (precipitación ≥ 10/5 mm/h)
  - EMAs rojas/amarillas (precip + isoterma)
  - Pronóstico rojo/amarillo (ventanas de grilla Open-Meteo)
- **Formato:** emoji + categoría + conteos + top 3-5 estaciones/ventanas ordenadas por máximo del día

### Sin alertas
- Si el día fue tranquilo (sin ninguna alerta), **no se envía nada**
- Si quieres un "latido" de confirmación diario, házmelo saber

## Archivos modificados

- `src/Notificaciones.ps1` — nuevas funciones de consolidación:
  - `Read-AlertasDiarias()` — leer estado del día
  - `Save-AlertasDiarias()` — guardar estado
  - `Update-EstadoAlertas()` — actualizar máximos con datos actuales
  - `Test-EsHoraEnvio()` — detectar si es 20:00 UTC
  - `Build-ResumenAlertas-Diario()` — construir resumen consolidado
  - `Build-AlertaSismo()` — alerta crítica para sismos M≥6

- `Actualizar.ps1` — lógica de decisión:
  - Leer estado diario previo
  - Actualizar con datos de esta corrida
  - Si hay sismos M≥6 → enviar inmediato + guardar estado
  - Si es 20:00 UTC + hay alertas → enviar consolidado + guardar estado
  - Si no → solo actualizar estado para próxima ronda

- `.github/workflows/publicar.yml` — persistencia:
  - Restaurar `alertas_diarias.json` de rama `live` antes de correr
  - Guardar `alertas_diarias.json` en rama `live` después de ejecutar

## Estado persistido

**Archivo:** `alertas_diarias.json` (en rama `live`, como `dmc_estado.json`)

**Contenido:**
```json
{
  "Dia": "2026-07-20",
  "EpochCreacion": 1754....,
  "MaximosPorId": {
    "Est Talca_DGA": { "Nombre": "Est Talca", "Red": "DGA", "MaxMmH": 12.4, "Lat": -35.42, "Lon": -71.66 }
  },
  "RegionalizadasRojas": [...],
  "RegionalizadasAmarillas": [...],
  "EmasRojas": [...],
  "EmasAmarillas": [...],
  "VentanasRojas": [...],
  "VentanasAmarillas": [...],
  "SismosFuertes": [...],
  "UltimoEnvio": 1754....
}
```

## Cómo probar

### Prueba local (Windows)
```powershell
cd C:\Users\carlos.venegas\Documents\Claude\alertas-redes
$env:TELEGRAM_TOKEN = "tu_token"
$env:TELEGRAM_CHAT_ID = "tu_chat_id"
.\Actualizar.ps1
```

El script intentará enviar si:
- Es 20:00 UTC (normalmente no), O
- Hay sismos M≥6 registrados

### Prueba con modo PRUEBA (simula resumen diario)
En GitHub Actions: dispara el workflow con `prueba=true` desde la interfaz web. Esto enviará un mensaje de prueba con formato de resumen consolidado.

### Monitoreo
- Revisa el archivo `alertas_diarias.json` después de cada corrida para ver qué se acumuló
- Verifica que el timestamp `UltimoEnvio` se actualice solo cuando se envía (20:00 UTC)

## Opciones futuras (si lo deseas)

- **Cambiar hora de envío:** edita `Test-EsHoraEnvio()` en `Notificaciones.ps1`, cambia el `Hour -eq 20` a otro valor
- **Múltiples resúmenes diarios:** crear `Test-EsHoraEnvioDos()` y lógica adicional en el flujo
- **Umbral de alerta:** enviar consolidado solo si hay rojas (no amarillas)
- **Latido diario:** enviar "sin alertas" confirmando que el sistema funciona

## Rollback

Si algo no funciona, revertir es simple:
1. Revert commits en `main`
2. Restaurar versión anterior de `Actualizar.ps1` y `Notificaciones.ps1`
3. El archivo `alertas_diarias.json` puede ignorarse (es decorativo)
