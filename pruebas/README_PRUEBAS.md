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
