# Métricas y análisis

Fuente de datos: `pruebas/resultados/resumen.csv`, generado desde los JSON de Artillery (integrante 4).

## Regenerar tablas y gráficas
Desde la raíz del repo: `python3 scripts/generar_metricas.py` (requiere python3-matplotlib).
Salidas: `metricas/datos/tablas.md`, `metricas/datos/metricas_limpias.csv` y `metricas/graficas/*.png`.

## Definiciones
- Latencia p95/p99: tiempo de respuesta por debajo del cual queda el 95 % / 99 % de las peticiones (ms).
- Throughput: peticiones por segundo (`rps`) que reporta Artillery.
- Tasa de error: (peticiones totales - respuestas HTTP 200) / peticiones totales.
- Desbalance de reparto: (máx - mín) / media de peticiones por backend; 0 % es reparto perfecto.

## Limitaciones
- Los N usuarios llegan repartidos en 30 s; no son N usuarios simultáneos.
- El throughput coincide con la carga ofrecida: no se llegó a saturar el sistema.
- `bybusyness` no equivale a `least_conn`.
- Las ejecuciones de byrequests con 5 backends no se consideran confiables: con 500 y 1000 usuarios la latencia mínima es negativa, y con 100 usuarios el p99 (1720 ms) es mayor que el de 1000 usuarios. No se repitieron.
- No se ejecutó el escenario `caida` bajo carga con Artillery.
