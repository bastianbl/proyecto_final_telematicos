# Interfaz gráfica: integrante 2

Página web servida por **nginx** que muestra el balanceador funcionando en vivo:

- **Enviar peticiones** a `/` o `/work` a través de Apache: cantidad, simultáneas
  (1-6) y `delay_ms` opcional. Muestra barras de reparto por backend, correctas,
  fallidas, latencia media y las últimas respuestas.
- **Modo continuo:** una petición cada 300 ms. Sirve para ver en vivo la caída y
  la recuperación de un backend mientras se ejecuta `docker compose stop backend2`.
- **Tarjetas por backend**, actualizadas cada 2 s: sano o sin respuesta,
  contenedor, IP, uptime, peticiones atendidas, activas ahora, pico de activas y
  tiempo medio de `/work`.

No usa librerías ni CDN: funciona sin internet.

## Cómo funciona nginx aquí

| Ruta del navegador | nginx la envía a | Para qué |
|---|---|---|
| `/` | archivos de `html/` | La página |
| `/panel-config.json` | respuesta generada desde `BACKEND_COUNT` y `BALANCER_METHOD` | Saber qué escenario mostrar |
| `/api/<ruta>` | `http://balanceador:80/<ruta>` | Camino real de un usuario: Apache elige el backend |
| `/directo/N/{health,info,metrics}` | `http://backendN:80/...` sin pasar por Apache | Observar cada backend por separado |

Decisiones:

- **Mismo origen.** La página y la API salen de `localhost:8090`, así el navegador
  no bloquea las peticiones y no hace falta configurar CORS en el backend.
- **`resolver 127.0.0.11` y `proxy_pass` con variable.** nginx resuelve el nombre
  en cada petición y no solo al arrancar. Así arranca aunque `backend4`..`backend7`
  no existan, y sigue funcionando si el balanceador se recrea con otra IP.
- **`/directo` solo permite rutas de monitoreo** y nombres `backend1`..`backend7`.
  No es un proxy abierto y no permite enviar `/work` saltándose al balanceador.
- **Content-Security-Policy `default-src 'self'`:** no se pueden cargar scripts de
  otros orígenes.
- **Imagen fijada:** `nginx:1.27.3-alpine`.
- **Límite del navegador:** máximo 6 conexiones simultáneas por servidor. Por eso
  sirve para demostrar el comportamiento, pero no reemplaza a Artillery.

## Probar

Desde la raíz del repositorio, con el laboratorio del backend:

```bash
BACKEND_COUNT=3 docker compose -p backend-lab -f backend/compose.backend-test.yml up -d --build
xdg-open http://localhost:8090
```

## Para el integrante 3 (`docker-compose.yml` raíz)

No modifiqué el compose principal. Para añadir la interfaz, bastaría con este
servicio. El perfil hace que no arranque por defecto, así no afecta a las pruebas:

```yaml
  interfaz:
    build:
      context: ./interfaz
    profiles: ["interfaz"]
    ports:
      - "127.0.0.1:${PANEL_PORT:-8090}:80"
    environment:
      BACKEND_COUNT: "${BACKEND_COUNT:-3}"
      BALANCER_METHOD: "${BALANCER_METHOD:-byrequests}"
    depends_on:
      balanceador:
        condition: service_started
    networks:
      - red-proyecto
```
