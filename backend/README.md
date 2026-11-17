# Backend: integrante 2

Cada backend es un contenedor cuyo **servidor web es Apache httpd 2.4.69**.
Apache hace de proxy inverso hacia una pequeña aplicación en Python (`app.py`,
solo biblioteca estándar) que genera las respuestas. Cumple
[balanceador/CONTRATO_INTEGRACION.md](../balanceador/CONTRATO_INTEGRACION.md).

## Arquitectura

```text
                 red-proyecto (Docker)                contenedor backendN
                                          ┌──────────────────────────────────────────┐
 balanceador ── HTTP :80 ───────────────► │ Apache httpd :80  (PID 1, MPM event)     │
 (Apache,                                 │      │ ProxyPass / -> 127.0.0.1:8000     │
  mod_proxy_balancer)                     │      ▼ keep-alive                        │
                                          │ app.py 127.0.0.1:8000  (usuario app)     │
                                          └──────────────────────────────────────────┘
```

- Solo Apache es alcanzable desde la red. `app.py` escucha en `127.0.0.1`, así
  que nada externo puede saltarse a Apache.
- El nombre del servicio (`backend1` … `backend7`) y el puerto 80 no cambian.

| Archivo | Función |
|---|---|
| `Dockerfile` | Imagen `httpd:2.4.69` + Python 3 de Debian. Activa `mod_proxy` y `mod_proxy_http` |
| `backend.conf` | Configuración de Apache: MPM event, keep-alive, `ProxyTimeout` y `ProxyPass` hacia app.py |
| `entrypoint.sh` | Arranca app.py, espera a que responda y hace `exec httpd-foreground` |
| `app.py` | Aplicación: genera las respuestas de todos los endpoints |
| `healthcheck.py` | `GET /health` con salida 0 o 1, para Docker y el entrypoint |

### Imagen base

Se usa `httpd:2.4.69`, la misma versión y la misma imagen que el balanceador:

- El enunciado pide servidores web Apache o Nginx.
- Todo el proyecto queda con una sola versión de Apache.
- Las capas de la imagen se comparten en disco y en la descarga.

La etiqueta es exacta, para que todos construyan lo mismo. Python 3.11 viene de
los repositorios de Debian bookworm; no hay `pip install`.

### Arranque y parada

1. `entrypoint.sh` valida `BACKEND_ID` y `WORK_MAX_MS`.
2. Lanza app.py como usuario `app` (UID 10001) y espera a que responda en `127.0.0.1:8000/health`.
3. Deja un **vigilante**: si app.py muere, envía SIGTERM a Apache y el
   contenedor termina, así no se queda devolviendo 503. Con
   `restart: unless-stopped`, Docker lo vuelve a levantar.
4. `exec httpd-foreground`: Apache pasa a ser el PID 1.

`docker stop` envía SIGWINCH, la parada ordenada de Apache: las peticiones en
curso terminan, como máximo en 3 s (`GracefulShutdownTimeout 3`).

### Privilegios

| Proceso | Usuario | Por qué |
|---|---|---|
| app.py | `app` (10001), con `no_new_privs` | No necesita nada más |
| Apache, proceso padre | root | Es así en la imagen oficial: abre el puerto 80 y crea los procesos hijos |
| Apache, procesos hijos | `daemon` | Son los que atienden las peticiones; nunca corren como root |

### Concurrencia

- MPM event con `ServerLimit 8 × ThreadsPerChild 50 = MaxRequestWorkers 400`.
- Apache reutiliza las conexiones hacia app.py (keep-alive), con `ttl=30`.
- app.py usa un hilo por conexión.

Así Apache no encola peticiones antes de que lleguen a app.py, y `active` /
`peak_active` de `/metrics` reflejan la carga real.

`ProxyTimeout` se calcula como `2 × WORK_MAX_MS + 5 s` (25 s por defecto),
porque `/work` puede gastar hasta `WORK_MAX_MS` de CPU más `WORK_MAX_MS` de
espera. El balanceador corta a los 10 s (`ProxyTimeout 10`), así que en la
práctica no tiene sentido pedir más de unos 10 s por petición.

### Modo `--scale`

Además de `backend1` … `backend7`, el compose tiene un servicio `backend` (perfil
`scale`) que se puede replicar con `docker compose up --scale backend=N`. Las réplicas
no reciben `BACKEND_ID`. El entrypoint lo deduce consultando el DNS inverso de su
propia IP: el DNS interno de Docker responde `proyecto-telematicos-backend-3…`, y de ahí
sale el número 3. Así cada réplica sigue respondiendo `backendN` y Artillery, los
scripts y la interfaz pueden contar el reparto igual que en el modo normal. Uso:
`make scale N=4` (ver el README raíz).

## Endpoints

| Endpoint | Respuesta | Uso |
|---|---|---|
| `GET /` | `200`, texto plano `backendN` | Identificar qué servidor atendió la petición |
| `GET /health` | `200`, `ok backendN` | `mod_proxy_hcheck` del balanceador y healthcheck de Docker |
| `GET /work` | `200`, `backendN` después de simular carga | Pruebas de Artillery (`byrequests` vs `bybusyness`) |
| `GET /info` | `200`, JSON | Identidad: hostname (ID del contenedor), IP, uptime, configuración de `/work` |
| `GET /metrics` | `200`, JSON | Peticiones por ruta y por código, activas, pico de activas, tiempo medio y máximo de `/work` |

Todas las respuestas llevan la cabecera `X-Backend-ID: N`. Los formatos de `/`,
`/health` y `/work` no cambian porque dependen de ellos `scripts/verificar.ps1`,
`pruebas/procesador.js` y la interfaz gráfica.

En `/metrics`, `active` y `peak_active` solo cuentan el tráfico de aplicación
(`/` y `/work`). Las rutas desconocidas se agrupan como `otros`. Los contadores
viven en memoria y se reinician con el contenedor.

## Variables de entorno

| Variable | Defecto | Significado |
|---|---|---|
| `BACKEND_ID` | **obligatoria** | Número del backend; la respuesta será `backend${BACKEND_ID}` |
| `WORK_DELAY_MS` | `200` | Espera de `/work` en ms (simula E/S) |
| `WORK_CPU_MS` | `0` | Cálculo activo de `/work` en ms (simula CPU) |
| `WORK_MAX_MS` | `10000` | Tope de los valores pasados por la URL (`/work?delay_ms=800&cpu_ms=50`) |
| `PORT` | `80` | Puerto público (el de Apache); solo se informa en `/info` |

## Probar

### La imagen sola

```bash
docker build -t backend-telematicos ./backend
docker run --rm -d --name b1 -e BACKEND_ID=1 -p 127.0.0.1:8081:80 backend-telematicos
sleep 6
curl -si localhost:8081/          # 200, backend1, X-Backend-ID: 1
curl -s  localhost:8081/health    # ok backend1
time curl -s localhost:8081/work  # backend1 (~0,2 s)
curl -s  localhost:8081/info
curl -s  localhost:8081/metrics
docker inspect -f '{{.State.Health.Status}}' b1   # healthy
time docker stop b1                               # ~1 s
```

### Con el proyecto completo

Ejecuta los comandos desde la raíz del repositorio:

```bash
docker compose up -d --build
./backend/probar.sh 21                       # 7 / 7 / 7
./backend/probar.sh 14 http://localhost:8080/work

# Caída y recuperación de backend2
docker compose stop backend2;  sleep 8; ./backend/probar.sh 21   # solo backend1 y backend3, 0 fallidas
docker compose start backend2; sleep 8; ./backend/probar.sh 21   # 7 / 7 / 7

# 5 y 7 backends (--force-recreate regenera la configuración del balanceador)
BACKEND_COUNT=5 docker compose --profile cinco up -d --build --force-recreate; ./backend/probar.sh 35
BACKEND_COUNT=7 docker compose --profile siete up -d --build --force-recreate; ./backend/probar.sh 70

docker compose --profile siete down
```

[compose.backend-test.yml](compose.backend-test.yml) es el laboratorio aislado
del integrante 2. Se ejecuta con `-p backend-lab -f backend/compose.backend-test.yml`
y los mismos comandos.
