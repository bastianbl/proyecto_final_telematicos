# Guía paso a paso — Integrante 1: Balanceador Apache

**Proyecto:** Balanceador de carga web con Apache `mod_proxy_balancer`
**Repositorio:** https://github.com/bastianbl/proyecto_final_telematicos
**Rama del integrante 1:** `feature/parte1-balanceador-apache`
**Entorno de trabajo:** Windows 11, PowerShell, Visual Studio Code y Docker Desktop (contenedores Linux).
**Estado:** pruebas funcionales realizadas el **7 de noviembre de 2026**. Pendiente de integración final con los backends del equipo, pruebas de Artillery y publicación de la rama, si aún no se han realizado.

> **Esta es la guía ACTUALIZADA.** Sustituye a la versión que describía únicamente detección pasiva de fallos. El balanceador ahora incorpora monitoreo activo con `mod_proxy_hcheck` y requiere `GET /health` en los backends.

---

## 0. Alcance y responsables

### Lo que corresponde al integrante 1

- Configurar Apache como proxy inverso y balanceador.
- Habilitar los módulos `mod_proxy`, `mod_proxy_http`, `mod_proxy_balancer`, los dos métodos de balanceo y `mod_proxy_hcheck`.
- Permitir `BACKEND_COUNT=3`, `5` o `7` y `BALANCER_METHOD=byrequests` o `bybusyness`.
- Mantener los archivos bajo `balanceador/`.
- Validar distribución, cambio de algoritmo, escalabilidad, caída y recuperación de un backend.
- Documentar la interfaz necesaria para que se integren los servicios definitivos.

### Lo que NO debes reemplazar

- `backend/` — integrante 2: backends definitivos.
- `docker-compose.yml` de la raíz — integrante 3: integración.
- `pruebas/` — integrante 4: Artillery.
- `metricas/` — integrante 5: métricas y gráficas.
- `README.md` general y evidencias globales — integrante 6.

`balanceador/compose.test.yml` y `balanceador/test-fixtures/` son un **laboratorio autónomo**. Sus backends Nginx temporales no son la aplicación final.

---

## 1. Contrato obligatorio antes de integrar

| Elemento | Valor o requisito | Responsable principal |
|---|---|---|
| Servicio Apache | `balanceador` | 1 y 3 |
| DNS de backends | `backend1` … `backend7` | 2 y 3 |
| Puerto Apache dentro del contenedor | `80/tcp` | 1 |
| Puerto de los backends dentro de Docker | `80/tcp` | 2 |
| Puerto publicado en este laboratorio | `127.0.0.1:8080` → `80` | 1 |
| Red Docker | Apache y todos los backends en la misma red | 3 |
| Número de backends | `BACKEND_COUNT=3`, `5` o `7` | 1 y 3 |
| Método | `BALANCER_METHOD=byrequests` o `bybusyness` | 1 y 3 |
| Identificador por backend | `GET /` permite identificar el backend en las pruebas | 2 |
| Monitoreo activo | `GET /health` debe responder **HTTP 200** cuando esté sano | 2; configurado en Apache por 1 |

**Importante:** no se está escalando un único servicio con `--scale backend=7`. El diseño del laboratorio utiliza servicios con nombres separados (`backend1`, `backend2`, etc.). Si el grupo decide cambiar esta arquitectura, deberá acordarse antes de fusionar las ramas.

Los requisitos técnicos están desarrollados en `balanceador/CONTRATO_INTEGRACION.md`. Ese archivo y esta guía deben coincidir.

---

## 2. Herramientas y ubicación de comandos

**Todos los comandos de esta guía se ejecutan en la terminal PowerShell de VS Code, desde la raíz del repositorio**, salvo que se indique expresamente otra cosa. No debes entrar en la terminal de un contenedor para ejecutar los comandos de Docker Compose.

Comprueba las herramientas:

```powershell
git --version
docker --version
docker compose version
docker info
code --version
```

En Docker Desktop comprueba que el motor esté activo (**Engine running**) y que esté usando contenedores Linux.

### Carpeta del proyecto en este computador

```text
C:\Users\sebas\Documents\proyecto_final_telematicos
```

Para entrar desde PowerShell:

```powershell
cd "$HOME\Documents\proyecto_final_telematicos"
```

### Clonar solo si todavía NO tienes el repositorio

```powershell
cd "$HOME\Documents"
git clone https://github.com/bastianbl/proyecto_final_telematicos.git
cd proyecto_final_telematicos
code .
```

**No vuelvas a clonar si ya lo tienes.** El integrante 1 ya creó y utilizó la rama:

```text
feature/parte1-balanceador-apache
```

Compruébala con:

```powershell
git branch --show-current
git status
```

Si necesitas cambiar a esa rama y ya existe localmente:

```powershell
git switch feature/parte1-balanceador-apache
```

No uses `git switch -c` sobre una rama que ya existe. No debes trabajar directamente en `main`.

---

## 3. Estructura de la carpeta del integrante 1

```text
proyecto_final_telematicos/
└── balanceador/
    ├── .gitattributes
    ├── Dockerfile
    ├── balancer.conf
    ├── entrypoint.sh
    ├── compose.test.yml
    ├── probar.ps1
    ├── CONTRATO_INTEGRACION.md
    ├── GUIA_PASO_A_PASO.md
    └── test-fixtures/
        ├── Dockerfile
        └── default.conf.template
```

Puedes añadir `balanceador/evidencias/` para conservar pruebas relevantes. No guardes contraseñas, claves, archivos `.env` con secretos ni datos privados en Git.

### Función de cada archivo

- **`Dockerfile`**: construye Apache 2.4, habilita módulos para el proxy, algoritmos y monitoreo activo (`proxy_hcheck` y su dependencia `watchdog`).
- **`balancer.conf`**: configura Apache como proxy inverso, define el clúster y restringe los endpoints administrativos con `Require local`.
- **`entrypoint.sh`**: valida las variables, genera `balancer-members.conf` con los backends requeridos y arranca Apache.
- **`compose.test.yml`**: despliega el laboratorio independiente; los perfiles `cinco` y `siete` activan backends extra.
- **`test-fixtures/`**: servidores temporales para probar distribución y `/health`.
- **`CONTRATO_INTEGRACION.md`**: requisitos que deben respetar los integrantes 2 y 3.

El archivo `balancer-members.conf` se crea **dentro del contenedor** en cada arranque. No es necesario guardarlo en Git ni editarlo a mano.

---

## 4. Revisar el monitoreo activo implementado

El `Dockerfile` actualizado incluye los módulos `proxy_hcheck` y `watchdog`. Los miembros generados por `entrypoint.sh` contienen los siguientes parámetros:

```apache
BalancerMember "http://backend1:80" retry=2 connectiontimeout=2 timeout=10 hcmethod=GET hcuri=/health hcinterval=2 hcfails=1 hcpasses=1
```

Se genera una línea equivalente para cada backend incluido en el escenario.

**Significado de la configuración:**

| Parámetro | Función |
|---|---|
| `hcmethod=GET` | Apache realiza una solicitud HTTP GET de salud. |
| `hcuri=/health` | Ruta consultada en el backend. |
| `hcinterval=2` | Intervalo entre comprobaciones, en segundos. |
| `hcfails=1` | Una comprobación fallida basta para marcar el backend no saludable. |
| `hcpasses=1` | Una comprobación correcta basta para volver a habilitarlo. |
| `retry=2` | Tiempo de reintento de un miembro que Apache ha marcado en error; no garantiza repetir automáticamente una misma solicitud fallida. |

**Diferencia importante:** los *healthchecks* de Docker Compose informan sobre la salud del contenedor; `mod_proxy_hcheck` decide qué backends deben participar en el balanceo de Apache. Son mecanismos complementarios.

Apache considera exitosas por defecto respuestas HTTP `2xx` o `3xx` para este tipo de comprobación, pero el contrato del equipo exige específicamente **HTTP 200** en `GET /health` para mayor claridad y consistencia.

Los controles no garantizan que nunca se pierda una solicitud: si un backend falla entre dos comprobaciones o durante el procesamiento, puede aparecer un error transitorio.

---

## 5. Validación de Docker Compose

Desde la raíz del repositorio:

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml config
```

El comando valida el archivo Compose y muestra los servicios configurados. **No inicia contenedores.**

El prefijo `-p balanceador-lab` evita mezclar los nombres de red y contenedores de este laboratorio con los del proyecto principal.

---

## 6. Desplegar el escenario de 3 backends con `byrequests`

```powershell
$env:BACKEND_COUNT="3"
$env:BALANCER_METHOD="byrequests"
docker compose -p balanceador-lab -f balanceador/compose.test.yml up -d --build
```

Comprueba los servicios:

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml ps
```

Deben aparecer tres backends como `Up (healthy)` y un balanceador como `Up`.

Verifica la sintaxis de Apache:

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml exec balanceador httpd -t
```

**Resultado esperado:** `Syntax OK`.

Comprueba los módulos:

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml exec balanceador httpd -M
```

Deben estar disponibles, entre otros: `proxy_module`, `proxy_http_module`, `proxy_balancer_module`, `lbmethod_byrequests_module`, `lbmethod_bybusyness_module`, `proxy_hcheck_module` y su dependencia `watchdog_module`. Si no ves un módulo en el listado, revisa cómo está compilado y los logs antes de asumir que falta.

Comprueba la configuración generada:

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml exec balanceador cat /usr/local/apache2/conf/extra/balancer-members.conf
```

Debe contener tres miembros y `ProxySet lbmethod=byrequests`.

---

## 7. Comprobar la distribución con 3 backends

Solicitud individual:

```powershell
Invoke-RestMethod http://localhost:8080/
```

Distribución de 21 solicitudes:

```powershell
1..21 | ForEach-Object {
    (Invoke-RestMethod 'http://localhost:8080/' -TimeoutSec 10).Trim()
} | Group-Object | Sort-Object Name | Select-Object Name, Count
```

**Resultado obtenido el 7 de noviembre de 2026:** `backend1=7`, `backend2=7`, `backend3=7`. Se verificó asimismo la rotación consecutiva entre los servidores.

Un recuento equilibrado demuestra distribución funcional, **no** una mejora de latencia ni de rendimiento.

---

## 8. Activar y validar `bybusyness`

En el escenario de tres backends:

```powershell
$env:BACKEND_COUNT="3"
$env:BALANCER_METHOD="bybusyness"
docker compose -p balanceador-lab -f balanceador/compose.test.yml up -d --force-recreate --no-deps balanceador
```

Verifica el método activo:

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml exec balanceador cat /usr/local/apache2/conf/extra/balancer-members.conf
```

Debe aparecer `ProxySet lbmethod=bybusyness`.

Prueba:

```powershell
1..21 | ForEach-Object {
    (Invoke-RestMethod 'http://localhost:8080/' -TimeoutSec 10).Trim()
} | Group-Object | Sort-Object Name | Select-Object Name, Count
```

**Resultado obtenido:** tres backends, siete respuestas cada uno, con `Syntax OK`.

`bybusyness` prioriza los backends con menos solicitudes activas; **no es idéntico a least connections**. Como las solicitudes del laboratorio son cortas y secuenciales, ambos métodos pueden arrojar recuentos iguales. La evaluación de latencia, throughput y p95/p99 corresponde a las pruebas posteriores con Artillery.

---

## 9. Cambiar a 5 backends

Primero elimina solo los contenedores del laboratorio anterior:

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml --profile cinco --profile siete down --remove-orphans
```

Configura y levanta cinco:

```powershell
$env:BACKEND_COUNT="5"
$env:BALANCER_METHOD="byrequests"
docker compose -p balanceador-lab -f balanceador/compose.test.yml --profile cinco up -d --build
```

Comprueba el estado:

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml --profile cinco ps
```

Comprueba la lista de miembros:

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml exec balanceador cat /usr/local/apache2/conf/extra/balancer-members.conf
```

Prueba 35 solicitudes:

```powershell
1..35 | ForEach-Object {
    (Invoke-RestMethod 'http://localhost:8080/' -TimeoutSec 10).Trim()
} | Group-Object | Sort-Object Name | Select-Object Name, Count
```

**Resultado obtenido:** cinco backends saludables; `backend1` a `backend5` recibieron **7 peticiones cada uno**.

---

## 10. Cambiar a 7 backends

Detén el entorno anterior:

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml --profile cinco --profile siete down --remove-orphans
```

Configura y levanta siete:

```powershell
$env:BACKEND_COUNT="7"
$env:BALANCER_METHOD="byrequests"
docker compose -p balanceador-lab -f balanceador/compose.test.yml --profile siete up -d --build
```

Verifica los ocho contenedores (7 backends + Apache):

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml --profile siete ps
```

Comprueba Apache:

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml exec balanceador httpd -t
docker compose -p balanceador-lab -f balanceador/compose.test.yml exec balanceador cat /usr/local/apache2/conf/extra/balancer-members.conf
```

Prueba 70 solicitudes:

```powershell
1..70 | ForEach-Object {
    (Invoke-RestMethod 'http://localhost:8080/' -TimeoutSec 10).Trim()
} | Group-Object | Sort-Object Name | Select-Object Name, Count
```

**Resultado obtenido:** los siete backends saludables, `Syntax OK` y **10 solicitudes por servidor**.

---

## 11. Prueba de caída y recuperación: resultado inicial

**Esta sección documenta lo que ocurrió ANTES de habilitar `mod_proxy_hcheck`. No describe el comportamiento actual esperado.**

- Con siete backends se detuvo `backend4`.
- De 60 solicitudes: **59 fueron exitosas y 1 falló** (98,33 % de éxito).
- Apache registró el error `AH00898: DNS lookup failure for: backend4` y respondió HTTP 500 en la solicitud afectada.
- Tras recuperar `backend4`, las 70 solicitudes posteriores fueron exitosas.

Se conservan estos datos por transparencia. En los logs de un periodo más amplio se observaron dos eventos HTTP 500 de ejecuciones distintas; no deben contarse como dos errores de la misma serie de 60 solicitudes.

---

## 12. Corrección aplicada: monitoreo activo con `mod_proxy_hcheck`

La corrección ya probada actualizó **dos archivos**: `balanceador/Dockerfile` y `balanceador/entrypoint.sh`.

Para verificar la versión actual:

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml exec balanceador httpd -M | Select-String 'proxy_hcheck|watchdog'
docker compose -p balanceador-lab -f balanceador/compose.test.yml exec balanceador httpd -t
docker compose -p balanceador-lab -f balanceador/compose.test.yml exec balanceador cat /usr/local/apache2/conf/extra/balancer-members.conf
```

En el archivo generado deben verse los parámetros `hcmethod=GET hcuri=/health hcinterval=2 hcfails=1 hcpasses=1` para cada backend. La prueba del integrante 1 confirmó que `proxy_hcheck_module` estaba cargado y la sintaxis era correcta.

Si en otro computador se acaban de actualizar estos archivos, reconstruye y recrea Apache (el entorno de siete backends debe estar levantado):

```powershell
$env:BACKEND_COUNT="7"
$env:BALANCER_METHOD="byrequests"
docker compose -p balanceador-lab -f balanceador/compose.test.yml --profile siete up -d --build --force-recreate --no-deps balanceador
```

Si falta `/health` en los backends oficiales, se debe implementar **antes de integrarlos**; no desactives `proxy_hcheck` como atajo.

---

## 13. Repetir la caída de `backend4` CON monitoreo activo

La prueba se ejecuta con **siete backends** y el balanceador actualizado.

Detén uno:

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml --profile siete stop backend4
```

Espera a que Apache detecte la caída:

```powershell
Start-Sleep -Seconds 8
```

Registra las 60 respuestas, **incluyendo los errores**:

```powershell
$resultados = 1..60 | ForEach-Object {
    try {
        (Invoke-RestMethod 'http://localhost:8080/' -TimeoutSec 10).Trim()
    }
    catch {
        'ERROR'
    }
}
$resultados | Group-Object | Sort-Object Name | Select-Object Name, Count
```

**Resultado observado con monitoreo activo:** `backend1=10`, `backend2=10`, `backend3=10`, `backend5=10`, `backend6=10`, `backend7=10`, **sin `ERROR`** (60/60 exitosas).

Esto valida el comportamiento **después de la ventana de detección**. No afirma que no puedan ocurrir errores durante una caída instantánea bajo carga.

---

## 14. Comprobar recuperación de `backend4`

Inicia el servidor:

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml --profile siete start backend4
```

Espera a que vuelva a estar sano y que Apache lo reincorpore:

```powershell
Start-Sleep -Seconds 8
docker compose -p balanceador-lab -f balanceador/compose.test.yml --profile siete ps
```

Repite 70 solicitudes:

```powershell
1..70 | ForEach-Object {
    try {
        (Invoke-RestMethod 'http://localhost:8080/' -TimeoutSec 10).Trim()
    }
    catch {
        'ERROR'
    }
} | Group-Object | Sort-Object Name | Select-Object Name, Count
```

**Resultado observado:** `backend1` a `backend7` recibieron **10 solicitudes cada uno**, con **70/70 exitosas**, sin reiniciar Apache.

---

## 15. Evidencias y registros

Crear carpeta para la evidencia específica del integrante 1:

```powershell
New-Item -ItemType Directory -Force .\balanceador\evidencias | Out-Null
```

Guardar los registros de fallo anteriores, si siguen disponibles en Docker:

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml logs --no-color balanceador |
    Select-String 'AH00898| 500 |Backends=' |
    Out-File .\balanceador\evidencias\fallo_backend4.log -Encoding utf8
```

**No esperes que los errores antiguos aparezcan en un contenedor reconstruido:** Docker Compose puede eliminar el contenedor anterior y sus logs cuando lo recrea. Para conservarlos utiliza el archivo de registro ya compartido en la conversación o las capturas originales, sin fabricar nuevas líneas de log.

Capturas recomendadas:

1. `docker compose ... ps` en los escenarios de 3, 5 y 7.
2. `httpd -t` con `Syntax OK`.
3. `httpd -M` mostrando `proxy_hcheck_module` y los módulos de balanceo.
4. `balancer-members.conf` con método y parámetros de salud.
5. Conteos reales por backend para ambos algoritmos y 3/5/7 backends.
6. Prueba de caída original (59/60) y corregida (60/60 tras esperar).
7. Recuperación (70/70) y los mensajes de error originales, si se conservaron.

**No presentar la prueba secuencial como evaluación p95/p99 ni como sustituto de Artillery.**

---

## 16. Reglas para integrar la solución con el equipo

El integrante 3 debe crear/actualizar el **`docker-compose.yml` de la raíz**, conectar Apache con los backends definitivos y Artillery, configurar la red y las variables y verificar un despliegue limpio. El integrante 1 **no debe reemplazar** ese archivo con `compose.test.yml`.

Ejemplo de contrato mínimo en el Compose de integración (**orientativo, no sustituye la configuración completa**):

```yaml
services:
  balanceador:
    build: ./balanceador
    ports:
      - "8080:80"
    environment:
      BACKEND_COUNT: "${BACKEND_COUNT:-3}"
      BALANCER_METHOD: "${BALANCER_METHOD:-byrequests}"
    depends_on:
      backend1:
        condition: service_healthy
      backend2:
        condition: service_healthy
      backend3:
        condition: service_healthy
    networks:
      - red-proyecto

networks:
  red-proyecto:
    driver: bridge
```

Los backends deberán conectarse a `red-proyecto`, escuchar en el puerto `80`, identificar el servidor que atendió la petición y responder `GET /health` con HTTP 200 cuando estén sanos. Los escenarios de 5/7 deben incluir los servicios adicionales y sus condiciones de inicio.

**Importante:** `depends_on` ayuda con el orden de arranque; no sustituye el monitoreo durante la ejecución. Hay que usar backends definitivos preparados para recibir el tráfico real que probará Artillery.

---

## 17. Revisión de Git y publicación de la rama

**Se realizan desde la raíz del repositorio, en PowerShell.**

Primero verifica el estado:

```powershell
git branch --show-current
git status
git diff --check
```

Debe mostrarse la rama:

```text
feature/parte1-balanceador-apache
```

Si todavía no aparece esta guía dentro de `balanceador/`, copia el archivo actualizado a esa carpeta antes de crear el commit.

Agrega **solo** lo que pertenece a tu parte:

```powershell
git add balanceador/
git diff --cached --check
git diff --cached --stat
git diff --cached --name-status
```

Comprueba que no se hayan incluido secretos, archivos temporales ajenos al proyecto ni cambios de los demás integrantes.

Luego publica tu rama:

```powershell
git commit -m "feat: configurar balanceador Apache con monitoreo activo"
git push -u origin feature/parte1-balanceador-apache
```

Abre un **Pull Request** de `feature/parte1-balanceador-apache` hacia la rama de integración que el equipo haya acordado (por ejemplo, `main`, si esa es la política del grupo). No hagas `push --force` ni fusiones sin revisión.

En el PR incluye: descripción de ambos algoritmos, escenarios de 3/5/7, evidencia de caída/recuperación, limitaciones, dependencia obligatoria de `GET /health` y referencia a `CONTRATO_INTEGRACION.md`.

---

## 18. Apagar exclusivamente el laboratorio

```powershell
docker compose -p balanceador-lab -f balanceador/compose.test.yml --profile cinco --profile siete down --remove-orphans
Remove-Item Env:BACKEND_COUNT -ErrorAction SilentlyContinue
Remove-Item Env:BALANCER_METHOD -ErrorAction SilentlyContinue
```

Este comando no borra tus archivos ni la rama Git. **No uses** `docker system prune -a` ni `docker compose down -v` de forma indiscriminada: podrías eliminar recursos de otros proyectos.

---

## 19. Problemas habituales y qué revisar

| Síntoma | Comprobación o solución |
|---|---|
| Docker no responde | Abrir Docker Desktop; comprobar `docker info`. |
| Puerto 8080 ocupado | Identificar proceso que lo usa; cambiar el puerto publicado solo en el laboratorio o coordinar con el equipo. |
| Apache no arranca | `docker compose ... logs balanceador` y `httpd -t`. |
| `invalid lbmethod` | Revisar `BALANCER_METHOD` y los módulos `lbmethod_byrequests`/`lbmethod_bybusyness`. |
| `proxy_hcheck` no aparece | Verificar que se reconstruyó la imagen a partir del Dockerfile actualizado. |
| Backend sano en Docker pero excluido de Apache | Confirmar `GET /health` HTTP 200 desde la red Docker y los parámetros `hcmethod/hcuri`. |
| `AH00898` al detener un backend | Revisar DNS y momento de la petición: puede ocurrir antes de que Apache complete la detección del fallo. |
| Todos los backends responden 503 | Comprobar red compartida, nombres DNS, puertos y salud; quizá Apache no encuentra ningún backend utilizable. |
| Aparece error HTTP 500 | Revisar logs; no afirmar que se solucionó solo porque otra serie no falló. |
| Faltan los backend4..7 | Revisar perfil `cinco`/`siete`, `BACKEND_COUNT` y estado de contenedores. |
| Error `^M` al ejecutar `entrypoint.sh` | Corregir saltos de línea CRLF → LF; mantener `.gitattributes`. |
| `/balancer-manager` devuelve 403 desde Windows | Es el comportamiento previsto por `Require local`; no abrir públicamente. |
| `byrequests` y `bybusyness` presentan los mismos conteos | Con solicitudes secuenciales es normal; la comparación de desempeño requiere carga concurrente con Artillery. |
| No aparecen logs antiguos | Pueden haberse eliminado al recrear el contenedor. Utilizar registros/capturas guardados anteriormente. |

---

## 20. Lista de verificación de entrega

- [x] Docker Compose local validado.
- [x] Apache construido y ejecutado con `Syntax OK`.
- [x] Algoritmo `byrequests` probado con 3 backends.
- [x] Algoritmo `bybusyness` probado con 3 backends.
- [x] Distribución probada con 5 y 7 backends.
- [x] Error inicial de caída analizado y registrado.
- [x] Monitoreo activo `mod_proxy_hcheck` habilitado y probado.
- [x] Caída de `backend4`: 60/60 respuestas correctas tras esperar detección.
- [x] Recuperación de `backend4`: 70/70 respuestas correctas.
- [ ] Actualizar `CONTRATO_INTEGRACION.md` en el repositorio local.
- [ ] Reemplazar esta guía en `balanceador/GUIA_PASO_A_PASO.md`.
- [ ] Confirmar con los integrantes 2 y 3 los nombres, el puerto y `GET /health`.
- [ ] Revisar `git status` y abrir el Pull Request de tu rama.
- [ ] Validar el sistema integrado con los backends definitivos y Artillery.

Las casillas marcadas corresponden a los resultados y capturas compartidos en la conversación; **no** representan una nueva ejecución automática en el computador del usuario.

---

## 21. Referencias oficiales

- Apache HTTP Server — `mod_proxy_balancer`: https://httpd.apache.org/docs/2.4/mod/mod_proxy_balancer.html
- Apache HTTP Server — `mod_proxy`: https://httpd.apache.org/docs/2.4/mod/mod_proxy.html
- Apache HTTP Server — `mod_proxy_hcheck`: https://httpd.apache.org/docs/2.4/mod/mod_proxy_hcheck.html
- Apache HTTP Server — `mod_lbmethod_bybusyness`: https://httpd.apache.org/docs/2.4/mod/mod_lbmethod_bybusyness.html
- Docker — perfiles de Compose: https://docs.docker.com/compose/how-tos/profiles/
- Docker — interpolación de variables: https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/
