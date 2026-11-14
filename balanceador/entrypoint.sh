#!/bin/sh
set -eu

BACKEND_COUNT="${BACKEND_COUNT:-3}"
BALANCER_METHOD="${BALANCER_METHOD:-byrequests}"

# Valores admitidos y probables segun la rubrica del proyecto.
case "$BACKEND_COUNT" in
    3|5|7) ;;
    *) echo "ERROR: BACKEND_COUNT debe ser 3, 5 o 7 (actual: $BACKEND_COUNT)" >&2; exit 1 ;;
esac
case "$BALANCER_METHOD" in
    byrequests|bybusyness) ;;
    *) echo "ERROR: BALANCER_METHOD debe ser byrequests o bybusyness" >&2; exit 1 ;;
esac

# Nombres estables pactados con los integrantes 2 y 3: backend1...backend7.
# Cada backend escucha en el puerto 80 dentro de la red de Docker Compose.
members_file="/usr/local/apache2/conf/extra/balancer-members.conf"
: > "$members_file"
i=1
while [ "$i" -le "$BACKEND_COUNT" ]; do
    printf '    BalancerMember "http://backend%s:80" retry=2 connectiontimeout=2 timeout=10 hcmethod=GET hcuri=/health hcinterval=2 hcfails=1 hcpasses=1\n' "$i" >> "$members_file"
    i=$((i + 1))
done
printf '    ProxySet lbmethod=%s\n' "$BALANCER_METHOD" >> "$members_file"

printf '[balanceador] Backends=%s, metodo=%s\n' "$BACKEND_COUNT" "$BALANCER_METHOD" >&2
httpd -t
exec "$@"
