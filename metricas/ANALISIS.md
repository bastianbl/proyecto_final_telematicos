# Análisis de resultados

## Resultados confiables
- 24 ejecuciones (2 algoritmos x 3, 5 y 7 backends x 50, 100, 500 y 1000 usuarios), 29.700 peticiones en total y 0 errores.
- Excluyendo byrequests con 5 backends, la latencia media queda entre 202 y 216 ms y el p95 entre 206,5 y 257,3 ms. El piso de ~200 ms corresponde al trabajo simulado en `/work`, así que el sobrecosto del balanceador es de pocos milisegundos.
- El p99 es más variable que el p95 (214,9 a 608 ms en esas mismas ejecuciones): es sensible a picos aislados.
- Reparto: byrequests fue exacto con 3 y 5 backends (0 % de desbalance). bybusyness mostró desviaciones pequeñas con 3 backends (hasta 5,4 %). Con 7 backends y pocas peticiones, la desviación (hasta 4,67 %) es de redondeo, porque 150 peticiones no se dividen en partes iguales entre 7.

## Lo que no se puede concluir
- Que un algoritmo sea mejor que otro en latencia: con backends iguales y sin saturación las diferencias son pequeñas, y las ejecuciones de byrequests con 5 backends no son confiables.
- Que más backends aumenten la capacidad: el throughput coincidió con la carga ofrecida (≈5, 10, 49 y 98 req/s), es decir, nunca se llegó al límite del sistema.

## Limitaciones
- Los N usuarios virtuales llegan repartidos en 30 s; no son N usuarios simultáneos.
- bybusyness no equivale a least_conn.
- Las ejecuciones de byrequests con 5 backends muestran mediciones anómalas (latencia mínima negativa con 500 y 1000 usuarios, p99 de 1720 ms con 100 usuarios) y no se repitieron. En las gráficas esos puntos deben leerse con esta reserva.
- **Las pausas entre peticiones no se aplicaron** (comprobado el 16/11/2026, ver también `pruebas/README_PRUEBAS.md`).
  - Qué pasó: `carga.yml` define `think: 0.5` entre las 3 peticiones de cada usuario. Con la versión de Artillery usada, ese valor produce `TimeoutNaNWarning ... Timeout duration was set to 1`: cada pausa duró ~1 ms. El aviso aparece en las 24 de 24 corridas, y la sesión media de cada usuario fue de ~0,67 s (625-935 ms), no de ~1,6 s.
  - Cómo afecta: según la ley de Little (simultáneos ≈ llegadas/s × duración), hubo unos **1, 2, 11 y 23 usuarios simultáneos** en las cargas de 50, 100, 500 y 1000, frente a ~3, 5, 27 y 53 previstos. Las peticiones en curso nunca pasaron de unas 20 entre todos los backends, lo que explica que no se llegara a saturar el sistema.
  - Por qué los resultados siguen siendo válidos como comparación: el defecto es idéntico en todas las corridas (mismo escenario y versión, mismo patrón de peticiones), así que la comparación entre 3/5/7 backends y entre algoritmos es justa. Además, lo que se mide por petición (latencia, errores, reparto) no depende de la pausa. No sirven, en cambio, para conclusiones de capacidad o saturación.
- No se ejecutó la prueba de caída bajo carga con Artillery. La caída y recuperación se probó de forma secuencial (60/60 respuestas correctas con health checks activos), documentada en `balanceador/GUIA_PASO_A_PASO.md`, secciones 11 a 13.
