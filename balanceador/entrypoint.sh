#!/bin/sh
set -eu

BACKEND_COUNT="${BACKEND_COUNT:-3}"
BALANCER_METHOD="${BALANCER_METHOD:-byrequests}"
BACKEND_WEIGHTS="${BACKEND_WEIGHTS:-}"
BACKEND_SPARES="${BACKEND_SPARES:-0}"
# Modo de nombres de los backends (anadido para "docker compose up --scale"):
#  - fijo  (por defecto): backend1..backendN, servicios separados del compose.
#  - scale: replicas de un unico servicio "backend"; Docker las nombra
#           <BACKEND_SCALE_PREFIX>1, 2, ... (proyecto-telematicos-backend-1, ...).
# Apache necesita un BalancerMember por replica para repartir y vigilar la
# salud de cada una; un unico "backend" no bastaria (ver README).
BACKEND_MODE="${BACKEND_MODE:-fijo}"
BACKEND_SCALE_PREFIX="${BACKEND_SCALE_PREFIX:-proyecto-telematicos-backend-}"

fail() {
    printf 'ERROR [balanceador]: %s\n' "$*" >&2
    exit 1
}

case "$BACKEND_MODE" in
    fijo)
        # Mantener las tres escalas originales del proyecto.
        case "$BACKEND_COUNT" in
            3|5|7) ;;
            *) fail "BACKEND_COUNT debe ser 3, 5 o 7 (actual: $BACKEND_COUNT)" ;;
        esac
        BACKEND_HOST_PREFIX=backend
        ;;
    scale)
        case "$BACKEND_COUNT" in
            ''|*[!0-9]*) fail "BACKEND_COUNT debe ser un entero (actual: $BACKEND_COUNT)" ;;
        esac
        [ "$BACKEND_COUNT" -ge 1 ] && [ "$BACKEND_COUNT" -le 20 ] || fail "En modo scale BACKEND_COUNT debe estar entre 1 y 20"
        # Solo letras minusculas, digitos y guiones: nunca se escribe texto arbitrario en la configuracion.
        case "$BACKEND_SCALE_PREFIX" in
            ''|*[!a-z0-9-]*) fail "BACKEND_SCALE_PREFIX solo admite a-z, 0-9 y guiones" ;;
        esac
        BACKEND_HOST_PREFIX=$BACKEND_SCALE_PREFIX
        ;;
    *) fail "BACKEND_MODE debe ser fijo o scale (actual: $BACKEND_MODE)" ;;
esac

# Tercer algoritmo de Apache: bytes enviados/recibidos por cada worker.
case "$BALANCER_METHOD" in
    byrequests|bybusyness|bytraffic) ;;
    *) fail "BALANCER_METHOD debe ser byrequests, bybusyness o bytraffic" ;;
esac

# Numero de servidores de reserva al final del pool (0 por defecto).
case "$BACKEND_SPARES" in
    0|1|2|3|4|5|6) ;;
    *) fail "BACKEND_SPARES debe ser un entero entre 0 y 6" ;;
esac
[ "$BACKEND_SPARES" -lt "$BACKEND_COUNT" ] || fail "BACKEND_SPARES debe ser menor que BACKEND_COUNT"

# Comprobar la lista antes de generar configuracion Apache.
# Se aceptan enteros de 1 a 100; nunca se ejecuta texto ingresado.
if [ -n "$BACKEND_WEIGHTS" ]; then
    case "$BACKEND_WEIGHTS" in
        *[!0-9,]*|,*|*,|*,,*) fail "BACKEND_WEIGHTS debe contener enteros separados por comas, sin espacios" ;;
    esac
fi

build_members() {
    # Dentro de una funcion, set -- no reemplaza los argumentos del ENTRYPOINT.
    if [ -z "$BACKEND_WEIGHTS" ]; then
        set --
        index=1
        while [ "$index" -le "$BACKEND_COUNT" ]; do
            set -- "$@" 1
            index=$((index + 1))
        done
    else
        old_ifs=$IFS
        IFS=,
        set -- $BACKEND_WEIGHTS
        IFS=$old_ifs
    fi

    [ "$#" -eq "$BACKEND_COUNT" ] || fail "BACKEND_WEIGHTS exige $BACKEND_COUNT valores (recibidos: $#)"
    for weight do
        case "$weight" in
            ''|*[!0-9]*) fail "Peso invalido: $weight" ;;
        esac
        [ "$weight" -ge 1 ] && [ "$weight" -le 100 ] || fail "Cada peso debe estar entre 1 y 100"
    done

    members_file="/usr/local/apache2/conf/extra/balancer-members.conf"
    : > "$members_file"
    last_active=$((BACKEND_COUNT - BACKEND_SPARES))
    index=1
    for weight do
        status_param=''
        if [ "$index" -gt "$last_active" ]; then
            # Hot spare: reemplaza a un miembro activo que deja de ser utilizable.
            status_param=' status=+R'
        fi
        # addressttl=5: Apache vuelve a resolver el nombre del backend cada 5 s.
        # Sin esto guarda la primera IP para siempre y, si Docker le da otra IP
        # al contenedor tras reiniciarlo, envia las peticiones a otro backend.
        printf '    BalancerMember "http://%s%s:80" loadfactor=%s retry=2 connectiontimeout=2 timeout=10 addressttl=5 hcmethod=GET hcuri=/health hcinterval=2 hcfails=1 hcpasses=1%s\n' \
            "$BACKEND_HOST_PREFIX" "$index" "$weight" "$status_param" >> "$members_file"
        index=$((index + 1))
    done
    printf '    ProxySet lbmethod=%s\n' "$BALANCER_METHOD" >> "$members_file"
}

build_members
printf '[balanceador] Backends=%s metodo=%s pesos=%s reservas=%s modo=%s\n' \
    "$BACKEND_COUNT" "$BALANCER_METHOD" "${BACKEND_WEIGHTS:-todos=1}" "$BACKEND_SPARES" "$BACKEND_MODE" >&2
httpd -t
exec "$@"
