"""Backend HTTP del proyecto (integrante 2).

Solo usa la biblioteca estandar de Python: no hay dependencias que instalar.

Endpoints:
  GET /        -> "backendN\n"  (texto plano, identifica el servidor)
  GET /health  -> 200 "ok backendN\n"  (lo consultan Apache y Docker)
  GET /work    -> simula carga y luego responde "backendN\n"

Variables de entorno:
  BACKEND_ID     (obligatoria) numero del backend: 1..7
  PORT           puerto interno, por defecto 80 (contrato con el balanceador)
  WORK_DELAY_MS  espera (I/O simulada) de /work en ms, por defecto 200
  WORK_CPU_MS    calculo activo (CPU) de /work en ms, por defecto 0
  WORK_MAX_MS    tope para los valores pasados por query string, por defecto 10000
"""

import os
import signal
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit


def env_int(name, default):
    raw = os.environ.get(name, str(default)).strip()
    try:
        value = int(raw)
    except ValueError:
        sys.exit(f"ERROR: {name} debe ser un entero (actual: {raw!r})")
    if value < 0:
        sys.exit(f"ERROR: {name} no puede ser negativo (actual: {value})")
    return value


BACKEND_ID = os.environ.get("BACKEND_ID", "").strip()
if not BACKEND_ID:
    sys.exit("ERROR: falta la variable de entorno BACKEND_ID")

NAME = f"backend{BACKEND_ID}"
PORT = env_int("PORT", 80)
WORK_DELAY_MS = env_int("WORK_DELAY_MS", 200)
WORK_CPU_MS = env_int("WORK_CPU_MS", 0)
WORK_MAX_MS = env_int("WORK_MAX_MS", 10000)


def burn_cpu(ms):
    """Ocupa la CPU durante `ms` milisegundos haciendo calculo real."""
    end = time.perf_counter() + ms / 1000
    x = 0
    while time.perf_counter() < end:
        for i in range(1000):
            x += i * i
    return x


def query_ms(query, key, default):
    """Permite sobrescribir el valor por peticion: /work?delay_ms=500&cpu_ms=50."""
    try:
        value = int(query.get(key, [default])[0])
    except ValueError:
        return default
    return max(0, min(value, WORK_MAX_MS))


class Handler(BaseHTTPRequestHandler):
    server_version = "backend-telematicos/1.0"
    protocol_version = "HTTP/1.1"  # keep-alive con Apache

    def send_text(self, status, body):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("X-Backend-ID", BACKEND_ID)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def do_GET(self):
        url = urlsplit(self.path)
        if url.path == "/health":
            self.send_text(200, f"ok {NAME}\n")
        elif url.path == "/work":
            q = parse_qs(url.query)
            delay = query_ms(q, "delay_ms", WORK_DELAY_MS)
            cpu = query_ms(q, "cpu_ms", WORK_CPU_MS)
            if cpu:
                burn_cpu(cpu)
            if delay:
                time.sleep(delay / 1000)
            self.send_text(200, f"{NAME}\n")
        elif url.path == "/":
            self.send_text(200, f"{NAME}\n")
        else:
            self.send_text(404, f"not found ({NAME})\n")

    do_HEAD = do_GET

    def log_message(self, fmt, *args):
        # /health se consulta cada 2-3 s (Apache + Docker): no llenar el log.
        if not self.path.startswith("/health"):
            sys.stdout.write(f"[{NAME}] {self.address_string()} {fmt % args}\n")
            sys.stdout.flush()


def main():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.daemon_threads = True

    # Como PID 1 del contenedor, Python no termina con SIGTERM salvo que
    # instalemos un manejador. Sin esto, `docker stop` esperaria 10 s y
    # luego mataria el proceso con SIGKILL.
    def stop(signum, _frame):
        print(f"[{NAME}] senal {signum} recibida, cerrando", flush=True)
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    print(
        f"[{NAME}] escuchando en :{PORT} "
        f"(WORK_DELAY_MS={WORK_DELAY_MS}, WORK_CPU_MS={WORK_CPU_MS})",
        flush=True,
    )
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
