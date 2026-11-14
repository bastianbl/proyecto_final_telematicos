# Backend: integrante 2

Servidor HTTP mínimo en Python (solo la biblioteca estándar) que cumple
[balanceador/CONTRATO_INTEGRACION.md](../balanceador/CONTRATO_INTEGRACION.md).

| Endpoint | Respuesta | Uso |
|---|---|---|
| `GET /` | `200`, texto plano `backendN` | Identificar qué servidor atendió la petición |
| `GET /health` | `200`, `ok backendN` | `mod_proxy_hcheck` de Apache y `HEALTHCHECK` de Docker |
| `GET /work` | `200`, `backendN` después de simular carga | Pruebas de Artillery (`byrequests` vs `bybusyness`) |

- Puerto interno **80**. Los servicios se llaman `backend1` … `backend7`.
- Imagen base fijada: `python:3.12.7-alpine3.20`, sin dependencias externas.
- Corre como usuario sin privilegios (UID 10001).
- El `Dockerfile` trae su propio `HEALTHCHECK` (cada 3 s contra `/health`).

## Variables de entorno

| Variable | Defecto | Significado |
|---|---|---|
| `BACKEND_ID` | **obligatoria** | Número del backend; la respuesta será `backend${BACKEND_ID}` |
| `WORK_DELAY_MS` | `200` | Espera de `/work` en ms (simula I/O: BD, red…) |
| `WORK_CPU_MS` | `0` | Cálculo activo de `/work` en ms (simula CPU) |
| `WORK_MAX_MS` | `10000` | Tope para valores pasados por query string |
| `PORT` | `80` | No cambiar: el balanceador espera el 80 |

Una petición puede sobrescribir los valores: `/work?delay_ms=800&cpu_ms=50`.

Para que Artillery muestre la diferencia entre algoritmos, dale a un backend
más retardo que a los demás (por ejemplo `WORK_DELAY_MS: "1000"` en
`backend1`). Con `byrequests` ese backend sigue recibiendo su parte y acumula
peticiones en espera. Con `bybusyness` Apache ve que tiene más peticiones
activas y le envía menos.

## Construir y probar solo la imagen

```bash
docker build -t backend-telematicos ./backend
docker run --rm -d --name b1 -e BACKEND_ID=1 -p 127.0.0.1:8081:80 backend-telematicos
curl localhost:8081/          # backend1
curl localhost:8081/health    # ok backend1
time curl localhost:8081/work # backend1 (~0,2 s)
docker inspect -f '{{.State.Health.Status}}' b1   # healthy
docker stop b1
```

## Probar con el balanceador real

Ejecuta los comandos desde la raíz del repositorio.
[compose.backend-test.yml](compose.backend-test.yml) es una copia de
`balanceador/compose.test.yml` que usa esta imagen en lugar de `test-fixtures/`.

```bash
# 3 backends
BACKEND_COUNT=3 docker compose -p backend-lab -f backend/compose.backend-test.yml up -d --build
./backend/probar.sh 21                     # 7 / 7 / 7

# Caída y recuperación de backend2
docker compose -p backend-lab -f backend/compose.backend-test.yml stop backend2
sleep 8; ./backend/probar.sh 21            # solo backend1 y backend3, 0 fallidas
docker compose -p backend-lab -f backend/compose.backend-test.yml start backend2
sleep 8; ./backend/probar.sh 21            # 7 / 7 / 7 otra vez

# 5 y 7 backends (perfiles; --force-recreate regenera la config de Apache)
BACKEND_COUNT=5 docker compose -p backend-lab -f backend/compose.backend-test.yml --profile cinco up -d --build --force-recreate
./backend/probar.sh 35                     # 7 c/u
BACKEND_COUNT=7 docker compose -p backend-lab -f backend/compose.backend-test.yml --profile siete up -d --build --force-recreate
./backend/probar.sh 70                     # 10 c/u

# Limpiar
docker compose -p backend-lab -f backend/compose.backend-test.yml --profile siete down
```
