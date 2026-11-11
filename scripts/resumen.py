#!/usr/bin/env python3
"""Convierte los JSON de Artillery de pruebas/resultados/ en resumen.csv (para el integrante 5; separador ";" y coma decimal, para abrir directo en Excel en español).
Ejecutar desde la raíz del repo:  python scripts/resumen.py"""
import csv, glob, json, os, re

DIR = os.path.join("pruebas", "resultados")
filas = []
for f in sorted(glob.glob(os.path.join(DIR, "*.json"))):
    m = re.match(r"(.+?)_(\d+)b_(\d+u|caida)_(\d+_\d+)\.json$", os.path.basename(f))
    if not m:
        continue  # ignora p. ej. artillery-report.json del smoke test
    algo, nb, carga, ts = m.groups()
    agg = json.load(open(f, encoding="utf-8"))["aggregate"]
    c, s = agg.get("counters", {}), agg.get("summaries", {})
    rt = s.get("http.response_time", {})
    total = c.get("http.requests", 0)
    ok = c.get("http.codes.200", 0)
    err = total - ok
    reparto = " ".join(f"{k.split('.', 1)[1]}={v}" for k, v in sorted(c.items()) if k.startswith("backend."))
    filas.append({
        "algoritmo": algo, "backends": nb, "carga": carga, "ejecucion": ts,
        "peticiones": total, "http_200": ok, "errores": err,
        "tasa_error_%": round(100 * err / total, 2) if total else "",
        "vusers_fallidos": c.get("vusers.failed", 0),
        "rps_medio": agg.get("rates", {}).get("http.request_rate", ""),
        "lat_min_ms": rt.get("min", ""), "lat_media_ms": rt.get("mean", ""),
        "lat_p50_ms": rt.get("median", ""), "lat_p95_ms": rt.get("p95", ""),
        "lat_p99_ms": rt.get("p99", ""), "lat_max_ms": rt.get("max", ""),
        "reparto_backends": reparto,
    })

def coma(v):
    # Excel en español espera coma decimal (202,4) y separador de columnas ";"
    return str(v).replace(".", ",") if isinstance(v, float) else v

if filas:
    filas = [{k: coma(v) for k, v in fila.items()} for fila in filas]
    with open(os.path.join(DIR, "resumen.csv"), "w", newline="", encoding="utf-8-sig") as out:
        w = csv.DictWriter(out, fieldnames=filas[0].keys(), delimiter=";")
        w.writeheader(); w.writerows(filas)
    print(f"resumen.csv generado con {len(filas)} ejecuciones")
else:
    print("No hay resultados con el formato esperado en", DIR)
