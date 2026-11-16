#!/bin/sh
# Entrypoint del backend (integrante 2).
# 1. Valida la configuracion.
# 2. Arranca app.py como usuario sin privilegios en 127.0.0.1:8000.
# 3. Espera a que app.py responda /health.
# 4. Deja un vigilante: si app.py muere, detiene el contenedor.
# 5. exec de httpd-foreground: Apache pasa a ser el PID 1.
set -eu

# Modo --scale (docker compose up --scale backend=N): las replicas no reciben
# BACKEND_ID. Docker las llama <proyecto>-backend-1, -2, ... y su DNS interno
# responde el DNS inverso de la IP del contenedor con ese nombre, asi que el
# numero se toma de ahi (identidad.py pregunta directamente a 127.0.0.11).
# Con backend1..backend7 BACKEND_ID viene del compose.
if [ -z "${BACKEND_ID:-}" ]; then
    BACKEND_ID=$(python3 /app/identidad.py) || BACKEND_ID=""
    if [ -n "$BACKEND_ID" ]; then
        echo "[backend$BACKEND_ID] BACKEND_ID deducido del nombre del contenedor (modo --scale)" >&2
    fi
fi
: "${BACKEND_ID:?ERROR: falta BACKEND_ID y no se pudo deducir del nombre del contenedor}"
export BACKEND_ID
WORK_MAX_MS="${WORK_MAX_MS:-10000}"
case "$WORK_MAX_MS" in
    ''|*[!0-9]*) echo "ERROR [backend]: WORK_MAX_MS debe ser un entero >= 0 (actual: $WORK_MAX_MS)" >&2; exit 1 ;;
esac

APP_HOST=127.0.0.1
APP_PORT=8000
export APP_HOST APP_PORT

# Tiempo maximo que Apache espera a app.py (ver backend.conf).
BACKEND_PROXY_TIMEOUT=$(( (2 * WORK_MAX_MS + 999) / 1000 + 5 ))
export BACKEND_PROXY_TIMEOUT

# app.py corre como "app" (UID 10001), sin grupos extra y sin poder ganar
# privilegios (no_new_privs). Apache sigue siendo root solo en su proceso padre.
setpriv --reuid=app --regid=app --clear-groups --no-new-privs python3 /app/app.py &
APP_PID=$!

# Vivo = existe y no es un zombi (si muere, su padre pasa a ser httpd y el
# proceso podria quedar como zombi un instante antes de que lo recojan).
app_viva() {
    [ -d "/proc/$APP_PID" ] && ! grep -q '^State:[[:space:]]*Z' "/proc/$APP_PID/status" 2>/dev/null
}

intentos=0
until python3 /app/healthcheck.py "http://$APP_HOST:$APP_PORT/health"; do
    if ! app_viva; then
        echo "ERROR [backend$BACKEND_ID]: app.py termino durante el arranque" >&2
        exit 1
    fi
    intentos=$((intentos + 1))
    if [ "$intentos" -ge 100 ]; then
        echo "ERROR [backend$BACKEND_ID]: app.py no respondio en 10 s" >&2
        kill "$APP_PID" 2>/dev/null || true
        exit 1
    fi
    sleep 0.1
done

# Vigilante: si app.py muere, Apache seguiria vivo devolviendo 503. En lugar de
# eso se detiene el contenedor (SIGTERM a httpd, PID 1) y Docker lo reinicia
# segun su politica restart (unless-stopped en el compose del proyecto).
(
    while app_viva; do sleep 1; done
    echo "ERROR [backend$BACKEND_ID]: app.py termino; deteniendo el contenedor" >&2
    kill -TERM 1
) &

echo "[backend$BACKEND_ID] app.py listo en $APP_HOST:$APP_PORT; arrancando Apache en :80 (ProxyTimeout ${BACKEND_PROXY_TIMEOUT}s)" >&2
exec "$@"
