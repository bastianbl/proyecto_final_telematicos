# Interfaz gráfica: integrante 2

Página web servida por **nginx** para ver el balanceador funcionando en vivo.

## Uso

La interfaz es parte del sistema: está en `docker-compose.yml` con el perfil `interfaz`.

```bash
make up                                   # Linux/macOS/Git Bash (incluye la interfaz)
.\scripts\compose.ps1 -Action Interfaz    # Windows
# o directamente: docker compose --profile interfaz up -d --build
```

Abre `http://localhost:8090`. En la cabecera, **Balanceador: Principal** está
seleccionado. Es el balanceador del proyecto (`:8080`), **el mismo que usan
Artillery, `verificar.ps1` y los demás scripts**. Por eso, mientras corre una prueba
de carga, la interfaz la muestra en vivo.

### Modo demostración 3 / 5 / 7

Para cambiar entre 3, 5 y 7 backends desde la página sin reiniciar nada:

```bash
make demo-escenarios
# o: docker compose -f docker-compose.yml -f interfaz/compose.interfaz.yml up -d --build --wait
```

Aparecen los botones **demo 3 · demo 5 · demo 7**. Cada uno usa un balanceador
de demostración (`balanceador3/5/7`) con exactamente esos backends, y la cantidad
de peticiones se ajusta a la de las pruebas del proyecto (21, 35, 70). `make up`
vuelve al modo normal.

Otras funciones:

- **Ruta** `/` o `/work`, peticiones **simultáneas** (1-6) y `delay_ms` opcional.
- **Modo continuo:** una petición cada 300 ms. Sirve para ver en vivo la caída
  (`docker compose stop backend2`) y la recuperación (`docker compose start backend2`).
- **Tarjetas por backend**, actualizadas cada 2 s: sano o sin respuesta,
  contenedor, IP, uptime, peticiones atendidas, activas ahora, pico de activas y
  tiempo medio de `/work`.

## Métricas y resultados

- **Métricas del balanceador en vivo:** cada 2 s se lee `/server-status?auto` del
  balanceador elegido (por defecto, el principal). Muestra peticiones totales, peticiones/s (calculadas entre
  dos lecturas), duración media por petición, tráfico, workers ocupados y libres,
  uptime y los fallos que vio el panel. Incluye las propias consultas del panel
  (~1 por segundo). Requiere que `balancer.conf` permita las redes de Docker
  (`Require ip ... 172.16.0.0/12`).
- **Resultados de las pruebas:**
  - gráfica de barras (`byrequests` frente a `bybusyness`) y tabla de
    `metricas/datos/metricas_limpias.csv`, filtradas por número de backends y
    métrica. Las mediciones marcadas como sospechosas salen en rojo;
  - las gráficas PNG de `metricas/graficas/`;
  - el texto de `metricas/ANALISIS.md`;
  - las corridas nuevas de `make carga` / `make concurrencia`
    (`pruebas/resultados/make/*.json`).

  Se montan como volúmenes de **solo lectura**: la interfaz no puede modificar
  ningún resultado.

## Cómo funciona

[compose.interfaz.yml](compose.interfaz.yml) se suma a `docker-compose.yml` sin modificarlo:

- Deja **los 7 backends siempre encendidos**: anula sus perfiles con `!reset`.
- Añade **`balanceador3`, `balanceador5` y `balanceador7`**: la misma imagen del
  integrante 1 con `BACKEND_COUNT` fijo. Apache genera su lista de miembros al
  arrancar, así que en lugar de reiniciar un balanceador para cambiar el
  número, hay tres listos y la página elige a cuál enviar las peticiones.
- El `balanceador` principal (`localhost:8080`), que usan los scripts y
  Artillery, sigue igual y se configura con `.env`.
- El algoritmo de los tres balanceadores es `BALANCER_METHOD` del `.env`.

```text
navegador ──► nginx :8090 ──┬─ /lb/3/… ──► balanceador3 ──► backend1..3
                            ├─ /lb/5/… ──► balanceador5 ──► backend1..5
                            ├─ /lb/7/… ──► balanceador7 ──► backend1..7
                            └─ /directo/N/{health,info,metrics} ──► backendN (sin balanceador)
```

| Ruta del navegador | nginx la envía a | Para qué |
|---|---|---|
| `/` | archivos de `html/` | La página |
| `/panel-config.json` | respuesta generada desde el entorno | Método de balanceo y escenario inicial |
| `/lb/{3,5,7}/<ruta>` | `http://balanceador{3,5,7}:80/<ruta>` | Camino real de un usuario: Apache elige el backend |
| `/api/<ruta>` | `http://balanceador:80/<ruta>` | El balanceador principal (se conserva) |
| `/directo/N/{health,info,metrics}` | `http://backendN:80/...` | Observar cada backend por separado |
| `/datos/metricas/…`, `/datos/resultados/…` | Archivos de `metricas/` y `pruebas/resultados/` (solo lectura, listado en JSON) | Resultados de las pruebas |

Decisiones:

- **Mismo origen.** La página y la API salen de `localhost:8090`, así el navegador
  no bloquea las peticiones y no hace falta configurar CORS en el backend.
- **`resolver 127.0.0.11` y `proxy_pass` con variable.** nginx resuelve el nombre
  en cada petición y no solo al arrancar, así sigue funcionando si un contenedor
  se recrea con otra IP.
- **Solo se aceptan nombres permitidos.** `/lb` solo acepta 3, 5 o 7, y `/directo`
  solo rutas de monitoreo de `backend1`..`backend7`. No es un proxy abierto.
- **Content-Security-Policy `default-src 'self'`:** no se pueden cargar scripts de
  otros orígenes.
- **Imagen fijada:** `nginx:1.27.3-alpine`.
- **Límite del navegador:** máximo 6 conexiones simultáneas por servidor. Sirve
  para demostrar el comportamiento, pero no reemplaza a Artillery.
