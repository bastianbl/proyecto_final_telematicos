# Pruebas de carga con Artillery (integrante 4)

Requisitos: Docker Desktop. Artillery corre dentro de Docker (no hay que instalar nada más); Python 3 solo para el resumen.

## Ejecutar una configuración completa (50, 100, 500 y 1000 usuarios)

```powershell
Copy-Item .env.example .env   # solo la primera vez
.\scripts\correr_pruebas.ps1 -BackendCount 3 -BalancerMethod byrequests
.\scripts\correr_pruebas.ps1 -BackendCount 3 -BalancerMethod bybusyness
.\scripts\correr_pruebas.ps1 -BackendCount 5 -BalancerMethod byrequests   # ... y así hasta cubrir 3/5/7 x 2 algoritmos
python scripts\resumen.py
```

Cada ejecución reinicia el stack con esa configuración, hace un calentamiento y guarda en `pruebas/resultados/`:
`<algoritmo>_<N>b_<carga>_<fecha>.json` (datos de Artillery) y `.txt` (salida de consola).
`resumen.csv` reúne p50/p95/p99, requests por segundo, errores y reparto por backend; es la entrada del integrante 5.

## Caída y recuperación de un backend

```powershell
.\scripts\correr_pruebas.ps1 -BackendCount 3 -BalancerMethod byrequests -Escenario caida
# en OTRA terminal, durante los 120 s (anota la hora de cada acción):
docker compose stop backend2
docker compose start backend2
```

## Diseño (para comparar justo)

- Un solo escenario (`carga.yml`) para todos los algoritmos y números de backends: solo cambia la configuración del balanceador.
- Cada usuario virtual hace 3 peticiones a `/work` (200 ms de trabajo simulado en el backend); los usuarios llegan repartidos en 30 s.
- `procesador.js` cuenta las respuestas por backend usando el header `X-Backend-ID`.
- `artillery-smoke.yml` (integrante 3) se conserva como prueba rápida de integración.
- Cerrar otros programas pesados durante las pruebas: si el equipo se satura, los resultados no son válidos.

## Imagen de Artillery

Artillery se ejecuta con una imagen propia, [`pruebas/Dockerfile`](Dockerfile), basada en
`artilleryio/artillery` con **versión fija**, en vez de `latest`. Con `latest`, dos
ejecuciones en días distintos podrían usar versiones diferentes y dejar de ser comparables.
Los escenarios se montan en `/tests` y los resultados se escriben en `pruebas/resultados/`
mediante volúmenes, así que no hace falta reconstruir la imagen al editar un escenario.

El servicio `artillery` es de **ejecución puntual**: arranca, lanza la prueba y termina.
Su healthcheck (`artillery version`) solo tiene efecto mientras la prueba está en marcha,
y es normal que no aparezca en `docker compose ps` cuando no hay ninguna prueba corriendo.

## "N usuarios" son llegadas, no usuarios simultáneos

En `carga.yml`, `arrivalCount: N` con `duration: 30` significa que **llegan N usuarios
virtuales repartidos en 30 s**, es decir, `N/30` llegadas por segundo. Cada usuario hace
su recorrido y se va. **No hay N usuarios conectados a la vez.**

La concurrencia real se estima con la ley de Little:
`usuarios simultáneos ≈ llegadas por segundo × duración de cada usuario`.

**Duración prevista por el diseño:** 3 peticiones de ~200 ms + 2 pausas de 0,5 s ≈ **1,6 s**.

**Duración medida en los resultados publicados:** `vusers.session_length` vale entre
**0,62 y 0,94 s** (media ≈ 0,67 s). Las pausas `think: 0.5` **no se aplicaron**: en los
`.txt`, Artillery muestra `TimeoutNaNWarning: NaN is not a number. Timeout duration was set to 1`,
o sea, cada pausa duró ~1 ms. Cada usuario hizo sus 3 peticiones casi seguidas. Los
resultados siguen siendo válidos como medida, pero la concurrencia fue menor que la prevista:

| Carga (`arrivalCount` en 30 s) | Llegadas/s | Simultáneos con 1,6 s (diseño) | Simultáneos con ~0,67 s (medido) | Peticiones en curso a la vez (≈ llegadas/s × 3 × 0,2 s) |
|---|---:|---:|---:|---:|
| 50   | 1,7  | ~3  | ~1  | ~1  |
| 100  | 3,3  | ~5  | ~2  | ~2  |
| 500  | 16,7 | ~27 | ~11 | ~10 |
| 1000 | 33,3 | ~53 | ~23 | ~20 |

Conclusión: la prueba "1000 usuarios" equivale a ~23 usuarios simultáneos y ~20 peticiones
en curso, repartidas entre 3, 5 o 7 backends. Por eso ningún escenario saturó el sistema
(p95 ≈ 205-370 ms con 200 ms de trabajo simulado). En el informe conviene hablar de
"N usuarios que llegan en 30 s", no de "N usuarios concurrentes".

**Comprobación (16/11/2026).** El aviso `TimeoutNaNWarning` aparece en **las 24 de 24**
salidas `.txt` publicadas, y la sesión media de los 24 JSON está entre 625 y 935 ms. Una
corrida nueva con la imagen fijada 2.0.34 (`make carga CARGA=carga500`) da también una
sesión media de 685 ms: el problema es de `think: 0.5` con esta versión de Artillery, no de
una ejecución concreta. `carga.yml` y los resultados publicados **no se modificaron**.

**Por qué los resultados publicados siguen siendo válidos como comparación entre escenarios:**

- **El defecto es idéntico en las 24 corridas.** Mismo escenario, misma versión de Artillery,
  mismo aviso. Todas las configuraciones (3/5/7 backends × 2 algoritmos × 4 cargas) recibieron
  exactamente el mismo patrón de peticiones, así que la comparación entre ellas es justa.
- **Lo que se mide por petición se midió bien.** Cada usuario hizo sus 3 peticiones a `/work`.
  La latencia (media, p95, p99), los errores y el reparto por backend (`X-Backend-ID`) no
  dependen de la pausa entre peticiones.
- **El total de peticiones y las llegadas no cambian.** Llegaron N usuarios en 30 s y cada uno
  hizo 3 peticiones (3 × N en total), y el throughput coincide con la carga ofrecida.
- **Lo que sí cambia es la intensidad:** hubo menos usuarios a la vez (tabla de arriba). Por eso
  los resultados **no** sirven para hablar de saturación o capacidad máxima; para eso está
  `concurrencia.yml` (~500 usuarios simultáneos, con `think: 1`).

## Escenarios adicionales (preparados, todavía sin ejecutar)

No reemplazan a `carga.yml` ni a los resultados publicados. Sus resultados van a
`pruebas/resultados/make/`, que `scripts/resumen.py` no lee, así que no alteran `resumen.csv`.

| Archivo | Qué mide | Cómo se ejecuta |
|---|---|---|
| [`concurrencia.yml`](concurrencia.yml) | **~500 usuarios simultáneos** durante ~60 s: llegan 500 en 10 s y cada uno hace 60 × (`/work` + 1 s de pausa) | `make concurrencia` |
| [`compose.heterogeneo.yml`](compose.heterogeneo.yml) | `backend1` con `WORK_DELAY_MS=1000` y los demás con 200: diferencia entre `byrequests` y `bybusyness` | Ver los comandos dentro del archivo |

`concurrencia.yml` usa `think: 1` (pausa entera) porque `think: 0.5` produjo el aviso
`TimeoutNaNWarning`. Al ejecutarlo hay que comprobar que el aviso **no** aparece y que
`vusers.session_length` ronda los 72 000 ms. Si no es así, el escenario no mide lo que dice.

## Desde Linux, macOS o Git Bash (Makefile)

```bash
make up                    # levanta el escenario de .env
make smoke                 # prueba rápida de integración (no sobrescribe artillery-report.json)
make carga CARGA=carga100  # carga.yml; resultado en pruebas/resultados/make/
make estado ETIQUETA=antes # captura /balancer-manager y /server-status antes de la carga
make estado ETIQUETA=despues
```
