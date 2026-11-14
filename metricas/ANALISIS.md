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
- No se ejecutó la prueba de caída bajo carga con Artillery. La caída y recuperación se probó de forma secuencial (60/60 respuestas correctas con health checks activos), documentada en `balanceador/GUIA_PASO_A_PASO.md`, secciones 11 a 13.
