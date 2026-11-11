#!/usr/bin/env python3
"""Integrante 5: lee pruebas/resultados/resumen.csv y genera tablas y graficas en metricas/.
Ejecutar desde la raiz del repo:  python3 scripts/generar_metricas.py
Solo usa datos reales del CSV; no inventa ni estima nada."""
import csv, os, re
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ENTRADA = os.path.join("pruebas", "resultados", "resumen.csv")
DATOS, GRAF = os.path.join("metricas", "datos"), os.path.join("metricas", "graficas")
os.makedirs(DATOS, exist_ok=True); os.makedirs(GRAF, exist_ok=True)

def num(v):
    return float(str(v).replace(",", ".")) if str(v).strip() != "" else None

filas = []
with open(ENTRADA, encoding="utf-8-sig", newline="") as f:
    for r in csv.DictReader(f, delimiter=";"):
        if not r["carga"].endswith("u"):
            continue  # ignora el escenario de caida
        rep = [int(x) for x in re.findall(r"=(\d+)", r["reparto_backends"])]
        media = sum(rep) / len(rep)
        filas.append({
            "algoritmo": r["algoritmo"], "backends": int(r["backends"]),
            "usuarios": int(r["carga"][:-1]), "peticiones": int(r["peticiones"]),
            "errores": int(r["errores"]), "tasa_error_pct": num(r["tasa_error_%"]),
            "rps": num(r["rps_medio"]), "lat_media": num(r["lat_media_ms"]),
            "p50": num(r["lat_p50_ms"]), "p95": num(r["lat_p95_ms"]),
            "p99": num(r["lat_p99_ms"]), "lat_min": num(r["lat_min_ms"]),
            "lat_max": num(r["lat_max_ms"]),
            "desv_reparto_pct": round(100 * (max(rep) - min(rep)) / media, 2),
            "sospechosa": "SI" if num(r["lat_min_ms"]) < 0 else "",
        })
filas.sort(key=lambda x: (x["algoritmo"], x["backends"], x["usuarios"]))

# CSV limpio (punto decimal, UTF-8) para graficar o importar
with open(os.path.join(DATOS, "metricas_limpias.csv"), "w", newline="", encoding="utf-8") as out:
    w = csv.DictWriter(out, fieldnames=filas[0].keys()); w.writeheader(); w.writerows(filas)

# Tablas en Markdown (una por numero de backends) listas para el informe/README
ALGS, NB, US = ["byrequests", "bybusyness"], [3, 5, 7], [50, 100, 500, 1000]
with open(os.path.join(DATOS, "tablas.md"), "w", encoding="utf-8") as md:
    for nb in NB:
        md.write(f"\n### {nb} backends\n\n| Algoritmo | Usuarios | Peticiones | Errores | Tasa error % | RPS | Media ms | p95 ms | p99 ms | Desv. reparto % | Nota |\n|---|---|---|---|---|---|---|---|---|---|---|\n")
        for x in filas:
            if x["backends"] == nb:
                nota = "min<0: medicion sospechosa" if x["sospechosa"] else ""
                md.write(f"| {x['algoritmo']} | {x['usuarios']} | {x['peticiones']} | {x['errores']} | {x['tasa_error_pct']} | {x['rps']} | {x['lat_media']} | {x['p95']} | {x['p99']} | {x['desv_reparto_pct']} | {nota} |\n")

def sel(alg, nb, campo):
    return [next(x[campo] for x in filas if x["algoritmo"] == alg and x["backends"] == nb and x["usuarios"] == u) for u in US]

def lineas(campo, titulo, ylabel, archivo):
    fig, ejes = plt.subplots(1, 3, figsize=(15, 4.2), sharey=True)
    for ax, nb in zip(ejes, NB):
        for alg in ALGS:
            ax.plot(US, sel(alg, nb, campo), marker="o", label=alg)
        ax.set_title(f"{nb} backends"); ax.set_xlabel("Usuarios virtuales"); ax.set_xscale("log"); ax.set_xticks(US); ax.set_xticklabels(US); ax.grid(alpha=.3)
    ejes[0].set_ylabel(ylabel); ejes[0].legend(); fig.suptitle(titulo); fig.tight_layout()
    fig.savefig(os.path.join(GRAF, archivo), dpi=150); plt.close(fig)

lineas("p95", "Latencia p95 vs usuarios", "ms", "latencia_p95.png")
lineas("p99", "Latencia p99 vs usuarios", "ms", "latencia_p99.png")
lineas("rps", "Throughput (peticiones/s) vs usuarios", "peticiones/s", "throughput_rps.png")

# p95 y p99 a 1000 usuarios segun numero de backends
fig, ejes = plt.subplots(1, 2, figsize=(10, 4))
for ax, campo in zip(ejes, ["p95", "p99"]):
    for alg in ALGS:
        ax.plot(NB, [sel(alg, nb, campo)[-1] for nb in NB], marker="o", label=alg)
    ax.set_title(f"{campo} con 1000 usuarios"); ax.set_xlabel("Numero de backends"); ax.set_xticks(NB); ax.set_ylabel("ms"); ax.grid(alpha=.3)
ejes[0].legend(); fig.tight_layout(); fig.savefig(os.path.join(GRAF, "backends_vs_latencia_1000u.png"), dpi=150); plt.close(fig)

# Desviacion del reparto de peticiones entre backends (0 % = reparto perfecto)
fig, ax = plt.subplots(figsize=(9, 4))
ancho = 0.38
x0 = range(len(NB) * len(US))
etq = [f"{nb}b/{u}u" for nb in NB for u in US]
for i, alg in enumerate(ALGS):
    vals = [next(x["desv_reparto_pct"] for x in filas if x["algoritmo"] == alg and x["backends"] == nb and x["usuarios"] == u) for nb in NB for u in US]
    ax.bar([p + i * ancho for p in x0], vals, ancho, label=alg)
ax.set_xticks([p + ancho / 2 for p in x0]); ax.set_xticklabels(etq, rotation=60); ax.set_ylabel("(max-min)/media %"); ax.set_title("Desbalance de reparto entre backends"); ax.legend(); fig.tight_layout()
fig.savefig(os.path.join(GRAF, "desbalance_reparto.png"), dpi=150); plt.close(fig)

print(f"{len(filas)} ejecuciones procesadas. Salidas en metricas/datos y metricas/graficas")
print("Totales: errores =", sum(x["errores"] for x in filas), "| ejecuciones sospechosas:", [(x['algoritmo'], x['backends'], x['usuarios']) for x in filas if x['sospechosa']])
