"""Deduce el numero de la replica en modo --scale (docker compose up --scale backend=N).

Docker llama a las replicas <proyecto>-backend-1, -2, ... y su DNS interno
(127.0.0.11) responde al DNS inverso (PTR) de la IP del contenedor con ese
nombre. Se pregunta DIRECTAMENTE a ese DNS con un paquete UDP: socket.gethostbyaddr()
no sirve porque consulta antes /etc/hosts, donde Docker asocia la IP al ID del
contenedor (p. ej. "b8233924cfa9") y nunca llega al nombre.

Imprime el numero (p. ej. "3") y sale con 0; si no lo consigue, sale con 1.
Uso: python3 identidad.py [ip]   (por defecto, la IP propia)
"""

import random
import re
import socket
import struct
import sys
import time

DNS_DOCKER = ("127.0.0.11", 53)


def leer_nombre(datos, pos):
    """Lee un nombre DNS (con compresion por punteros); devuelve (nombre, pos siguiente)."""
    partes, saltado, fin = [], False, pos
    while True:
        largo = datos[pos]
        if largo == 0:
            pos += 1
            break
        if largo & 0xC0 == 0xC0:  # puntero a otra parte del mensaje
            if not saltado:
                fin = pos + 2
            pos = ((largo & 0x3F) << 8) | datos[pos + 1]
            saltado = True
            continue
        partes.append(datos[pos + 1:pos + 1 + largo].decode())
        pos += 1 + largo
    return ".".join(partes), (fin if saltado else pos)


def ptr(ip):
    """Consulta PTR de `ip` al DNS de Docker; devuelve el primer nombre o None."""
    nombre = ".".join(reversed(ip.split("."))) + ".in-addr.arpa"
    ident = random.randint(0, 0xFFFF)
    consulta = struct.pack(">HHHHHH", ident, 0x0100, 1, 0, 0, 0)
    consulta += b"".join(bytes([len(p)]) + p.encode() for p in nombre.split(".")) + b"\0"
    consulta += struct.pack(">HH", 12, 1)  # tipo PTR, clase IN
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.settimeout(1)
        s.sendto(consulta, DNS_DOCKER)
        datos, _ = s.recvfrom(2048)
    rid, _, qd, an, _, _ = struct.unpack(">HHHHHH", datos[:12])
    if rid != ident or an == 0:
        return None
    pos = 12
    for _ in range(qd):  # saltar la pregunta
        _, pos = leer_nombre(datos, pos)
        pos += 4
    for _ in range(an):
        _, pos = leer_nombre(datos, pos)
        tipo, _, _, largo = struct.unpack(">HHIH", datos[pos:pos + 10])
        pos += 10
        if tipo == 12:
            return leer_nombre(datos, pos)[0]
        pos += largo
    return None


def main():
    ip = sys.argv[1] if len(sys.argv) > 1 else socket.gethostbyname(socket.gethostname())
    for _ in range(20):
        try:
            nombre = ptr(ip)
            if nombre:
                m = re.search(r"-(\d+)$", nombre.split(".")[0])
                if m:
                    print(m.group(1))
                    return 0
        except OSError:
            pass
        time.sleep(0.5)
    return 1


if __name__ == "__main__":
    sys.exit(main())
