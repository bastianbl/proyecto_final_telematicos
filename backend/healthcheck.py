"""HEALTHCHECK de Docker: sale con 0 si GET /health devuelve 200, si no con 1."""

import os
import sys
import urllib.request

port = os.environ.get("PORT", "80")
try:
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=2) as r:
        sys.exit(0 if r.status == 200 else 1)
except Exception:
    sys.exit(1)
