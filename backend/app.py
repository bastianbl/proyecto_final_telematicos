"""Backend HTTP del proyecto (integrante 2).

Solo usa la biblioteca estandar de Python: no hay dependencias que instalar.

Endpoints del contrato (su formato NO cambia: lo usan verificar.ps1 y Artillery):
  GET /        -> "backendN\n"  (texto plano, identifica el servidor)
  GET /health  -> 200 "ok backendN\n"  (lo consultan Apache y Docker)
  GET /work    -> simula carga y luego responde "backendN\n"

Endpoints de observacion (JSON, los usa la interfaz grafica):
  GET /info    -> identidad del contenedor y configuracion de /work
  GET /metrics -> contadores: peticiones por ruta y codigo, activas, pico, tiempos de /work

Variables de entorno:
  BACKEND_ID     (obligatoria) numero del backend: 1..7
  PORT           puerto interno, por defecto 80 (contrato con el balanceador)
  WORK_DELAY_MS  espera (I/O simulada) de /work en ms, por defecto 200
  WORK_CPU_MS    calculo activo (CPU) de /work en ms, por defecto 0
  WORK_MAX_MS    tope para los valores pasados por query string, por defecto 10000
"""

import json
import os
import platform
import signal
import socket
import sys
import threading
import time
from datetime import datetime, timezone
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

HOSTNAME = socket.gethostname()  # en Docker es el ID corto del contenedor
try:
    IP = socket.gethostbyname(HOSTNAME)
except OSError:
    IP = "desconocida"
STARTED = time.time()
STARTED_ISO = datetime.now(timezone.utc).isoformat(timespec="seconds")

# Rutas conocidas. Cualquier otra se cuenta como "otros": asi una URL
# inventada no puede crear claves nuevas sin limite en el diccionario.
ROUTES = ("/", "/health", "/work", "/info", "/metrics")
# Trafico de aplicacion: el que reparte el balanceador entre usuarios.
# /health, /info y /metrics son monitoreo y no cuentan como "activas",
# para que la observacion no altere lo que se observa.
APP_ROUTES = ("/", "/work")


class Stats:
    """Contadores compartidos entre hilos (uno por peticion), protegidos con un Lock."""

    def __init__(self):
        self.lock = threading.Lock()
        self.total = 0
        self.by_path = {r: 0 for r in ROUTES}
        self.by_path["otros"] = 0
        self.by_status = {}
        self.active = 0
        self.peak_active = 0
        self.work_count = 0
        self.work_total_ms = 0.0
        self.work_max_ms = 0.0

    def begin(self, route):
        with self.lock:
            self.total += 1
            self.by_path[route] += 1
            if route in APP_ROUTES:
                self.active += 1
                self.peak_active = max(self.peak_active, self.active)

    def end(self, route, status, elapsed_ms):
        with self.lock:
            key = str(status)
            self.by_status[key] = self.by_status.get(key, 0) + 1
            if route in APP_ROUTES:
                self.active -= 1
            if route == "/work" and status == 200:
                self.work_count += 1
                self.work_total_ms += elapsed_ms
                self.work_max_ms = max(self.work_max_ms, elapsed_ms)

    def snapshot(self):
        with self.lock:
            avg = self.work_total_ms / self.work_count if self.work_count else 0.0
            return {
                "backend": NAME,
                "uptime_s": round(time.time() - STARTED, 1),
                "requests_total": self.total,
                "app_requests": self.by_path["/"] + self.by_path["/work"],
                "by_path": dict(self.by_path),
                "by_status": dict(self.by_status),
                "active": self.active,
                "peak_active": self.peak_active,
                "work": {
                    "count": self.work_count,
                    "avg_ms": round(avg, 1),
                    "max_ms": round(self.work_max_ms, 1),
                },
            }


STATS = Stats()


def info():
    return {
        "backend": NAME,
        "id": BACKEND_ID,
        "hostname": HOSTNAME,
        "ip": IP,
        "port": PORT,
        "pid": os.getpid(),
        "python": platform.python_version(),
        "started_at": STARTED_ISO,
        "uptime_s": round(time.time() - STARTED, 1),
        "work_config": {
            "delay_ms": WORK_DELAY_MS,
            "cpu_ms": WORK_CPU_MS,
            "max_ms": WORK_MAX_MS,
        },
    }


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
    server_version = "backend-telematicos/1.1"
    protocol_version = "HTTP/1.1"  # keep-alive con Apache

    def send_body(self, status, data, content_type):
        self.status_sent = status
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("X-Backend-ID", BACKEND_ID)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def send_text(self, status, body):
        self.send_body(status, body.encode(), "text/plain; charset=utf-8")

    def send_json(self, status, obj):
        data = json.dumps(obj, ensure_ascii=False).encode()
        self.send_body(status, data, "application/json; charset=utf-8")

    def do_GET(self):
        url = urlsplit(self.path)
        route = url.path if url.path in ROUTES else "otros"
        self.status_sent = 500  # si algo falla antes de responder
        t0 = time.perf_counter()
        STATS.begin(route)
        try:
            self.dispatch(route, url)
        finally:
            STATS.end(route, self.status_sent, (time.perf_counter() - t0) * 1000)

    do_HEAD = do_GET

    def dispatch(self, route, url):
        if route == "/health":
            self.send_text(200, f"ok {NAME}\n")
        elif route == "/work":
            q = parse_qs(url.query)
            delay = query_ms(q, "delay_ms", WORK_DELAY_MS)
            cpu = query_ms(q, "cpu_ms", WORK_CPU_MS)
            if cpu:
                burn_cpu(cpu)
            if delay:
                time.sleep(delay / 1000)
            self.send_text(200, f"{NAME}\n")
        elif route == "/":
            self.send_text(200, f"{NAME}\n")
        elif route == "/info":
            self.send_json(200, info())
        elif route == "/metrics":
            self.send_json(200, STATS.snapshot())
        else:
            self.send_text(404, f"not found ({NAME})\n")

    def log_message(self, fmt, *args):
        # /health, /info y /metrics se consultan cada pocos segundos
        # (Apache, Docker y la interfaz): no llenar el log con ellos.
        path = urlsplit(self.path).path
        if path not in ("/health", "/info", "/metrics"):
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
