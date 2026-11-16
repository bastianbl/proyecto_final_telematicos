# Integrante 2: backend definitivo del proyecto.
#
# Imagen base: httpd:2.4.69 (Apache HTTP Server oficial, Debian bookworm).
# Por que:
#  - El enunciado exige servidores web backend Apache o Nginx: el servidor web
#    del contenedor es Apache httpd, y app.py queda detras como aplicacion.
#  - Es exactamente la misma version y la misma imagen que usa el balanceador
#    (balanceador/Dockerfile): una sola version de Apache en todo el proyecto
#    y las capas de la imagen se comparten en disco y en la descarga.
#  - Etiqueta exacta (no "latest" ni "2.4") para que todos construyan lo mismo.
# Python 3 se instala desde los repositorios de Debian bookworm (3.11.x); app.py
# solo usa la biblioteca estandar, sin pip ni dependencias externas.
FROM httpd:2.4.69

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=80 \
    WORK_DELAY_MS=200 \
    WORK_CPU_MS=0 \
    WORK_MAX_MS=10000 \
    BACKEND_PROXY_TIMEOUT=25

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends python3; \
    rm -rf /var/lib/apt/lists/*; \
    command -v setpriv; \
    # Usuario sin privilegios para app.py.
    useradd --system --uid 10001 --user-group --no-create-home --shell /usr/sbin/nologin app; \
    conf=/usr/local/apache2/conf/httpd.conf; \
    # Modulos de proxy (vienen compilados pero comentados en httpd.conf).
    for mod in proxy proxy_http; do \
        sed -i -E "s|^[[:space:]]*#[[:space:]]*(LoadModule[[:space:]]+${mod}_module[[:space:]]+modules/mod_${mod}[.]so)|\\1|" "$conf"; \
        grep -Eq "^[[:space:]]*LoadModule[[:space:]]+${mod}_module[[:space:]]" "$conf"; \
    done; \
    # MPM event debe ser el activo (es el defecto de la imagen oficial).
    grep -Eq '^[[:space:]]*LoadModule[[:space:]]+mpm_event_module' "$conf"; \
    # Sin access log de Apache: app.py ya registra cada peticion (con la IP real
    # via X-Forwarded-For) y asi los logs del contenedor no salen duplicados.
    sed -i -E 's|^([[:space:]]*CustomLog[[:space:]])|#\1|' "$conf"; \
    printf '\nInclude conf/extra/backend.conf\n' >> "$conf"

WORKDIR /app
COPY app.py healthcheck.py identidad.py /app/
COPY backend.conf /usr/local/apache2/conf/extra/backend.conf
COPY entrypoint.sh /usr/local/bin/backend-entrypoint.sh
RUN chmod 0755 /usr/local/bin/backend-entrypoint.sh \
    && httpd -t

EXPOSE 80

# Comprueba /health A TRAVES de Apache (puerto 80): falla si cae Apache o app.py.
# El docker-compose.yml define su propio healthcheck equivalente.
HEALTHCHECK --interval=5s --timeout=3s --start-period=15s --retries=3 \
    CMD ["python3", "/app/healthcheck.py", "http://127.0.0.1:80/health"]

# Igual que la imagen httpd: SIGWINCH = parada ordenada de Apache
# (GracefulShutdownTimeout 3 en backend.conf la limita a 3 s).
STOPSIGNAL SIGWINCH

ENTRYPOINT ["/usr/local/bin/backend-entrypoint.sh"]
CMD ["httpd-foreground"]
