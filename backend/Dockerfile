# Integrante 2: backend definitivo del proyecto.
# Imagen base fijada a una version exacta (Python 3.12.7 sobre Alpine 3.20)
# para que todos los integrantes construyan exactamente lo mismo.
# Se usa solo la biblioteca estandar: no hay pip install ni dependencias.
FROM python:3.12.7-alpine3.20

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=80 \
    WORK_DELAY_MS=200 \
    WORK_CPU_MS=0

WORKDIR /app
COPY app.py healthcheck.py ./

# Usuario sin privilegios. Docker (>= 20.10) permite a procesos no root
# abrir puertos < 1024 dentro del contenedor (ip_unprivileged_port_start=0).
RUN adduser -D -H -u 10001 app
USER app

EXPOSE 80

# Docker marca el contenedor healthy/unhealthy con esta comprobacion;
# Compose la usa en depends_on: condition: service_healthy.
HEALTHCHECK --interval=3s --timeout=2s --start-period=3s --retries=10 \
    CMD ["python", "/app/healthcheck.py"]

# Forma exec: Python es el PID 1 y recibe directamente SIGTERM.
CMD ["python", "/app/app.py"]
