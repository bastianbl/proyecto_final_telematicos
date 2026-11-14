# Contrato de integración — Integrante 1 / Apache

## 1. Qué debe respetar el equipo

1. El servicio `balanceador` se construye mediante `build: ./balanceador` y escucha HTTP en el **puerto 80 dentro del contenedor**.

2. Todos los backends y el balanceador Apache deben pertenecer a la **misma red interna de Docker Compose**, para permitir la comunicación entre los servicios.

3. Los nombres DNS internos de los servicios deben ser **`backend1`, `backend2`, ..., `backend7`**. No se deben utilizar nombres como `backend-1`, `backend_1` o `web1`, salvo que se modifique de forma coordinada la configuración del balanceador.

4. Todos los backends deben cumplir las siguientes condiciones:
   - Escuchar HTTP en el **puerto interno 80**.
   - Responder a `GET /` con un identificador que permita reconocer qué servidor atendió la solicitud.
   - Implementar el endpoint **`GET /health`**, que debe devolver HTTP `200 OK` cuando el servicio esté funcionando correctamente.
   - Mantener el endpoint `/health` accesible desde el balanceador a través de la red Docker.
   - El endpoint de salud debe verificar las condiciones necesarias para considerar operativo al backend, según las funcionalidades que implemente el integrante 2.

5. La variable `BACKEND_COUNT` admite los valores `3`, `5` y `7`. Su valor debe coincidir con la cantidad de backends desplegados y disponibles en la configuración del proyecto.

6. La variable `BALANCER_METHOD` admite los siguientes algoritmos:
   - `byrequests`: distribuye solicitudes de acuerdo con los factores de balanceo configurados. Con pesos iguales, busca una distribución equilibrada.
   - `bybusyness`: prioriza los servidores con menos solicitudes activas en procesamiento.

   **Nota:** `bybusyness` no equivale exactamente a *least connections*, pero permite evaluar un criterio de distribución basado en la carga activa.

7. Cualquier cambio en `BACKEND_COUNT` o `BALANCER_METHOD` requiere recrear el contenedor `balanceador`, ya que el archivo `balancer-members.conf` se genera automáticamente al iniciar Apache.

8. Los endpoints administrativos `balancer-manager` y `server-status` permanecen restringidos mediante `Require local`. No deben exponerse públicamente ni habilitarse sin definir previamente mecanismos de seguridad.

9. Los archivos `compose.test.yml` y la carpeta `test-fixtures/` pertenecen exclusivamente al **laboratorio autónomo del integrante 1**. Su finalidad es validar Apache utilizando backends temporales. No reemplazan el archivo `docker-compose.yml` principal ni los backends oficiales desarrollados por el integrante 2.

10. El balanceador incorpora **monitoreo activo de salud mediante `mod_proxy_hcheck`**. Apache comprueba periódicamente la disponibilidad de los backends consultando `/health`.

    La configuración implementada utiliza:

    - `hcmethod=GET`: realiza solicitudes HTTP GET.
    - `hcuri=/health`: establece el endpoint de verificación.
    - `hcinterval=2`: establece un intervalo de dos segundos entre comprobaciones.
    - `hcfails=1`: permite marcar un backend como no saludable después de una comprobación fallida.
    - `hcpasses=1`: permite reincorporar un backend cuando supera una comprobación de salud.

    Cuando un backend deja de responder correctamente, Apache puede excluirlo de la distribución de nuevas solicitudes. Cuando vuelve a estar disponible y supera la comprobación, puede reincorporarse automáticamente.

    **Importante:** el monitoreo activo reduce los errores durante fallos, pero no garantiza que todas las solicitudes se completen correctamente si un servidor se detiene durante el procesamiento de una petición.

11. Se mantiene el parámetro `retry=2`, utilizado por el mecanismo de reintento de los miembros del balanceador. Este mecanismo complementa la configuración de monitoreo activo, pero no sustituye las comprobaciones periódicas de disponibilidad.

12. Los healthchecks de Docker Compose y los de Apache cumplen funciones complementarias:
    - Docker Compose permite comprobar el estado de salud de los contenedores y establecer condiciones de arranque.
    - Apache utiliza `mod_proxy_hcheck` para decidir qué backends pueden participar en el balanceo.

    Por lo tanto, un backend puede estar iniciado como contenedor, pero no ser considerado saludable por Apache si su endpoint `/health` falla.

## 2. Ejemplo orientativo de integración

**Este ejemplo NO modifica el archivo `docker-compose.yml` real.**

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

**Ajustes obligatorios para el integrante 3:**

- Configurar la red compartida `red-proyecto` y conectar allí todos los servicios.
- Integrar los backends oficiales desarrollados por el integrante 2.
- Garantizar que los backends implementen `GET /health` y cuenten con healthchecks compatibles.
- Configurar los servicios adicionales para los escenarios de 5 y 7 backends.
- Asegurar que el valor de `BACKEND_COUNT` coincida con los servicios desplegados.
- Mantener las variables de entorno configurables mediante el archivo `.env`.
- Coordinar la secuencia de inicio de los servicios para evitar que Apache intente comunicarse con backends que todavía no estén preparados.

El ejemplo muestra únicamente el escenario inicial de tres backends. Los escenarios de cinco y siete servidores requieren ampliar la configuración de Docker Compose.

## 3. Responsabilidad de los archivos

| Responsable | Archivos |
|---|---|
| Integrante 1 | `balanceador/` |
| Integrante 2 | `backend/` |
| Integrante 3 | `docker-compose.yml`, Makefile y scripts del proyecto |
| Integrante 4 | `pruebas/` (Artillery) |
| Integrante 5 | `metricas/` |
| Integrante 6 | `README.md` raíz, `evidencias/` y coordinación del monitoreo |

El integrante 1 es responsable de mantener y documentar la configuración de Apache y su mecanismo de monitoreo activo. El integrante 6 podrá utilizar los registros y resultados del balanceador para desarrollar las actividades generales de supervisión y documentación del proyecto.

## 4. Pruebas realizadas por el integrante 1

Las siguientes pruebas se ejecutaron utilizando Docker Desktop, Apache y los servidores temporales definidos en `test-fixtures/`.

### Algoritmos de balanceo

| Algoritmo | Servidores | Solicitudes | Resultado |
|---|---:|---:|---|
| `byrequests` | 3 | 21 | 7 por servidor |
| `bybusyness` | 3 | 21 | 7 por servidor |
| `byrequests` | 5 | 35 | 7 por servidor |
| `byrequests` | 7 | 70 | 10 por servidor |

Estas pruebas verificaron la distribución funcional de solicitudes. No constituyen una comparación de rendimiento bajo carga concurrente.

### Pruebas de tolerancia a fallos

**Prueba inicial, antes de incorporar el monitoreo activo:**

- Se detuvo el servidor `backend4`.
- Se realizaron 60 solicitudes HTTP.
- Se obtuvieron 59 respuestas exitosas y una fallida.
- Apache registró un error HTTP 500 relacionado con la resolución DNS de `backend4`.

**Prueba posterior, con `mod_proxy_hcheck`:**

- Se detuvo el servidor `backend4`.
- Se esperaron ocho segundos para permitir la detección del fallo.
- Se realizaron 60 solicitudes HTTP.
- Las 60 solicitudes fueron atendidas correctamente por los seis servidores disponibles.
- No se registraron errores en las solicitudes de esa prueba.

**Prueba de recuperación:**

- Se reinició `backend4` sin reiniciar Apache.
- Se esperaron ocho segundos.
- Se realizaron 70 solicitudes HTTP.
- Los siete servidores volvieron a participar en el balanceo.
- Cada backend atendió diez solicitudes y no se registraron errores.

**Limitación:** los resultados corresponden a pruebas funcionales secuenciales y no garantizan ausencia de errores durante fallos repentinos bajo carga concurrente. Esa validación deberá realizarse mediante las pruebas de Artillery.

## 5. Confirmación necesaria antes del Pull Request

Los integrantes 1, 2 y 3 deben confirmar los siguientes acuerdos:

- Nombres DNS de los servicios: `backend1` a `backend7`.
- Puerto HTTP interno de los backends: `80`.
- Red interna compartida entre Apache y los servidores.
- Formato del identificador de cada backend.
- Implementación obligatoria de `GET /health`.
- Variables `BACKEND_COUNT` y `BALANCER_METHOD`.
- Estrategia de despliegue para 3, 5 y 7 backends.
- Configuración de healthchecks y recuperación de servicios.
- Compatibilidad del balanceador con las funcionalidades que desarrolle el integrante 2.

**El objetivo de este contrato es permitir que todos los componentes se integren sin modificar innecesariamente el trabajo de otros integrantes y garantizar que el proyecto pueda ejecutarse desde un despliegue limpio.**
