"""Comprobacion de salud: sale con 0 si GET <url> devuelve 200, si no con 1.

Uso:
  python3 healthcheck.py                               -> http://127.0.0.1:80/health (Apache)
  python3 healthcheck.py http://127.0.0.1:8000/health  -> app.py directo (lo usa el entrypoint)
"""

import sys
import urllib.request

url = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:80/health"
try:
    with urllib.request.urlopen(url, timeout=2) as r:
        sys.exit(0 if r.status == 200 else 1)
except Exception:
    sys.exit(1)
