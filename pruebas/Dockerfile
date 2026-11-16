# Imagen de Artillery del proyecto (pruebas de carga).
#
# Imagen base: artilleryio/artillery (imagen oficial publicada por el equipo de
# Artillery en Docker Hub; trae Node.js y Artillery listos, ENTRYPOINT = artillery).
#
# Por que una VERSION FIJA y no "latest":
#  - "latest" cambia sin aviso: dos integrantes, o la misma persona en dos dias
#    distintos, podrian medir con versiones diferentes y los resultados dejarian
#    de ser comparables.
#  - Con la etiqueta exacta todos ejecutan el mismo Artillery y el reporte JSON
#    tiene siempre el mismo formato (scripts/resumen.py depende de el).
#
# Los escenarios (carga.yml, artillery-smoke.yml, procesador.js) NO se copian en
# la imagen: se montan como volumen en /tests desde docker-compose.yml, asi se
# pueden editar sin reconstruir. Los resultados se escriben en /results (volumen).
# 2.0.34 es la version con la que se generaron los resultados publicados
# (pruebas/resultados/, ejecutados con "latest" el 2026-11-10): fijarla
# mantiene las nuevas corridas comparables con las anteriores.
FROM artilleryio/artillery:2.0.34

WORKDIR /tests
