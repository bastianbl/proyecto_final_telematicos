# Integrante 1: Apache HTTP Server con mod_proxy_balancer
# Imagen de la rama 2.4 fijada para reducir diferencias entre equipos.
FROM httpd:2.4.69

# La imagen oficial httpd no incluye a2enmod (propio de Debian apache2).
# Habilitamos los modulos que ya trae compilados y comprobamos cada uno.
RUN set -eux; \
    for mod in proxy proxy_http slotmem_shm proxy_balancer lbmethod_byrequests lbmethod_bybusyness status watchdog proxy_hcheck; do \
        sed -i -E "s|^[[:space:]]*#[[:space:]]*(LoadModule[[:space:]]+${mod}_module[[:space:]]+modules/mod_${mod}[.]so)|\\1|" /usr/local/apache2/conf/httpd.conf; \
        grep -Eq "^[[:space:]]*LoadModule[[:space:]]+${mod}_module[[:space:]]" /usr/local/apache2/conf/httpd.conf; \
    done; \
    printf '\nInclude conf/extra/balancer.conf\n' >> /usr/local/apache2/conf/httpd.conf

COPY balancer.conf /usr/local/apache2/conf/extra/balancer.conf
COPY entrypoint.sh /usr/local/bin/balancer-entrypoint.sh
RUN chmod +x /usr/local/bin/balancer-entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/balancer-entrypoint.sh"]
CMD ["httpd", "-DFOREGROUND"]
