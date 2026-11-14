# Balanceador de carga web con Apache `mod_proxy_balancer`

Proyecto 6. Un balanceador **Apache HTTP Server 2.4** reparte las peticiones entre varios backends en contenedores **Docker**, y su rendimiento se evalúa con **Artillery**.

- Escenarios con **3, 5 y 7 backends**.
- Dos algoritmos: **`byrequests`** (round-robin ponderado) y **`bybusyness`** (menos peticiones activas). `bybusyness` **no** equivale exactamente a *least connections*.
- **Monitoreo activo** de salud con `mod_proxy_hcheck` (`GET /health` cada 2 s): un backend caído sale del reparto y vuelve a entrar solo, sin reiniciar Apache.
- Pruebas de carga de 50, 100, 500 y 1000 usuarios, y escenario de caída de un backend.

## Arquitectura

```text
                          red Docker "red-proyecto" (privada)
  Cliente ──► 127.0.0.1:8080 ──► balanceador (Apache :80) ──┬──► backend1 :80
  (host)                                                     ├──► backend2 :80
                                                             ├──► backend3 :80
                  Artillery (perfil "artillery") ───────────►│    backend4..7 (perfiles "cinco"/"siete")
```

- Solo el balanceador se publica en el host, y únicamente en `127.0.0.1` (puerto `BALANCER_PORT`, por defecto 8080).
- Los backends se llaman `backend1` … `backend7`, escuchan en el puerto 80 interno y comparten la red con Apache.
- `/balancer-manager` y `/server-status` están restringidos con `Require local`: desde el host responden **403** (es lo esperado).

## Requisitos

- Windows 10/11 con **Docker Desktop** (contenedores Linux) y **PowerShell**.
- **Git**.
- **Python 3** para `scripts\resumen.py` y `scripts\generar_metricas.py` (ver `metricas/README.md`).

## Inicio rápido

```powershell
git clone https://github.com/bastianbl/proyecto_final_telematicos.git
cd proyecto_final_telematicos
Copy-Item .env.example .env
.\scripts\compose.ps1 -Action Up
.\scripts\verificar.ps1
Invoke-RestMethod http://localhost:8080/        # responde "backendN"
```

Apagar (elimina solo los contenedores y la red de este proyecto):

```powershell
.\scripts\compose.ps1 -Action Down
```

## Configuración (`.env`)

| Variable | Por defecto | Descripción |
|---|---|---|
| `BALANCER_PORT` | `8080` | Puerto del host donde se publica Apache |
| `BACKEND_COUNT` | `3` | Cantidad de backends: `3`, `5` o `7` |
| `BALANCER_METHOD` | `byrequests` | `byrequests` o `bybusyness` |
| `WORK_DELAY_MS` | `200` | Espera simulada (E/S) de `GET /work` |
| `WORK_CPU_MS` | `0` | Cálculo activo (CPU) de `GET /work` |
| `WORK_MAX_MS` | `10000` | Tope para los valores pasados por la URL |
| `ARTILLERY_IMAGE` | `artilleryio/artillery:latest` | Imagen de Artillery (se puede fijar una versión) |

## Cambiar de escenario o de algoritmo

Apache genera su lista de backends **al iniciar**, por eso cualquier cambio requiere `Restart`:

```powershell
.\scripts\compose.ps1 -Action Restart -BackendCount 3 -BalancerMethod byrequests
.\scripts\compose.ps1 -Action Restart -BackendCount 5 -BalancerMethod byrequests
.\scripts\compose.ps1 -Action Restart -BackendCount 7 -BalancerMethod bybusyness
```

Otras acciones: `-Action Status` (estado), `-Action Logs` (logs en vivo), `-Action Artillery` (smoke test).

## Endpoints de los backends

| Ruta | Respuesta |
|---|---|
| `GET /` | `backendN` (identifica qué servidor atendió) |
| `GET /health` | `200 ok backendN` (lo consultan Apache y Docker) |
| `GET /work` | Simula carga y responde `backendN`. Admite `?delay_ms=500&cpu_ms=50` |

## Verificación del sistema

Con el sistema levantado:

```powershell
.\scripts\verificar.ps1                       # usa BACKEND_COUNT de .env
.\scripts\verificar.ps1 -BackendCount 7       # fuerza el escenario esperado
```

Comprueba contenedores (`running`/`healthy`), `httpd -t`, módulos de Apache, que el pool coincida con `BACKEND_COUNT`, `GET /health`, `GET /`, `GET /work`, que **todos** los backends reciban tráfico y que los endpoints administrativos devuelvan 403. Termina con código 0 si todo pasa y guarda el informe en `evidencias\logs\`.

## Prueba de caída y recuperación

Con el sistema levantado:

```powershell
.\scripts\prueba_caida.ps1                                   # detiene backend2 durante la prueba
.\scripts\prueba_caida.ps1 -BackendCount 7 -Backend 4 -Duracion 60 -SegundoCaida 15 -SegundoRecuperacion 35
```

El script envía peticiones continuas, detiene el backend elegido, lo vuelve a iniciar **sin reiniciar Apache** y mide errores, cuándo deja de recibir tráfico y cuándo se reincorpora. Todo se guarda en `evidencias\logs\`. Es una prueba secuencial; para caídas bajo carga concurrente usa Artillery:

```powershell
.\scripts\correr_pruebas.ps1 -BackendCount 3 -BalancerMethod byrequests -Escenario caida
# durante los 120 s, en otra terminal:
docker compose stop backend2
docker compose start backend2
```

Anota la hora exacta de cada acción para el análisis.

## Pruebas de carga y métricas

```powershell
.\scripts\correr_pruebas.ps1 -BackendCount 3 -BalancerMethod byrequests      # 50, 100, 500 y 1000 usuarios
python scripts\resumen.py
```

- Escenarios y detalles de Artillery: `pruebas/README_PRUEBAS.md`.
- Definición de métricas (p95/p99, throughput, tasa de errores), tablas y gráficas: `metricas/README.md`.
- Comparación y conclusiones: `metricas/ANALISIS.md`.

Los resultados reportados deben salir de ejecuciones reales (`pruebas/resultados/`); no se inventan datos.

## Estructura del repositorio

```text
proyecto_final_telematicos/
├── docker-compose.yml        Integración (Integrante 3)
├── .env.example              Variables de ejemplo
├── INTEGRACION.md            Guía de integración Docker
├── README.md                 Este archivo (Integrante 6)
├── backend/                  Backend Python y healthcheck (Integrante 2)
├── balanceador/              Apache, contrato y guía (Integrante 1)
├── pruebas/                  Escenarios Artillery y resultados (Integrante 4)
├── metricas/                 Datos, tablas, gráficas y análisis (Integrante 5)
├── scripts/                  Operación y pruebas (Integrantes 3, 4, 5 y 6)
└── evidencias/               Capturas y logs (Integrante 6)
```

## Responsables

| Integrante | Nombre | Área |
|---|---|---|
| 1 | _(por completar)_ | Balanceador Apache |
| 2 | _(por completar)_ | Backends y Docker |
| 3 | _(por completar)_ | Docker Compose e integración |
| 4 | _(por completar)_ | Pruebas Artillery |
| 5 | _(por completar)_ | Métricas y análisis |
| 6 | _(por completar)_ | Monitoreo, README, evidencias y entrega |

## Limitaciones conocidas

- El monitoreo activo reduce los errores durante un fallo, pero **no garantiza** que todas las peticiones se completen: una petición que llega justo cuando el backend cae, antes de que Apache lo detecte (≈2 s), puede fallar.
- Las pruebas secuenciales (`verificar.ps1`, `prueba_caida.ps1`) comprueban funcionamiento, **no rendimiento**. La latencia p95/p99 y el throughput se miden con Artillery.
- Con peticiones cortas y secuenciales, `byrequests` y `bybusyness` pueden dar el mismo reparto; la diferencia solo se aprecia con carga concurrente.

## Problemas habituales

| Síntoma | Qué revisar |
|---|---|
| Docker no responde | Abrir Docker Desktop y comprobar `docker info` |
| Puerto 8080 ocupado | Cambiar `BALANCER_PORT` en `.env` |
| Un backend aparece sano pero no recibe tráfico | Probar `GET /health` y revisar `evidencias\logs` de Apache |
| Error `^M` al ejecutar `entrypoint.sh` | Saltos de línea CRLF: mantener los `.gitattributes` |
| `BACKEND_COUNT` no coincide con los backends | `compose.ps1 -Action Restart -BackendCount N` y luego `verificar.ps1` |
| Respuestas 503 de Apache | Revisar red compartida, nombres `backendN` y salud de los backends |
| `/balancer-manager` da 403 desde el host | Es lo previsto (`Require local`) |

## Evidencias y validación

Capturas, logs y la lista de validación desde cero están en `evidencias/README.md`.
Documentación del balanceador: `balanceador/CONTRATO_INTEGRACION.md` y `balanceador/GUIA_PASO_A_PASO.md`.
