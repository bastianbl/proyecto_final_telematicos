<#
.SYNOPSIS
  Ejecuta las cargas de Artillery (50, 100, 500 y 1000 usuarios) para una configuración dada.
.EXAMPLE
  .\scripts\correr_pruebas.ps1 -BackendCount 3 -BalancerMethod byrequests
  .\scripts\correr_pruebas.ps1 -BackendCount 5 -BalancerMethod bybusyness
  .\scripts\correr_pruebas.ps1 -BackendCount 3 -BalancerMethod byrequests -Escenario caida
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet(3, 5, 7)][int]$BackendCount,
    [Parameter(Mandatory)][ValidateSet('byrequests', 'bybusyness')][string]$BalancerMethod,
    [int[]]$Cargas = @(50, 100, 500, 1000),
    [ValidateSet('carga', 'caida')][string]$Escenario = 'carga',
    [int]$PausaSegundos = 15,
    [switch]$SinReiniciar
)

$ErrorActionPreference = 'Stop'
$raiz = Join-Path $PSScriptRoot '..'
$composeFile = Join-Path $raiz 'docker-compose.yml'
$resultados = Join-Path $raiz 'pruebas\resultados'
New-Item -ItemType Directory -Force $resultados | Out-Null

# Perfil de compose según el número de backends (igual que compose.ps1)
$perfil = @()
if ($BackendCount -eq 5) { $perfil = @('--profile', 'cinco') }
if ($BackendCount -eq 7) { $perfil = @('--profile', 'siete') }

# Reinicio limpio con la configuración pedida: Apache genera su pool al iniciar.
if (-not $SinReiniciar) {
    & (Join-Path $PSScriptRoot 'compose.ps1') -Action Restart -BackendCount $BackendCount -BalancerMethod $BalancerMethod
}

# Variables para que "compose run" vea la misma configuración y no recree el balanceador.
$env:BACKEND_COUNT = "$BackendCount"
$env:BALANCER_METHOD = $BalancerMethod
$puerto = if ($env:BALANCER_PORT) { $env:BALANCER_PORT } else { '8080' }

$lista = if ($Escenario -eq 'caida') { @('caida') } else { $Cargas | ForEach-Object { "carga$_" } }

foreach ($entorno in $lista) {
    # Calentamiento (no se mide) para no incluir el arranque en frío.
    1..20 | ForEach-Object {
        try { Invoke-WebRequest "http://localhost:$puerto/work" -UseBasicParsing | Out-Null } catch { }
    }

    $etiqueta = $entorno -replace '^carga(\d+)$', '$1u'
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $base = "${BalancerMethod}_${BackendCount}b_${etiqueta}_$ts"
    Write-Host ">>> $BalancerMethod | $BackendCount backends | $entorno" -ForegroundColor Cyan

    if ($entorno -eq 'caida') {
        Write-Host "Durante los 120 s: en otra terminal ejecuta  docker compose stop backend2  y luego  docker compose start backend2" -ForegroundColor Yellow
        Write-Host "(apunta las horas exactas de cada acción para el informe)" -ForegroundColor Yellow
    }

    $args = @('compose', '-f', $composeFile) + $perfil + @(
        '--profile', 'artillery', 'run', '--rm', '--no-deps', 'artillery',
        'run', '-e', $entorno, '/tests/carga.yml', '--output', "/results/$base.json")
    & docker @args 2>&1 | Tee-Object -FilePath (Join-Path $resultados "$base.txt")
    if ($LASTEXITCODE -ne 0) { throw "Artillery falló en $entorno (código $LASTEXITCODE)" }

    if ($entorno -ne $lista[-1]) { Start-Sleep -Seconds $PausaSegundos }
}

Write-Host "Listo. Genera el resumen con:  python scripts\resumen.py" -ForegroundColor Green
