# Makefile del proyecto: atajos para levantar, escalar, verificar y probar.
# Funciona en Linux, macOS y Windows con WSL o Git Bash (con "make" instalado).
# En Windows sin make, usa los scripts de PowerShell de scripts/ (ver README).
#
#   make demo                    TODO para la sustentación: levanta, verifica y dice qué abrir
#   make up                      levanta el escenario de .env + interfaz (http://localhost:8090)
#   make demo-escenarios         interfaz con balanceadores demo 3/5/7 seleccionables
#   make scale N=4               modo --scale: docker compose up --scale backend=4
#   make verificar               estado, /health, /server-status y reparto
#   make caida                   caída y recuperación de backend2
#   make estado ETIQUETA=antes   captura /balancer-manager y /server-status
#   make carga CARGA=carga100    Artillery con pruebas/carga.yml
#   make smoke                   Artillery con pruebas/artillery-smoke.yml
#   make concurrencia            Artillery con ~500 usuarios simultáneos
#   make ps | logs | down

SHELL := /bin/bash
-include .env

BACKEND_COUNT   ?= 3
BALANCER_METHOD ?= byrequests
BALANCER_PORT   ?= 8080
CARGA           ?= carga100
ETIQUETA        ?= manual

# Git Bash convierte los argumentos que empiezan por "/" (como /tests/carga.yml)
# en rutas de Windows; esto lo desactiva. En Linux y macOS no tiene efecto.
export MSYS_NO_PATHCONV := 1
export BACKEND_COUNT BALANCER_METHOD BALANCER_PORT

URL    := http://localhost:$(BALANCER_PORT)
DC     := docker compose
PERFIL := $(if $(filter 5,$(BACKEND_COUNT)),--profile cinco,$(if $(filter 7,$(BACKEND_COUNT)),--profile siete,))
TODOS  := --profile cinco --profile siete --profile artillery --profile scale --profile interfaz
N_PET   = $$(( $(or $(N),$(BACKEND_COUNT)) * 7 ))
FECHA   = $(shell date +%Y%m%d_%H%M%S)

.PHONY: help demo demo-escenarios up down ps logs verificar scale carga concurrencia smoke caida estado

help:
	@sed -n '2,16p' Makefile

# Escenario normal (backend1..N) + interfaz. Si había réplicas del modo
# --scale o balanceadores de demostración, se retiran.
up:
	-$(DC) --profile scale rm -sf backend
	-$(DC) -f docker-compose.yml -f interfaz/compose.interfaz.yml rm -sf balanceador3 balanceador5 balanceador7
	$(DC) $(PERFIL) --profile interfaz up -d --build --wait

# Recorrido completo para la sustentación (ver README, "Recorrido completo").
demo: up verificar
	@echo
	@echo "Sistema listo:"
	@echo "  Interfaz:          http://localhost:8090   (botón Principal)"
	@echo "  Balanceador:       $(URL)/"
	@echo "  Estado de Apache:  $(URL)/server-status"
	@echo "  Panel administrativo: restringido (HTTP 403)"
	@echo "Siguiente: make carga CARGA=carga100  (mírala en vivo en la interfaz)"

# Interfaz con balanceadores de demostración 3/5/7 (interfaz/compose.interfaz.yml).
demo-escenarios:
	$(DC) -f docker-compose.yml -f interfaz/compose.interfaz.yml up -d --build --wait
	@echo "Interfaz: http://localhost:8090  (botones Principal / demo 3 / demo 5 / demo 7)"

down:
	$(DC) $(TODOS) down --remove-orphans

ps:
	$(DC) $(TODOS) ps -a

logs:
	$(DC) $(TODOS) logs -f --tail 100

verificar:
	$(DC) $(TODOS) ps
	@curl -fsS "$(URL)/health" && echo
	@curl -fsS -o /dev/null -w "server-status:    HTTP %{http_code}\n" "$(URL)/server-status?auto"
	@codigo=$$(curl -s -o /dev/null -w '%{http_code}' "$(URL)/balancer-manager"); \
	echo "balancer-manager: HTTP $$codigo (esperado 403)"; \
	test "$$codigo" = "403"
	bash backend/probar.sh $(N_PET) "$(URL)/"

# Modo --scale (requisito literal del enunciado). Apache lee su lista de
# miembros al arrancar, así que tras escalar se recrea el balanceador con un
# BalancerMember por réplica. Limitación: esa recreación corta el servicio ~1-3 s.
scale:
	@test -n "$(N)" || { echo "Uso: make scale N=4   (1 a 20)"; exit 1; }
	-$(DC) $(TODOS) stop backend1 backend2 backend3 backend4 backend5 backend6 backend7
	$(DC) --profile scale up -d --build --wait --no-deps --scale backend=$(N) backend
	BACKEND_MODE=scale BACKEND_COUNT=$(N) $(DC) up -d --build --wait --no-deps --force-recreate balanceador
	@echo "Modo --scale con $(N) réplicas. Comprueba: make verificar N=$(N)"

# Resultados en pruebas/resultados/make/: no se mezclan con los publicados
# (scripts/resumen.py solo lee pruebas/resultados/*.json).
carga:
	@mkdir -p pruebas/resultados/make
	$(DC) --profile artillery run --rm --no-deps artillery run -e $(CARGA) /tests/carga.yml \
		--output /results/make/$(BALANCER_METHOD)_$(or $(N),$(BACKEND_COUNT))b_$(CARGA)_$(FECHA).json

# ~500 usuarios simultáneos durante ~60 s (pruebas/concurrencia.yml).
concurrencia:
	@mkdir -p pruebas/resultados/make
	$(DC) --profile artillery run --rm --no-deps artillery run /tests/concurrencia.yml \
		--output /results/make/concurrencia500_$(BALANCER_METHOD)_$(or $(N),$(BACKEND_COUNT))b_$(FECHA).json

# Sin --output: no sobrescribe pruebas/resultados/artillery-report.json.
smoke:
	$(DC) --profile artillery run --rm artillery run /tests/artillery-smoke.yml

caida:
	bash backend/probar.sh $(N_PET) "$(URL)/"
	$(DC) $(PERFIL) stop backend2
	sleep 8
	bash backend/probar.sh $(N_PET) "$(URL)/"
	$(DC) $(PERFIL) start backend2
	sleep 8
	bash backend/probar.sh $(N_PET) "$(URL)/"

estado:
	@set -e; d="evidencias/logs/estado_$(ETIQUETA)_$(FECHA)"; mkdir -p "$$d"; \
	curl -fsS "$(URL)/server-status?auto" -o "$$d/server-status.txt"; \
	curl -fsS "$(URL)/server-status" -o "$$d/server-status.html"; \
	codigo=$$(curl -s -o /dev/null -w '%{http_code}' "$(URL)/balancer-manager"); \
	echo "balancer-manager: HTTP $$codigo (esperado 403)"; \
	test "$$codigo" = "403"; \
	echo "Captura guardada en $$d"
