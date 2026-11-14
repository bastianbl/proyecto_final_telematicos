# Evidencias del proyecto

Esta carpeta reúne las pruebas de que el sistema funciona. **Todo debe provenir de ejecuciones reales**: no se editan ni se fabrican logs, capturas ni números.

```text
evidencias/
├── capturas/   Imágenes (.png) de las pruebas
└── logs/       Informes, CSV y logs generados por los scripts
```

## Cómo se generan los logs

Desde la raíz del repositorio, con el sistema levantado (`.\scripts\compose.ps1 -Action Up`):

| Qué | Comando | Genera en `logs/` |
|---|---|---|
| Verificación general | `.\scripts\verificar.ps1` | `verificacion_<N>b_<fecha>.txt` |
| Caída y recuperación de un backend | `.\scripts\prueba_caida.ps1` | `caida_backendX_<N>b_<método>_<fecha>` (`.csv`, `_resumen.txt`, `_apache.log`, `_apache_eventos.log`, `_backendX.log`) |
| Foto del estado (logs, estadísticas, config) | `.\scripts\recolectar_evidencias.ps1` | carpeta `snapshot_<N>b_<fecha>/` |

## Capturas recomendadas

Nombra cada imagen como `NN_descripcion.png` (por ejemplo `03_ps_3backends.png`) y haz la captura **cuando ejecutas la prueba**, no al final.

| # | Captura | Cómo obtenerla |
|---|---|---|
| 01 | Contenedores con 3 backends (`healthy`) | `.\scripts\compose.ps1 -Action Status` |
| 02 | Verificación general en 3 backends | `.\scripts\verificar.ps1` |
| 03 | Contenedores y verificación con 5 backends | `compose.ps1 -Action Restart -BackendCount 5` y `verificar.ps1` |
| 04 | Contenedores y verificación con 7 backends | ídem con `-BackendCount 7` |
| 05 | Algoritmo `byrequests` activo (miembros de Apache) | salida de `verificar.ps1` o `apache_miembros.txt` |
| 06 | Algoritmo `bybusyness` activo | `compose.ps1 -Action Restart -BackendCount 3 -BalancerMethod bybusyness` y `verificar.ps1` |
| 07 | Caída y recuperación de un backend | pantalla final de `.\scripts\prueba_caida.ps1` |
| 08 | Caída con 7 backends (otro backend) | `.\scripts\prueba_caida.ps1 -BackendCount 7 -Backend 4` |
| 09 | Ejecución de Artillery | salida de `correr_pruebas.ps1` |
| 10 | Gráficas de métricas | desde `metricas/graficas/` |
| 11 | Docker Desktop mostrando un backend detenido | durante la prueba de caída |

## Validación desde cero (la hace una persona distinta al autor)

El plan exige que alguien que no escribió el proyecto lo levante siguiendo solo el `README.md` principal.

- [ ] Clonó el repositorio en una carpeta nueva.
- [ ] Copió `.env.example` a `.env` y levantó el sistema con 3 backends.
- [ ] `.\scripts\verificar.ps1` terminó con todo en `OK`.
- [ ] Cambió a 5 y a 7 backends y a `bybusyness` siguiendo el README.
- [ ] Ejecutó `.\scripts\prueba_caida.ps1` y el backend volvió a recibir tráfico.
- [ ] Ejecutó el smoke test de Artillery (`.\scripts\compose.ps1 -Action Artillery`).
- [ ] Apagó con `.\scripts\compose.ps1 -Action Down`.
- Persona que validó: ______________  Fecha: ____________
- Problemas encontrados y cómo se resolvieron: ______________________________

## Notas

- Si `.gitignore` excluye `*.log` o `*.csv`, revisa con `git status` qué archivos de `evidencias/` se van a subir realmente.
- Los logs de un contenedor se pierden si el contenedor se elimina (`down`). Ejecuta `recolectar_evidencias.ps1` **antes** de apagar.
- No guardes el archivo `.env` ni credenciales en esta carpeta.
