# Integración Docker

El `docker-compose.yml` de la raíz conecta el balanceador Apache con los backends definitivos de `backend/`. Los servicios usan la red privada `red-proyecto`; solo se publica el balanceador en `127.0.0.1:8080` por defecto. Los backends conservan el puerto interno 80 y su healthcheck proviene de su Dockerfile.

## Inicio en Windows

Desde la raíz del repositorio, con Docker Desktop iniciado:

```powershell
Copy-Item .env.example .env
.\scripts\compose.ps1 -Action Up
.\scripts\compose.ps1 -Action Status
Invoke-RestMethod http://localhost:8080/
```

Para ejecutar el smoke test de Artillery dentro de la red Docker:

```powershell
.\scripts\compose.ps1 -Action Artillery
```

El reporte JSON queda en `pruebas/resultados/artillery-report.json`. El escenario es intencionalmente ligero y solo comprueba el recorrido por `/work`; los perfiles de carga y las ejecuciones de 50, 100, 500 y 1000 usuarios corresponden al trabajo de pruebas.

## Escenarios de 3, 5 y 7 backends

```powershell
# 3 backends, valores por defecto
.\scripts\compose.ps1 -Action Restart -BackendCount 3 -BalancerMethod byrequests

# 5 backends
.\scripts\compose.ps1 -Action Restart -BackendCount 5 -BalancerMethod byrequests

# 7 backends y algoritmo por actividad
.\scripts\compose.ps1 -Action Restart -BackendCount 7 -BalancerMethod bybusyness
```

`Restart` elimina únicamente los contenedores y la red de este proyecto y vuelve a construir el escenario solicitado. Úsalo al cambiar el número de backends o el algoritmo: Apache genera la lista de miembros al iniciar. No hay volúmenes de aplicación que se eliminen.

## Detener y revisar

```powershell
.\scripts\compose.ps1 -Action Down
.\scripts\compose.ps1 -Action Status
```

Para comprobar la configuración sin iniciar contenedores:

```powershell
docker compose config --quiet
```

Variables configurables en `.env`: `BALANCER_PORT`, `BACKEND_COUNT`, `BALANCER_METHOD`, `WORK_DELAY_MS`, `WORK_CPU_MS`, `WORK_MAX_MS` y `ARTILLERY_IMAGE`. `BACKEND_COUNT` admite 3, 5 o 7; `BALANCER_METHOD`, `byrequests` o `bybusyness`.
