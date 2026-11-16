# Ampliación de la Parte 1: Apache avanzado

**Proyecto:** `bastianbl/proyecto_final_telematicos` · **Base:** rama `main` de 16/11/2026.

## Objetivo

Agregar complejidad a **la responsabilidad del integrante 1** sin modificar `backend/`, `interfaz/`, el `docker-compose.yml` principal ni los scripts de otros integrantes.

**Novedades**

1. **Balanceo ponderado:** `BACKEND_WEIGHTS=5,3,2` asigna pesos distintos a cada servidor. `byrequests` tiende a repartir 50 %, 30 % y 20 % de las solicitudes; no constituye una garantía de latencia.
2. **Tercer algoritmo:** `BALANCER_METHOD=bytraffic`, que usa bytes de entrada y salida. No confundirlo con `bybusyness` o `least connections`.
3. **Reservas automáticas:** `BACKEND_SPARES=1` convierte el **último** backend del pool en *hot spare* (`status=+R`). En un escenario de tres backends, backend3 sustituye a un activo que quede indisponible. No es lo mismo que un *hot standby* (`status=+H`), que se usa únicamente cuando no hay otros workers ni spares disponibles.
4. **Auditoría por petición:** Apache escribe la ruta, código HTTP, tiempo en microsegundos y servidor seleccionado en `logs/balanceo_detallado.log` dentro del contenedor.
5. **Pruebas repetibles:** `probar_avanzado.ps1` cuenta peticiones y porcentajes sin instalar herramientas adicionales.

Los valores por defecto son **compatibles con el sistema anterior**: sin variables nuevas, todos los pesos son 1, no hay servidores de reserva y el algoritmo sigue siendo `byrequests`.

## Archivos del paquete

- `balanceador/Dockerfile` (modificado): habilita `lbmethod_bytraffic_module` además de los módulos existentes.
- `balanceador/entrypoint.sh` (modificado): valida valores y genera pesos, reservas y algoritmo.
- `balanceador/balancer.conf` (modificado): auditoría de cada petición.
- `balanceador/compose.test.yml` (modificado): pasa las dos nuevas variables al laboratorio aislado.
- `balanceador/compose.advanced.yml` (nuevo): *override* que permite probar las novedades con `docker-compose.yml` real sin editarlo.
- `balanceador/probar_avanzado.ps1` (nuevo): conteo reproducible.
- `balanceador/AMPLIACION_BALANCEADOR.md` (nuevo): esta documentación.

## Paso 0 — Crear una rama sin modificar `main`

**En PowerShell de VS Code, raíz del repositorio:**

```powershell
git status --short
```

Si aparece alguna modificación, guárdala o resuélvela antes de continuar; no descartes trabajo ajeno.

```powershell
git switch main
git pull --ff-only origin main
git switch -c feature/parte1-balanceador-avanzado
```

Si esa rama ya existe localmente, usa `git switch feature/parte1-balanceador-avanzado` en vez de volver a crearla.

## Paso 1 — Colocar los archivos

Desde PowerShell en **la raíz** del repositorio, si el ZIP está en Descargas:

```powershell
Expand-Archive -LiteralPath "$HOME\Downloads\ampliacion_balanceador_avanzado.zip" -DestinationPath (Get-Location).Path -Force
Get-ChildItem .\balanceador\
git status --short
```

**Importante:** este paquete fue preparado contra el `main` revisado el 16 de noviembre de 2026. Si otro compañero modificó `balanceador/` después de esa fecha, compara los cambios antes de sobrescribir.

## Paso 2 — Validar el laboratorio independiente (3 backends)

Primero detén otro laboratorio que utilice `127.0.0.1:8080`, si lo tienes abierto.

```powershell
$env:BACKEND_COUNT="3"
$env:BALANCER_METHOD="byrequests"
$env:BACKEND_WEIGHTS="5,3,2"
$env:BACKEND_SPARES="0"

docker compose -p balanceador-lab -f balanceador/compose.test.yml config --quiet
docker compose -p balanceador-lab -f balanceador/compose.test.yml up -d --build

docker compose -p balanceador-lab -f balanceador/compose.test.yml exec -T balanceador httpd -t
docker compose -p balanceador-lab -f balanceador/compose.test.yml exec -T balanceador httpd -M | Select-String "bytraffic|byrequests|bybusyness|proxy_hcheck"
docker compose -p balanceador-lab -f balanceador/compose.test.yml exec -T balanceador cat /usr/local/apache2/conf/extra/balancer-members.conf
```

**Esperado:** `Syntax OK`, tres `BalancerMember`, `loadfactor=5`, `loadfactor=3`, `loadfactor=2`, `ProxySet lbmethod=byrequests` y los módulos anteriores cargados.

## Paso 3 — Validar los pesos (evidencia para profesor)

```powershell
.\balanceador\probar_avanzado.ps1 -Solicitudes 100
```

**Esperado aproximado:** backend1 50 peticiones, backend2 30, backend3 20. El resultado real puede variar por el estado del balanceador y no representa una mejora automáticamente en latencia.

Guarda captura de los pesos generados y de los porcentajes. La nueva auditoría se consulta así:

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml exec -T balanceador tail -n 12 /usr/local/apache2/logs/balanceo_detallado.log
```

En la auditoría deben aparecer códigos HTTP, tiempos y la URL del worker elegido. Son logs **internos al contenedor** y se pierden si se recrea; exporta evidencia antes de detenerlo.

## Paso 4 — Activar el tercer algoritmo

```powershell
$env:BALANCER_METHOD="bytraffic"
$env:BACKEND_WEIGHTS="1,2,1"
$env:BACKEND_SPARES="0"

docker compose -p balanceador-lab -f balanceador/compose.test.yml up -d --force-recreate --no-deps balanceador
docker compose -p balanceador-lab -f balanceador/compose.test.yml exec -T balanceador httpd -t
docker compose -p balanceador-lab -f balanceador/compose.test.yml exec -T balanceador cat /usr/local/apache2/conf/extra/balancer-members.conf
.\balanceador\probar_avanzado.ps1 -Solicitudes 40
```

**Esperado:** `ProxySet lbmethod=bytraffic`, solicitudes atendidas y sin errores. **No se puede deducir una ventaja de rendimiento** con esas 40 solicitudes: para comparar bytes y latencias hay que diseñar pruebas concurrentes con distintas respuestas, en coordinación con los integrantes 2, 4 y 5.

## Paso 5 — Probar la reserva automática

```powershell
$env:BALANCER_METHOD="byrequests"
$env:BACKEND_WEIGHTS="1,1,1"
$env:BACKEND_SPARES="1"

docker compose -p balanceador-lab -f balanceador/compose.test.yml up -d --force-recreate --no-deps balanceador
Start-Sleep -Seconds 6
.\balanceador\probar_avanzado.ps1 -Solicitudes 30
```

**Esperado:** backend1 y backend2 participan; backend3 no debería recibir tráfico porque queda como reserva (`status=+R`).

Ahora simula el fallo de un activo:

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml stop backend1
Start-Sleep -Seconds 8
.\balanceador\probar_avanzado.ps1 -Solicitudes 30
```

**Esperado:** Apache mantiene el servicio usando backend2 y la reserva backend3 tras detectar el fallo. Puede existir algún error durante la ventana de detección.

Recupera el servidor:

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml start backend1
Start-Sleep -Seconds 8
.\balanceador\probar_avanzado.ps1 -Solicitudes 30
```

Guarda capturas del antes, fallo y recuperación. Si no se produce el comportamiento esperado, comparte la configuración y los logs para revisarlos antes de continuar.

## Paso 6 — Probar contra los backends oficiales (sin alterar Compose principal)

Para evitar conflicto con el laboratorio, apágalo primero:

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml --profile cinco --profile siete down --remove-orphans
```

Desde la raíz del repositorio, activa los valores para el entorno integrado. Si el puerto 8080 ya está ocupado, detén primero el servicio que lo utiliza.

```powershell
$env:BACKEND_COUNT="3"
$env:BALANCER_METHOD="byrequests"
$env:BACKEND_WEIGHTS="5,3,2"
$env:BACKEND_SPARES="0"

docker compose -p telematicos-avanzado -f docker-compose.yml -f balanceador/compose.advanced.yml config --quiet
docker compose -p telematicos-avanzado -f docker-compose.yml -f balanceador/compose.advanced.yml up -d --build --wait
.\balanceador\probar_avanzado.ps1 -Solicitudes 100
```

Este *override* solo pasa `BACKEND_WEIGHTS` y `BACKEND_SPARES`; el Compose principal sigue gestionando red, backend, healthchecks y algoritmo. Para activar `bytraffic` utiliza la variable `$env:BALANCER_METHOD="bytraffic"` y recrea el balanceador con ambos archivos Compose, sin utilizar `scripts/compose.ps1` (que en `main` todavía solo admite dos métodos).

Comprueba también `http://127.0.0.1:8080/health` y `http://127.0.0.1:8080/work`.

Para terminar el laboratorio integrado:

```powershell
docker compose -p telematicos-avanzado -f docker-compose.yml -f balanceador/compose.advanced.yml --profile cinco --profile siete down --remove-orphans
```

## Paso 7 — Comprobar Git y crear Pull Request

```powershell
git status
git add balanceador/
git diff --cached --check
git diff --cached --stat
git commit -m "feat: ampliar balanceador con pesos, bytraffic y servidores de reserva"
git push -u origin feature/parte1-balanceador-avanzado
```

Crea un PR de `feature/parte1-balanceador-avanzado` hacia `main`. **No lo fusiones hasta validar Docker**, y explica que `BALANCER_METHOD=bytraffic` requiere actualizar la validación del script general `scripts/compose.ps1` con el integrante 3 para uso por ese script.

## Variables nuevas y compatibilidad

| Variable | Ejemplo | Valor por defecto | Descripción |
|---|---|---|---|
| `BACKEND_WEIGHTS` | `5,3,2` | vacío = todos 1 | Debe tener exactamente `BACKEND_COUNT` enteros de 1 a 100. |
| `BACKEND_SPARES` | `1` | `0` | Número de últimos backends marcados como reserva. Debe ser menor que `BACKEND_COUNT`. |
| `BALANCER_METHOD` | `bytraffic` | `byrequests` | También acepta los dos métodos anteriores. |

En escenarios de **5 o 7 backends** debes pasar 5 o 7 pesos, respectivamente; el mismo mecanismo se aplica a cualquier cantidad admitida.

**Importante:** una reserva `status=+R` sustituye un worker activo indisponible, mientras que `status=+H` solo se usaría cuando todos los demás workers viables se agotan. Se mantienen las comprobaciones `/health` existentes.

## Fuentes oficiales

- Apache proxy y miembros: https://httpd.apache.org/docs/2.4/mod/mod_proxy.html
- Algoritmo `byrequests`: https://httpd.apache.org/docs/2.4/mod/mod_lbmethod_byrequests.html
- Algoritmo `bytraffic`: https://httpd.apache.org/docs/2.4/mod/mod_lbmethod_bytraffic.html
- Estados `R` y `H`: https://httpd.apache.org/docs/2.4/howto/reverse_proxy.html
- Monitoreo activo: https://httpd.apache.org/docs/2.4/mod/mod_proxy_hcheck.html

**Validación realizada fuera de Docker:** se comprobó `sh -n`, se ejecutaron pruebas de entradas válidas/inválidas del generador y se validó sintaxis `Syntax OK` con Apache 2.4.68 (Debian). También se levantaron tres servicios HTTP temporales y se observaron los siguientes datos de prueba: 100 solicitudes con pesos `5,3,2` → `50/30/20`; con una reserva y tres servidores → `15/15/0`; tras detener backend1 y esperar a la comprobación de salud → `0/15/15`. La auditoría de Apache registró la URL del worker seleccionado. **Esta validación no reemplaza una construcción y ejecución con la imagen `httpd:2.4.69` en Docker Desktop**, que sigue pendiente y que realizaremos sobre la rama nueva.
