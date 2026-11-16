# Balanceador de carga web con Apache `mod_proxy_balancer`

Proyecto 6. Un balanceador **Apache HTTP Server 2.4** reparte las peticiones entre varios backends en contenedores **Docker**, y su rendimiento se evalúa con **Artillery**.

- Escenarios con **3, 5 y 7 backends**.
- Dos algoritmos: **`byrequests`** (round-robin ponderado) y **`bybusyness`** (menos peticiones activas). `bybusyness` **no** equivale exactamente a *least connections*.
- **Monitoreo activo** de salud con `mod_proxy_hcheck` (`GET /health` cada 2 s): un backend caído sale del reparto y vuelve a entrar solo, sin reiniciar Apache.
- Pruebas de carga de 50, 100, 500 y 1000 usuarios, y escenario de caída de un backend.

## Recorrido completo: un solo sistema

Todo el proyecto es **un único sistema**: un `docker-compose.yml`, un balanceador
principal (`localhost:8080`) y una interfaz (`localhost:8090`) que lo observa. El
trabajo de cada integrante es una etapa de este recorrido, que sirve también de
guion para la sustentación:

| # | Paso | Linux / macOS / Git Bash | Windows (PowerShell) | Qué se ve | Parte de |
|---|---|---|---|---|---|
| 1 | Levantar todo | `make up` | `.\scripts\compose.ps1 -Action Interfaz` | Balanceador, backends e interfaz `healthy` | 3 (integración) |
| 2 | Verificar | `make verificar` | `.\scripts\verificar.ps1` | Salud, endpoint de estado y reparto 7/7/7 | 6 (verificación) |
| 3 | Ver el balanceo | abrir `http://localhost:8090` → **Principal** → **Enviar** | igual | Barras de reparto y una tarjeta por backend (contenedor, IP, peticiones activas) | 1 (Apache) y 2 (backends) |
| 4 | Caída y recuperación | **Modo continuo** + `docker compose stop backend2` / `start backend2` | igual | La tarjeta pasa a rojo y vuelve; 0 fallos | 1 (`mod_proxy_hcheck`) y 2 (healthcheck) |
| 5 | Estado de Apache antes de la carga | `make estado ETIQUETA=antes` | `.\scripts\capturar_estado.ps1 -Etiqueta antes` | `/balancer-manager` y `/server-status` guardados en `evidencias/logs/` | 1 y 6 |
| 6 | Carga con Artillery | `make carga CARGA=carga100` | `.\scripts\correr_pruebas.ps1 -BackendCount 3 -BalancerMethod byrequests -Cargas 100 -SinReiniciar` | **En vivo en la interfaz**: suben las peticiones/s, las activas por backend y el reparto | 4 (pruebas) |
| 7 | Estado de Apache después | `make estado ETIQUETA=despues` | `.\scripts\capturar_estado.ps1 -Etiqueta despues` | Comparación antes/después | 1 y 6 |
| 8 | Resultados y análisis | sección "Resultados de las pruebas" de la interfaz | `python scripts\resumen.py` y `python scripts\generar_metricas.py` | Gráfica `byrequests` vs `bybusyness`, tabla, gráficas PNG y conclusiones | 4 y 5 (métricas) |
| 9 | Evidencias y apagado | `make down` | `.\scripts\compose.ps1 -Action Down` | Capturas y logs en `evidencias/`; log de reparto en `logs/balanceador/` | 6 |

Atajo para la sustentación: `make demo` ejecuta los pasos 1 y 2 e indica qué abrir.

```text
  .env ─► docker-compose.yml ─► balanceador (Apache) ─► backend1..N (Apache → app.py)
              │                     │      ▲
              │                     │      └── Artillery (carga) ─► pruebas/resultados/ ─► scripts/resumen.py ─► metricas/
              │                     │                                                                            │
              └─► interfaz (nginx) ─┴─ observa en vivo: reparto, backends, /server-status ◄──────────────────────┘ muestra resultados
```

Cada carpeta conserva su documentación técnica (`balanceador/`, `backend/`, `pruebas/`,
`metricas/`, `interfaz/`, `evidencias/`), pero **la forma de ejecutar el proyecto es la de
esta tabla**. Los archivos `balanceador/compose.test.yml` y `backend/compose.backend-test.yml`
son laboratorios aislados que usó cada integrante para probar su parte por separado; no
son la forma de ejecutar el proyecto.

## Arquitectura

```text
 HOST (tu equipo)                    red Docker "red-proyecto" (bridge, privada)
 ───────────────────────────────────────────────────────────────────────────────────────────
                                    ┌───────────────────────────┐
 navegador / curl ─ 127.0.0.1:8080 ►│ balanceador               │  Apache 2.4 + mod_proxy_balancer
   /                                │ (Apache :80)              │  mod_proxy_hcheck: GET /health cada 2 s
   /balancer-manager  (estado)      │                           │──┬──► backend1 :80 ┐ Apache :80
   /server-status?auto (métricas)   └─────────────┬─────────────┘  ├──► backend2 :80 │ → app.py
                                                  │                ├──► backend3 :80 │ (127.0.0.1:8000)
 ./logs/balanceador/  ◄── volumen ────────────────┘                └──► backend4..7  ┘ perfiles cinco/siete
   balanceo_detallado.log                                                o backend × N (perfil scale,
                                    ┌───────────────────────────┐          docker compose --scale)
 ./pruebas/ ──── volumen (ro) ─────►│ artillery (perfil         │
 ./pruebas/resultados/ ◄─ volumen ──│ "artillery", ejecución    │──► http://balanceador/work
                                    │ puntual)                  │
                                    └───────────────────────────┘
```

- Solo el balanceador se publica en el host, y únicamente en `127.0.0.1` (puerto `BALANCER_PORT`, por defecto 8080).
- Los backends se llaman `backend1` … `backend7`, escuchan en el puerto 80 interno y comparten la red con Apache. Cada backend es Apache httpd haciendo de proxy a una aplicación Python (`backend/README.md`).
- Cada servicio tiene su propio Dockerfile con imagen base fija y documentada: `balanceador/Dockerfile` (`httpd:2.4.69`), `backend/Dockerfile` (`httpd:2.4.69` + Python 3) y `pruebas/Dockerfile` (`artilleryio/artillery:2.0.34`).
- `/balancer-manager` y `/server-status` responden **200 desde el equipo local** (`Require ip 127.0.0.1 172.16.0.0/12 192.168.65.0/24`). No son accesibles desde otras máquinas porque el puerto solo se publica en `127.0.0.1`.

## Requisitos

- Windows 10/11 con **Docker Desktop** (contenedores Linux) y **PowerShell**.
- **Git**.
- **Python 3** para `scripts\resumen.py` y `scripts\generar_metricas.py` (ver `metricas/README.md`).
- **Linux o macOS** (alternativa): Docker Engine o Docker Desktop, `make`, `bash` y `curl`. En Windows también se puede usar `make` desde WSL o Git Bash (`winget install ezwinports.make`).

## Despliegue paso a paso

Windows (PowerShell), desde la raíz del repositorio:

1. `Copy-Item .env.example .env` y ajustar `.env` si hace falta (ver la tabla de variables).
2. `.\scripts\compose.ps1 -Action Up` construye las imágenes y levanta el balanceador y los backends.
3. `.\scripts\compose.ps1 -Action Status`: todos los servicios deben estar `healthy`.
4. `.\scripts\verificar.ps1` debe terminar con todo en `OK`.
5. `.\scripts\compose.ps1 -Action Artillery` ejecuta la prueba rápida de Artillery.
6. `.\scripts\compose.ps1 -Action Down` apaga todo.

Linux, macOS o Git Bash (Makefile), desde la raíz:

1. `cp .env.example .env`
2. `make up` construye y levanta el escenario de `.env`, esperando a que todo esté `healthy`.
3. `make ps` muestra el estado; `make verificar` comprueba `/health`, el endpoint de estado y el reparto (7 peticiones por backend).
4. `make smoke` ejecuta la prueba rápida de Artillery; `make carga CARGA=carga100` ejecuta una carga de `pruebas/carga.yml`.
5. `make down` apaga todo.

Sin `make` ni PowerShell, los comandos equivalentes son `docker compose up -d --build --wait`, `docker compose ps` y `docker compose down`.

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
| `BACKEND_MODE` | `fijo` | `fijo` (`backend1..N`) o `scale` (réplicas con `--scale`); lo pone `make scale` |

Artillery ya no se configura en `.env`: usa su propia imagen con versión fija (`pruebas/Dockerfile`). Si tu `.env` aún tiene `ARTILLERY_IMAGE`, se ignora.

## Cambiar de escenario o de algoritmo

Apache genera su lista de backends **al iniciar**, por eso cualquier cambio requiere `Restart`:

```powershell
.\scripts\compose.ps1 -Action Restart -BackendCount 3 -BalancerMethod byrequests
.\scripts\compose.ps1 -Action Restart -BackendCount 5 -BalancerMethod byrequests
.\scripts\compose.ps1 -Action Restart -BackendCount 7 -BalancerMethod bybusyness
```

Otras acciones: `-Action Status` (estado), `-Action Logs` (logs en vivo), `-Action Artillery` (smoke test).

Con el Makefile, basta cambiar `BACKEND_COUNT` y `BALANCER_METHOD` en `.env` y ejecutar `make up`; el perfil `cinco` o `siete` se elige solo.

## Escalar con `docker compose up --scale backend=N`

Además de `backend1` … `backend7`, el compose define un servicio **`backend`** (perfil `scale`) que se puede replicar:

```bash
make scale N=4          # 1 a 20 réplicas
make verificar N=4      # reparto: 7 peticiones por réplica
make up                 # volver al modo normal (backend1..N de .env)
```

`make scale N=4` ejecuta dos pasos:

1. `docker compose --profile scale up -d --wait --no-deps --scale backend=4 backend`: crea 4 réplicas. Cada una deduce su número de su nombre (`proyecto-telematicos-backend-3` → `backend3`).
2. Recrea el balanceador con `BACKEND_MODE=scale BACKEND_COUNT=4`.

**Por qué hace falta el paso 2.** Apache necesita **un `BalancerMember` por réplica** para repartir entre ellas y vigilar la salud de cada una. Un único `BalancerMember "http://backend:80"` no bastaría: el DNS de Docker devuelve las IPs de todas las réplicas, pero Apache resuelve el nombre y reutiliza sus conexiones, así que no repartiría de forma controlada ni detectaría la caída de una réplica concreta. Como Apache lee su lista de miembros al arrancar, después de escalar hay que recrearlo.

**Limitaciones:**
- Al subir o bajar réplicas, la recreación del balanceador **corta el servicio unos 1-3 s**.
- `scripts\verificar.ps1` y `prueba_caida.ps1` trabajan con el modo normal (`backend1..N`). En la interfaz, el reparto y las métricas en vivo funcionan también en modo `scale`, pero las tarjetas por backend no (consultan `backendN` por nombre).
- En modo `scale` se detienen `backend1..backend7`; `make up` los vuelve a levantar y retira las réplicas.

## Endpoint de estado del balanceador

Desde el equipo local, con el sistema levantado:

| URL | Qué muestra |
|---|---|
| `http://localhost:8080/balancer-manager` | Por cada `BalancerMember`: estado (`Init Ok`, `Err`, `Hcheck`…), peticiones atendidas (`Elected`), peticiones activas (`Busy`), carga y bytes enviados/recibidos (`To`/`From`), además del algoritmo activo. También **permite cambiar** la configuración en caliente: úsalo solo para observar |
| `http://localhost:8080/server-status?auto` | Métricas de Apache en texto: peticiones totales (`Total Accesses`), tráfico (`Total kBytes`), peticiones por segundo (`ReqPerSec`), duración media (`DurationPerReq`), workers ocupados y libres (`BusyWorkers`/`IdleWorkers`) y tiempo activo |
| `http://localhost:8080/server-status` | Lo mismo en HTML, con cada conexión en curso (`ExtendedStatus On`) |

Los **fallos** se ven en el estado `Err` de cada miembro en `balancer-manager`, y en el log `balanceo_detallado.log` (respuestas `status=5xx`).

Capturas para el informe, antes y después de una carga. Se guardan en `evidencias/logs/estado_<etiqueta>_<fecha>/`:

```bash
make estado ETIQUETA=antes && make carga CARGA=carga100 && make estado ETIQUETA=despues
```
```powershell
.\scripts\capturar_estado.ps1 -Etiqueta antes
.\scripts\correr_pruebas.ps1 -BackendCount 3 -BalancerMethod byrequests -Cargas 100 -SinReiniciar
.\scripts\capturar_estado.ps1 -Etiqueta despues
```

## Logs y resultados

| Qué | Dónde (en el host) |
|---|---|
| Qué backend atendió cada petición, código y duración | `logs/balanceador/balanceo_detallado.log` (volumen; sobrevive a `down`) |
| Access y error log de Apache, logs de los backends | `docker compose logs <servicio>` (se pierden con `down`) |
| Resultados de Artillery publicados | `pruebas/resultados/*.json` y `.txt`, y `resumen.csv` |
| Resultados de `make carga` / `make concurrencia` | `pruebas/resultados/make/` (no entran en `resumen.csv`) |
| Verificaciones, caídas y capturas de estado | `evidencias/logs/` |

Contar el reparto por backend a partir del log:

```bash
grep -o 'backend=[^ ]*' logs/balanceador/balanceo_detallado.log | sort | uniq -c
```
```powershell
Select-String -Path logs\balanceador\balanceo_detallado.log -Pattern 'backend=(\S+)' |
  ForEach-Object { $_.Matches[0].Groups[1].Value } | Group-Object | Select-Object Name, Count
```

En Linux, Apache escribe esos archivos como root: para borrarlos usa `sudo rm logs/balanceador/*.log`.

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

Comprueba contenedores (`running`/`healthy`), `httpd -t`, módulos de Apache, que el pool coincida con `BACKEND_COUNT`, `GET /health`, `GET /`, `GET /work`, que **todos** los backends reciban tráfico y que el endpoint de estado (`/balancer-manager`, `/server-status?auto`) responda 200 desde el equipo local. Termina con código 0 si todo pasa y guarda el informe en `evidencias\logs\`.

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
- **Pruebas nuevas (16/11/2026)**: concurrencia real (~500 usuarios simultáneos, `make concurrencia`) y backends heterogéneos (`pruebas/compose.heterogeneo.yml`). Resultados en `pruebas/resultados/make/`, análisis en `metricas/ANALISIS.md` (sección "Pruebas nuevas") y gráfica en `metricas/graficas/heterogeneo_algoritmos.png`. Con backends heterogéneos, `bybusyness` envía el 12 % de las peticiones al backend lento (frente al 33 % de `byrequests`) y baja la latencia media un 37 %.
- Los resultados publicados de las 24 corridas se midieron con el backend solo en Python y con pausas que no se aplicaron (`think: 0.5`); ver "Limitaciones" en `metricas/ANALISIS.md`.

Los resultados reportados deben salir de ejecuciones reales (`pruebas/resultados/`); no se inventan datos.

## Estructura del repositorio

```text
proyecto_final_telematicos/
├── docker-compose.yml        Integración (Integrante 3)
├── Makefile                  Atajos: up, down, scale, verificar, carga, caida, estado
├── .env.example              Variables de ejemplo
├── logs/balanceador/         Log del balanceador (volumen; no se versiona)
├── interfaz/                 Interfaz gráfica con nginx, perfil "interfaz" (Integrante 2)
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
| 1 | _Sebastian Bustamante López_ | Balanceador Apache |
| 2 | _Jose Alejandro Ramírez_ | Backends y Docker |
| 3 | _Byron Zapata_ | Docker Compose e integración |
| 4 | _Diego Alejandro Hernández_ | Pruebas Artillery |
| 5 | _Kevin Franco_ | Métricas y análisis |
| 6 | _Santiago López_ | Monitoreo, README, evidencias y entrega |

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
| `/balancer-manager` da 403 desde el host | La IP con la que llega la petición no está en `Require ip` (`balanceador/balancer.conf`). Mira la IP de origen con `docker compose logs balanceador` |
| `make` no existe en Windows | Usar los scripts `.ps1`, o instalar make (`winget install ezwinports.make`) y usar Git Bash |

## Requisitos del enunciado

| Requisito del enunciado | Cómo se cumple | Archivo |
|---|---|---|
| `docker-compose.yml` con balanceador, mínimo 3 backends y Artillery en una sola red | Servicios `balanceador`, `backend1..3` (más 4-7 o `backend × N`) y `artillery`, todos en `red-proyecto` | `docker-compose.yml` |
| Cada servicio con su propio Dockerfile e imagen base documentada | `httpd:2.4.69`, `httpd:2.4.69` + Python 3, `artilleryio/artillery:2.0.34`; versión exacta y motivo en comentarios | `balanceador/Dockerfile`, `backend/Dockerfile`, `pruebas/Dockerfile` |
| Variables configurables (número de backends, puerto del balanceador) en `.env` | `BACKEND_COUNT`, `BALANCER_PORT`, `BALANCER_METHOD`, `WORK_*` | `.env.example` |
| Health checks para cada servicio en `docker-compose.yml` | Balanceador: `bash` + `/dev/tcp` contra `/server-status?auto`. Backends: `/health` a través de su Apache. Interfaz: `wget` a `/panel-config.json`. Artillery: `artillery version`. `depends_on: service_healthy` | `docker-compose.yml` |
| Makefile o script para escalar con `docker compose up --scale backend=N` | `make scale N=…`: `--scale backend=N` y recreación del balanceador con un miembro por réplica | `Makefile`, `balanceador/entrypoint.sh`, `backend/entrypoint.sh` |
| Volúmenes para logs del balanceador y resultados de Artillery | `./logs/balanceador` → `/usr/local/apache2/logs`; `./pruebas/resultados` → `/results` | `docker-compose.yml` |
| README con despliegue paso a paso y arquitectura | Secciones "Arquitectura" y "Despliegue paso a paso" | `README.md` |
| Estadísticas del balanceador (peticiones, fallos, latencia) desde el endpoint de estado | `/server-status?auto` (peticiones, `DurationPerReq`, tráfico) y `/balancer-manager` (por miembro: atendidas, estado `Err`, ocupación); capturas antes y después | `balanceador/balancer.conf`, `scripts/capturar_estado.ps1`, `make estado` |

El servicio `artillery` es de **ejecución puntual**: arranca, lanza la prueba y termina. Por eso no aparece en `docker compose ps` cuando no hay una prueba en marcha, y su healthcheck (`artillery version`) solo tiene efecto mientras corre.

## Evidencias y validación

Capturas, logs y la lista de validación desde cero están en `evidencias/README.md`.
Documentación del balanceador: `balanceador/CONTRATO_INTEGRACION.md` y `balanceador/GUIA_PASO_A_PASO.md`.
