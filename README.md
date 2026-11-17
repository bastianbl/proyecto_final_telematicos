# Balanceador de carga web con Apache `mod_proxy_balancer`

**Proyecto 6 — Servicios Telemáticos**

Este proyecto implementa un balanceador de carga con **Apache HTTP Server 2.4**, que distribuye solicitudes entre backends desplegados en **Docker**. El sistema incorpora una aplicación web de monitoreo con **nginx**, comprobaciones de salud mediante `mod_proxy_hcheck` y pruebas de rendimiento con **Artillery**.

**Características principales:**

- Escenarios integrados de **3, 5 y 7 backends**, configurables mediante `.env` o los scripts de operación.
- Tres métodos de balanceo: **`byrequests`** (reparto por solicitudes), **`bybusyness`** (menor cantidad de solicitudes activas) y **`bytraffic`** (distribución según tráfico transferido). `bybusyness` no es exactamente equivalente a *least connections*.
- Monitoreo activo de salud con `mod_proxy_hcheck`: Apache consulta `GET /health` cada 2 segundos, retira temporalmente los miembros no saludables y los reincorpora cuando se recuperan.
- Interfaz web para visualizar backends, distribución de solicitudes, métricas de Apache y resultados de pruebas.
- Pruebas con Artillery para cargas de 50, 100, 500 y 1000 usuarios virtuales configurados como llegadas; además, escenarios de concurrencia y de caída de un backend.
- **Separación entre monitoreo y administración**: `/server-status` está disponible para las consultas locales; `/balancer-manager` está restringido por seguridad.

> **Alcance de seguridad:** el puerto del balanceador se publica en `127.0.0.1` del host. La configuración es apropiada para el laboratorio local del proyecto; no implica que la solución esté endurecida para exponerse directamente a Internet.

## Recorrido completo: un solo sistema

El proyecto se ejecuta mediante un `docker-compose.yml` principal, con el balanceador disponible normalmente en `http://localhost:8080` y la interfaz en `http://localhost:8090`. Cada integrante aporta una parte de este recorrido, que también sirve como guía para la sustentación.

| # | Paso | Linux / macOS / Git Bash | Windows (PowerShell) | Evidencia esperada | Parte de |
|---|---|---|---|---|---|
| 1 | Levantar el sistema | `make up` | `.\scripts\compose.ps1 -Action Interfaz -BackendCount 3 -BalancerMethod byrequests` | Balanceador, backends e interfaz saludables | 3: integración |
| 2 | Verificar | `make verificar` | `.\scripts\verificar.ps1 -BackendCount 3` | Salud, configuración de Apache, reparto y HTTP 403/200 | 6: verificación |
| 3 | Visualizar el balanceo | Abrir `http://localhost:8090` y pulsar **Enviar** | Igual | Reparto de solicitudes y tarjetas por backend | 1 y 2 |
| 4 | Demostrar caída y recuperación | **Modo continuo** y comandos `docker compose stop backend2` / `docker compose start backend2` | Igual | Detección de la caída, redistribución y recuperación | 1 y 2 |
| 5 | Capturar estado previo | `make estado ETIQUETA=antes` | `.\scripts\capturar_estado.ps1 -Etiqueta antes` | Estadísticas de `/server-status` y comprobación de HTTP 403 en `/balancer-manager` | 1 y 6 |
| 6 | Ejecutar Artillery | `make carga CARGA=carga100` | `.\scripts\correr_pruebas.ps1 -BackendCount 3 -BalancerMethod byrequests -Cargas 100 -SinReiniciar` | Solicitudes y métricas durante la carga | 4: pruebas |
| 7 | Capturar estado posterior | `make estado ETIQUETA=despues` | `.\scripts\capturar_estado.ps1 -Etiqueta despues` | Datos para comparar antes y después | 1 y 6 |
| 8 | Analizar resultados | Ver la sección **Resultados de las pruebas** | `python scripts\resumen.py` y `python scripts\generar_metricas.py` | Tabla, gráficas y análisis de métricas | 4 y 5 |
| 9 | Guardar evidencias y apagar | `make down` | `.\scripts\compose.ps1 -Action Down` | Archivos en `evidencias/` y `logs/balanceador/` | 6 |

Para la sustentación en Linux, macOS o Git Bash, `make demo` levanta el escenario definido en `.env`, lo verifica y muestra las URLs relevantes. En Windows se puede utilizar `compose.ps1` y `verificar.ps1`.

Cada carpeta conserva su documentación técnica (`balanceador/`, `backend/`, `pruebas/`, `metricas/`, `interfaz/`, `evidencias/`). Los archivos `balanceador/compose.test.yml` y `backend/compose.backend-test.yml` corresponden a laboratorios de componentes, no al despliegue integrado recomendado.

## Arquitectura

```text
                              HOST
                 http://127.0.0.1:8080
                            │
                            ▼
                   ┌─────────────────┐
                   │ Balanceador     │
                   │ Apache :80      │
                   │ mod_proxy_*     │
                   └────────┬────────┘
                            │ red-proyecto (Docker)
               ┌────────────┼────────────┐
               ▼            ▼            ▼
           backend1      backend2      backend3 ... backend7
           Apache :80    Apache :80    Apache :80
               │            │            │
               └────────────┴────────────┘
                         apps Python

   navegador ──► nginx :8090 ──► monitoreo del balanceador
                                  y consultas a los backends
   Artillery (perfil puntual) ──► balanceador ──► resultados
   balanceador ──► logs/balanceador/balanceo_detallado.log
```

- Los backends `backend1` a `backend7` escuchan en el puerto 80 de sus respectivos contenedores. Cada uno utiliza Apache como proxy hacia su aplicación Python, que escucha internamente en `127.0.0.1:8000`.
- `BACKEND_COUNT=3`, `5` o `7` determina los miembros utilizados por el balanceador; los perfiles de Compose permiten habilitar los servicios adicionales.
- El modo `scale` dispone de un servicio replicable `backend`, separado de los servicios `backend1..backend7` del modo normal.
- Las imágenes base documentadas son `httpd:2.4.69` para Apache y `artilleryio/artillery:2.0.34` para Artillery. Los backends incorporan Python; la interfaz utiliza nginx.
- Los logs y resultados de pruebas se conservan mediante volúmenes, conforme a la configuración de Compose.

### Acceso a los endpoints de Apache

| Endpoint | Acceso esperado desde el host | Propósito |
|---|---|---|
| `/` | HTTP 200 | Solicitud enviada a un backend |
| `/health` | HTTP 200 | Comprobación de salud a través del balanceador |
| `/server-status` | HTTP 200 | Estadísticas de Apache en HTML |
| `/server-status?auto` | HTTP 200 | Estadísticas en texto utilizadas por el monitoreo |
| `/balancer-manager` | **HTTP 403** | Administración restringida al propio contenedor de Apache mediante `Require local` |

La restricción del panel administrativo no impide que la interfaz consulte `/server-status?auto`. La ruta `/balancer-manager` no debe usarse como enlace público de monitoreo.

## Requisitos

**Windows:** Docker Desktop con contenedores Linux, PowerShell y Git. Se requiere Python 3 para los scripts locales de análisis (`scripts/resumen.py` y `scripts/generar_metricas.py`).

**Linux o macOS:** Docker Engine o Docker Desktop, `make`, `bash` y `curl`. En Windows también pueden utilizarse `make` y Git Bash o WSL, cuando estén configurados.

## Despliegue paso a paso

### Windows (PowerShell)

Desde la raíz del repositorio:

```powershell
Copy-Item .env.example .env
.\scripts\compose.ps1 -Action Interfaz -BackendCount 3 -BalancerMethod byrequests
.\scripts\verificar.ps1 -BackendCount 3
```

Abrir:

- Interfaz: `http://localhost:8090`.
- Balanceador: `http://localhost:8080`.
- Estadísticas: `http://localhost:8080/server-status?auto`.

Para una prueba rápida de Artillery:

```powershell
.\scripts\compose.ps1 -Action Artillery
```

Para ver el estado o detener el sistema:

```powershell
.\scripts\compose.ps1 -Action Status
.\scripts\compose.ps1 -Action Down
```

**Nota:** `-Action Up` levanta el balanceador y los backends; `-Action Interfaz` incluye también el panel web. Selecciona el escenario deseado antes de ejecutar la verificación con el mismo número de backends.

### Linux, macOS o Git Bash

```bash
cp .env.example .env
make up
make ps
make verificar
make smoke
make down
```

`make up` configura el escenario según `.env`, construye los servicios y espera los *health checks*. `make carga CARGA=carga100` ejecuta una carga de `pruebas/carga.yml`.

Si se usa Docker Compose directamente, para incluir la interfaz se necesita el perfil correspondiente:

```bash
docker compose --profile interfaz up -d --build --wait
docker compose ps
docker compose --profile interfaz down
```

## Inicio rápido desde GitHub

```powershell
git clone https://github.com/bastianbl/proyecto_final_telematicos.git
cd proyecto_final_telematicos
Copy-Item .env.example .env
.\scripts\compose.ps1 -Action Interfaz -BackendCount 3 -BalancerMethod byrequests
.\scripts\verificar.ps1 -BackendCount 3
Invoke-RestMethod http://localhost:8080/
```

> **Importante:** el repositorio `main` puede no incorporar todavía las correcciones documentadas aquí mientras el PR #8 y la rama de ajustes permanezcan sin fusionar. Para reproducir exactamente la validación reciente, primero deben integrarse esos cambios.

## Configuración (`.env`)

| Variable | Valor habitual | Descripción |
|---|---|---|
| `BALANCER_PORT` | `8080` | Puerto del host para Apache |
| `BACKEND_COUNT` | `3` | Cantidad de backends en modo fijo: `3`, `5` o `7` |
| `BALANCER_METHOD` | `byrequests` | `byrequests`, `bybusyness` o `bytraffic` |
| `WORK_DELAY_MS` | `200` | Espera simulada de E/S de `GET /work`, en milisegundos |
| `WORK_CPU_MS` | `0` | Carga simulada de CPU de `GET /work`, en milisegundos |
| `WORK_MAX_MS` | `10000` | Valor máximo permitido para la carga indicada por URL |
| `BACKEND_MODE` | `fijo` | `fijo` para `backend1..N` o `scale` para réplicas; `make scale` configura este modo |

Artillery usa su propia imagen definida en `pruebas/Dockerfile`; la variable antigua `ARTILLERY_IMAGE`, si aparece en un `.env` anterior, no controla su imagen.

## Cambiar de escenario o algoritmo

Apache genera la lista de miembros al iniciar. Por ello, para cambiar de escenario o método se recrea o reinicia el balanceador mediante los scripts del proyecto.

```powershell
.\scripts\compose.ps1 -Action Restart -BackendCount 3 -BalancerMethod byrequests
.\scripts\compose.ps1 -Action Restart -BackendCount 5 -BalancerMethod bybusyness
.\scripts\compose.ps1 -Action Interfaz -BackendCount 7 -BalancerMethod bytraffic
```

También están disponibles `-Action Status`, `-Action Logs`, `-Action Artillery` y `-Action Down`. Con el `Makefile`, se establecen `BACKEND_COUNT` y `BALANCER_METHOD` en `.env` y se ejecuta `make up`.

**Interpretación de los algoritmos:**

- `byrequests`: busca repartir las solicitudes según los pesos asignados a cada miembro.
- `bybusyness`: favorece los miembros con menos solicitudes activas; resulta útil para comparar cargas heterogéneas o solicitudes de distinta duración.
- `bytraffic`: utiliza la cantidad de tráfico transferido para decidir el reparto. No implica que todas las solicitudes tengan idéntico tamaño ni garantiza un número igual de peticiones por backend.

El soporte de `bytraffic` en `scripts/compose.ps1` y `scripts/correr_pruebas.ps1` corresponde a los ajustes finales. Las gráficas históricas `byrequests` frente a `bybusyness` no deben presentarse como una comparación de los tres algoritmos si no se han medido las corridas de `bytraffic`.

## Escalar con `docker compose up --scale backend=N`

Además de los servicios fijos, el archivo Compose define `backend` con el perfil `scale`. El Makefile incluye:

```bash
make scale N=4       # genera 4 réplicas (intervalo documentado: 1 a 20)
make verificar N=4   # verifica el balanceador y su reparto
make up              # regresa al modo normal
```

`make scale N=4` inicia las réplicas con `--scale backend=4` y recrea el balanceador con `BACKEND_MODE=scale BACKEND_COUNT=4`. Apache necesita un `BalancerMember` por réplica para gestionar individualmente el reparto y el monitoreo de salud; no es suficiente con utilizar una única entrada que apunte al nombre DNS compartido.

**Limitaciones de este modo:**

- La recreación del balanceador ocasiona una interrupción breve del servicio; la duración depende del entorno.
- `scripts/verificar.ps1` y `scripts/prueba_caida.ps1` están orientados al modo fijo. Las tarjetas directas de la interfaz consultan nombres `backendN`, por lo que no representan necesariamente todas las réplicas del modo `scale`.
- La funcionalidad `--scale` está implementada en el proyecto, pero no forma parte de las verificaciones locales documentadas el 17 de noviembre de 2026. Debe probarse por separado antes de presentarla como validada.

## Monitoreo y captura de estado

`/server-status?auto` proporciona métricas de Apache como `Total Accesses`, `Total kBytes`, `ReqPerSec`, `DurationPerReq`, `BusyWorkers`, `IdleWorkers` y tiempo activo. La interfaz las consulta periódicamente.

`/balancer-manager` permite modificar la configuración de miembros y, por ese motivo, **se mantiene restringido**. Desde Windows debe responder HTTP 403; no se descarga como evidencia. Para consultar su contenido desde el interior del contenedor se necesitarían permisos de acceso locales al propio Apache, fuera del recorrido estándar de la sustentación.

**Capturas antes y después de una prueba:**

```bash
make estado ETIQUETA=antes
make carga CARGA=carga100
make estado ETIQUETA=despues
```

```powershell
.\scripts\capturar_estado.ps1 -Etiqueta antes
.\scripts\correr_pruebas.ps1 -BackendCount 3 -BalancerMethod byrequests -Cargas 100 -SinReiniciar
.\scripts\capturar_estado.ps1 -Etiqueta despues
```

Las capturas se guardan en `evidencias/logs/estado_<etiqueta>_<fecha>/` e incluyen `server-status.txt`, `server-status.html` y el resultado de la comprobación de acceso restringido al administrador. Los errores de backend se investigan mediante las métricas disponibles, las verificaciones y `logs/balanceador/balanceo_detallado.log`.

## Logs y resultados

| Información | Ubicación en el host |
|---|---|
| Backend seleccionado, código de respuesta y duración | `logs/balanceador/balanceo_detallado.log` |
| Logs de contenedores | `docker compose logs <servicio>` |
| Resultados publicados por Artillery | `pruebas/resultados/*.json`, archivos `.txt` y resúmenes generados |
| Corridas de `make carga` o `make concurrencia` | `pruebas/resultados/make/` |
| Verificaciones, pruebas de caída y capturas de estado | `evidencias/logs/` |

El volumen de logs puede conservar archivos incluso después de ejecutar `docker compose down`. Los logs propios de contenedores eliminados pueden no estar disponibles posteriormente.

Para contar las solicitudes por backend a partir del log detallado:

```bash
grep -o 'backend=[^ ]*' logs/balanceador/balanceo_detallado.log | sort | uniq -c
```

```powershell
Select-String -Path logs\balanceador\balanceo_detallado.log -Pattern 'backend=(\S+)' |
    ForEach-Object { $_.Matches[0].Groups[1].Value } |
    Group-Object | Select-Object Name, Count
```

En Linux puede ser necesario contar con permisos administrativos para eliminar logs creados por Apache.

## Endpoints de los backends

| Ruta | Comportamiento |
|---|---|
| `GET /` | Responde con el identificador `backendN` |
| `GET /health` | Devuelve HTTP 200 e identifica al backend saludable |
| `GET /work` | Simula carga y responde con el backend; admite parámetros como `?delay_ms=500&cpu_ms=50` |

## Verificación del sistema

Con el escenario ya levantado:

```powershell
.\scripts\verificar.ps1 -BackendCount 3
.\scripts\verificar.ps1 -BackendCount 7
```

**Ejecuta solo el comando correspondiente al número de backends activos.** El script comprueba:

1. Docker y validez de la configuración de Compose.
2. Estado `running`/`healthy` del balanceador y los backends previstos.
3. Sintaxis de Apache (`httpd -t`), módulos cargados, miembros del balanceador y comprobaciones `hcheck`.
4. Respuesta de `/health`, `/` y `/work` a través del balanceador.
5. Recepción de tráfico por todos los backends y ausencia de respuestas inesperadas.
6. **HTTP 403** en `/balancer-manager` y **HTTP 200** en `/server-status?auto` desde el host.

Si todas las comprobaciones pasan, el script informa `RESULTADO: todas las verificaciones pasaron`, devuelve un código de salida exitoso y guarda el informe en `evidencias/logs/`.

## Prueba de caída y recuperación

```powershell
.\scripts\prueba_caida.ps1
.\scripts\prueba_caida.ps1 -BackendCount 7 -Backend 4 -Duracion 60 -SegundoCaida 15 -SegundoRecuperacion 35
```

El script envía solicitudes mientras se detiene y restablece un backend, sin reiniciar el balanceador Apache. Registra el comportamiento observado y genera evidencias. La detección de fallos no elimina por completo la posibilidad de errores en solicitudes que lleguen antes de que el monitoreo marque al backend como no saludable.

Para una prueba de caída durante la carga:

```powershell
.\scripts\correr_pruebas.ps1 -BackendCount 3 -BalancerMethod byrequests -Escenario caida
# En otra terminal, durante la prueba:
docker compose stop backend2
docker compose start backend2
```

Es importante anotar la hora exacta de la caída y recuperación para comparar los logs y resultados.

## Pruebas de carga y métricas

```powershell
.\scripts\correr_pruebas.ps1 -BackendCount 3 -BalancerMethod byrequests
python scripts\resumen.py
python scripts\generar_metricas.py
```

El parámetro `-Cargas` permite elegir subconjuntos de 50, 100, 500 o 1000 usuarios virtuales según la configuración de las pruebas. `-SinReiniciar` resulta útil cuando ya se ha levantado el escenario y se quiere observar la carga en la interfaz sin recrear los contenedores.

Para ejecutar una carga con el tercer método:

```powershell
.\scripts\correr_pruebas.ps1 -BackendCount 7 -BalancerMethod bytraffic -Cargas 100 -SinReiniciar
```

Este último es un **comando disponible**, no una afirmación de que esa corrida específica ya haya sido ejecutada.

Material complementario:

- `pruebas/README_PRUEBAS.md`: diseño y alcance de los escenarios de Artillery.
- `metricas/README.md`: definiciones de latencia, p95/p99, throughput y errores.
- `metricas/ANALISIS.md`: comparación de algoritmos, resultados y limitaciones.
- `pruebas/compose.heterogeneo.yml`: configuración de backends heterogéneos.

Los resultados registrados el 16 de noviembre de 2026 para backends heterogéneos muestran, según el análisis existente, un 12 % de solicitudes dirigidas al backend lento con `bybusyness` frente a un 33 % con `byrequests`, y una reducción de la latencia media del 37 %. Estos valores corresponden a **ese escenario experimental**, no a una mejora garantizada para cualquier carga.

Los resultados históricos de 24 corridas tienen limitaciones metodológicas documentadas en `metricas/ANALISIS.md`, relacionadas con la ejecución previa del backend y las pausas de Artillery. **Nunca se deben presentar datos simulados o no ejecutados como mediciones reales.**

### Validación local del 17 de noviembre de 2026

Estas comprobaciones se efectuaron en el escenario integrado con Docker Desktop y PowerShell:

| Comprobación | Resultado observado |
|---|---|
| Siete backends con `bytraffic` | Los siete contenedores `healthy`; Apache confirmó `Método de balanceo activo: bytraffic` |
| Verificación funcional de 70 solicitudes secuenciales | 70 respuestas válidas; 10 peticiones en cada backend |
| Seguridad administrativa | `/balancer-manager` → HTTP 403 |
| Monitoreo | `/server-status?auto` → HTTP 200 |
| Captura de estado | Dos archivos de estadísticas generados y restricción administrativa confirmada |
| Interfaz gráfica con `bytraffic` | 70 solicitudes correctas, 0 fallidas y 240 ms de latencia media en la prueba visual mostrada |
| Artillery con siete backends y `byrequests` | 100 usuarios virtuales completados; 300 respuestas HTTP 200, 0 fallos; p95 de aproximadamente 202,4 ms y p99 de 210,6 ms |

La prueba visual de 70 solicitudes y la corrida de Artillery con `byrequests` son **pruebas distintas**. No deben mezclarse sus métricas. Las evidencias corresponden al entorno local; solo se incorporarán al repositorio cuando se decida guardar los archivos de resultados.

## Estructura del repositorio

```text
proyecto_final_telematicos/
├── docker-compose.yml       Integración Docker y perfiles
├── Makefile                 Comandos de operación y pruebas
├── .env.example             Variables de ejemplo
├── README.md                Documentación principal
├── INTEGRACION.md           Guía adicional de integración
├── balanceador/             Apache, configuración y contrato (integrante 1)
├── backend/                 Backends y endpoints de salud (integrante 2)
├── interfaz/                Panel web nginx (integrante 2)
├── pruebas/                 Artillery, escenarios y resultados (integrante 4)
├── metricas/                Resúmenes, gráficas y análisis (integrante 5)
├── scripts/                 Scripts de ejecución y validación
├── evidencias/              Capturas y reportes (integrante 6)
└── logs/balanceador/        Logs persistentes del balanceador
```

## Responsables

| Integrante | Nombre | Área |
|---|---|---|
| 1 | Sebastian Bustamante López | Balanceador Apache |
| 2 | Jose Alejandro Ramírez | Backends y Docker |
| 3 | Byron Zapata | Docker Compose e integración |
| 4 | Diego Alejandro Hernández | Pruebas Artillery |
| 5 | Kevin Franco | Métricas y análisis |
| 6 | Santiago López | Monitoreo, README, evidencias y entrega |

## Limitaciones conocidas

- Los *health checks* minimizan errores durante una caída, pero no garantizan que todas las solicitudes que coincidan con el fallo finalicen correctamente.
- Las verificaciones secuenciales demuestran funcionamiento, no rendimiento. Para latencia p95/p99, throughput y errores bajo carga se usan las ejecuciones de Artillery.
- `byrequests`, `bybusyness` y `bytraffic` pueden producir distribuciones similares en pruebas cortas y homogéneas. Sus diferencias deben analizarse con cargas apropiadas.
- `/balancer-manager` está restringido al propio contenedor. Su respuesta HTTP 403 desde el host es el **comportamiento esperado**, no un error del sistema.
- Las mediciones históricas conservan las limitaciones documentadas en los archivos de análisis; conviene distinguir las condiciones de cada escenario.
- El funcionamiento del modo `scale` se debe verificar específicamente si se va a demostrar en la sustentación.

## Problemas habituales

| Síntoma | Comprobación recomendada |
|---|---|
| Docker no responde | Abrir Docker Desktop y ejecutar `docker info` |
| Puerto 8080 ocupado | Revisar `BALANCER_PORT` en `.env` |
| Backend saludable sin tráfico | Probar `/health`, revisar miembros configurados y los logs |
| Error `^M` en scripts `.sh` | Verificar finales de línea LF y `.gitattributes` |
| `BACKEND_COUNT` no coincide con los contenedores | Recrear el escenario con `compose.ps1` y ejecutar `verificar.ps1` |
| Apache responde 503 | Comprobar salud, nombres DNS internos y red compartida |
| `/balancer-manager` devuelve 403 desde el host | **Es correcto**: acceso restringido mediante `Require local`; utilizar `/server-status` para el monitoreo |
| `/server-status?auto` no responde 200 | Revisar `balanceador/balancer.conf`, puertos, red Docker y logs de Apache |
| `make` no existe en Windows | Usar los scripts `.ps1` o instalar `make` y utilizar Git Bash/WSL |

## Requisitos del enunciado

| Requisito | Implementación | Archivos relevantes |
|---|---|---|
| Balanceador, al menos tres backends y Artillery en una red | Servicios integrados y red `red-proyecto` | `docker-compose.yml` |
| Imágenes definidas y documentadas | Dockerfiles de Apache, Python y Artillery | `balanceador/Dockerfile`, `backend/Dockerfile`, `pruebas/Dockerfile` |
| Configuración por variables | Número de backends, puerto, método y carga de trabajo | `.env.example` |
| Health checks | Apache `/health`, comprobaciones de balanceador e interfaz | `docker-compose.yml`, `balanceador/balancer.conf` |
| Escalamiento mediante `--scale` | Perfil replicable y recreación del balanceador | `Makefile`, `balanceador/entrypoint.sh`, `backend/entrypoint.sh` |
| Logs y resultados persistentes | Volúmenes de Apache y Artillery | `docker-compose.yml` |
| Documentación de despliegue | Arquitectura, comandos y pruebas | `README.md` |
| Estadísticas de peticiones, tráfico y duración | `/server-status?auto`; registros por backend; acceso administrativo restringido | `balanceador/balancer.conf`, `scripts/capturar_estado.ps1`, `Makefile` |

Artillery es un servicio de **ejecución puntual**: inicia para correr una prueba y termina. Por ello no necesariamente figura como contenedor activo cuando no se está realizando una medición.

## Evidencias y validación

- `evidencias/README.md`: lista de evidencias y comprobaciones para la entrega.
- `balanceador/CONTRATO_INTEGRACION.md`: requisitos de integración del balanceador.
- `balanceador/GUIA_PASO_A_PASO.md`: guía técnica de Apache.
- `pruebas/README_PRUEBAS.md`: metodología de Artillery.
- `metricas/ANALISIS.md`: interpretación de resultados y limitaciones.

**Estado del repositorio:** la actualización de este README debe guardarse junto con los cambios ya verificados de `balancer.conf`, scripts de PowerShell, `Makefile` e interfaz. La integración a la rama `main` requiere el flujo normal de revisión y fusión del equipo.
