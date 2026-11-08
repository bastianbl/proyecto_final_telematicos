#!/usr/bin/env bash
# Equivalente Linux de balanceador/probar.ps1.
# Uso: ./backend/probar.sh [peticiones] [url]
set -euo pipefail
N="${1:-21}"
URL="${2:-http://localhost:8080/}"

ok=0; fail=0; out=""
for _ in $(seq "$N"); do
    if r=$(curl -fsS --max-time 10 "$URL"); then
        out+="$r"$'\n'; ok=$((ok + 1))
    else
        fail=$((fail + 1))
    fi
done
echo "Peticiones: $N  correctas: $ok  fallidas: $fail"
printf '%s' "$out" | sort -V | uniq -c
