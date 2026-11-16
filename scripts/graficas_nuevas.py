#!/usr/bin/env python3
"""Tabla y grafica de las pruebas nuevas (pruebas/resultados/make/).

- concurrencia500_*.json: ~500 usuarios simultaneos, backends iguales.
- heterogeneo_*.json:     backend1 con WORK_DELAY_MS=1000, el resto 200 ms.

Imprime una tabla Markdown y genera metricas/graficas/heterogeneo_algoritmos.png
(no sobrescribe ninguna grafica existente). Ejecutar desde la raiz del repo:
    python scripts/graficas_nuevas.py            # requiere matplotlib
"""
import glob
import json
import os
import re

DIR = os.path.join("pruebas", "resultados", "make")
SALIDA = os.path.join("metricas", "graficas", "heterogeneo_algoritmos.png")


def leer(ruta):
    a = json.load(open(ruta, encoding="utf-8"))["aggregate"]
    c, s = a["counters"], a["summaries"]
    rt = s.get("http.response_time", {})
    pet = c.get("http.requests", 0)
    ok = c.get("http.codes.200", 0)
    nombre = os.path.basename(ruta)
    return {
        "prueba": "Heterogénea (backend1 = 1000 ms)" if nombre.startswith("heterogeneo_")
                  else "Concurrencia (~500 simultáneos)",
        "algoritmo": re.search(r"(byrequests|bybusyness)", nombre).group(1),
        "peticiones": pet,
        "error_pct": 100 * (pet - ok) / pet if pet else 0.0,
        "rps": a.get("rates", {}).get("http.request_rate", 0),
        "media": rt.get("mean"), "p95": rt.get("p95"), "p99": rt.get("p99"),
        "sesion": s.get("vusers.session_length", {}).get("mean"),
        "reparto": {k[8:]: v for k, v in sorted(c.items()) if k.startswith("backend.")},
    }


def main():
    filas = [leer(f) for f in sorted(glob.glob(os.path.join(DIR, "concurrencia500_*.json")))
             + sorted(glob.glob(os.path.join(DIR, "heterogeneo_*.json")))]
    if not filas:
        raise SystemExit(f"No hay resultados en {DIR}")

    print("| Prueba | Algoritmo | Peticiones | Errores % | Pet./s | Media ms | p95 ms | p99 ms | Sesión media ms | Reparto (backend1 / 2 / 3) |")
    print("|---|---|---:|---:|---:|---:|---:|---:|---:|---|")
    for f in filas:
        rep = " / ".join(f"{v} ({100 * v / f['peticiones']:.0f} %)" for v in f["reparto"].values())
        print(f"| {f['prueba']} | {f['algoritmo']} | {f['peticiones']} | {f['error_pct']:.2f} | {f['rps']} "
              f"| {f['media']} | {f['p95']} | {f['p99']} | {f['sesion']} | {rep} |")

    het = [f for f in filas if f["prueba"].startswith("Heterogénea")]
    if len(het) < 2:
        return
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    if os.path.exists(SALIDA):
        raise SystemExit(f"{SALIDA} ya existe: no se sobrescribe (bórrala a mano si quieres regenerarla)")
    colores = {"byrequests": "#2563eb", "bybusyness": "#ea580c"}
    fig, (izq, der) = plt.subplots(1, 2, figsize=(11, 4.2))
    backends = list(het[0]["reparto"].keys())
    ancho = 0.38
    for j, f in enumerate(het):
        xs = [i + (j - 0.5) * ancho for i in range(len(backends))]
        vals = [f["reparto"].get(b, 0) for b in backends]
        barras = izq.bar(xs, vals, ancho, label=f["algoritmo"], color=colores[f["algoritmo"]])
        izq.bar_label(barras, fontsize=8)
    izq.set_xticks(range(len(backends)), [b + (" (1000 ms)" if b == "backend1" else " (200 ms)") for b in backends])
    izq.set_ylabel("Peticiones atendidas")
    izq.set_title("Reparto por backend")
    izq.legend()

    metricas = [("media", "Media"), ("p95", "p95"), ("p99", "p99")]
    for j, f in enumerate(het):
        xs = [i + (j - 0.5) * ancho for i in range(len(metricas))]
        barras = der.bar(xs, [f[k] for k, _ in metricas], ancho, label=f["algoritmo"], color=colores[f["algoritmo"]])
        der.bar_label(barras, fmt="%.0f", fontsize=8)
    der.set_xticks(range(len(metricas)), [t for _, t in metricas])
    der.set_ylabel("Latencia (ms)")
    der.set_title("Latencia")
    der.legend()

    fig.suptitle("Backends heterogéneos (backend1 = 1000 ms, resto = 200 ms), 3 backends, carga500", fontsize=11)
    fig.tight_layout()
    fig.savefig(SALIDA, dpi=120)
    print(f"\nGráfica: {SALIDA}")


if __name__ == "__main__":
    main()
