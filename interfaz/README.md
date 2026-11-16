# Interfaz gráfica: integrante 2

Página web servida por **nginx** para ver el balanceador funcionando en vivo.

## Uso

Desde la raíz del repositorio, un solo comando:

```bash
docker compose -f docker-compose.yml -f interfaz/compose.interfaz.yml up -d --build
xdg-open http://localhost:8090
```

En la cabecera eliges **Backends: 3 · 5 · 7**. Al elegir un número:

- aparecen exactamente esas tarjetas de backend;
- las peticiones van a un balanceador que tiene exactamente esos backends;
- la cantidad de peticiones se ajusta a la de las pruebas del proyecto
  (21 → 7 c/u, 35 → 7 c/u, 70 → 10 c/u). Pulsa **Enviar**.

Cambiar de escenario es inmediato: no hay que editar archivos ni reiniciar nada.

Otras funciones:

- **Ruta** `/` o `/work`, peticiones **simultáneas** (1-6) y `delay_ms` opcional.
- **Modo continuo:** una petición cada 300 ms. Sirve para ver en vivo la caída
  (`docker compose stop backend2`) y la recuperación (`docker compose start backend2`).
- **Tarjetas por backend**, actualizadas cada 2 s: sano o sin respuesta,
  contenedor, IP, uptime, peticiones atendidas, activas ahora, pico de activas y
  tiempo medio de `/work`.

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
