# Interfaz grafica del proyecto (integrante 2).
# nginx sirve la pagina estatica y hace de proxy hacia el balanceador
# y hacia cada backend, todo dentro de la red de Docker.
# Version exacta fijada para que todos construyan la misma imagen.
FROM nginx:1.27.3-alpine

# Valores por defecto: la imagen oficial sustituye ${VAR} en las plantillas
# de /etc/nginx/templates al arrancar (envsubst). Si no existieran, nginx
# interpretaria ${BACKEND_COUNT} como variable propia y no arrancaria.
# PANEL_DEMO=1 solo con interfaz/compose.interfaz.yml (balanceadores demo 3/5/7).
ENV BACKEND_COUNT=3 \
    BALANCER_METHOD=byrequests \
    PANEL_DEMO=0

COPY default.conf.template /etc/nginx/templates/default.conf.template
COPY html/ /usr/share/nginx/html/

EXPOSE 80

HEALTHCHECK --interval=5s --timeout=2s --start-period=3s --retries=5 \
    CMD wget -q -O /dev/null http://127.0.0.1/panel-config.json || exit 1
