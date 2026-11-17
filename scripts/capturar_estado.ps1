<#
.SYNOPSIS
  Guarda una captura del endpoint de estado del balanceador como evidencia.
.DESCRIPTION
  Descarga /balancer-manager (estado de cada BalancerMember) y /server-status
  (peticiones, tráfico, workers de Apache) en evidencias\logs\estado_<etiqueta>_<fecha>\.
  Úsalo antes y después de una prueba de carga para comparar. Solo lee; no cambia nada.
  Equivalente en Linux/macOS:  make estado ETIQUETA=antes
.EXAMPLE
  .\scripts\capturar_estado.ps1 -Etiqueta antes
  .\scripts\correr_pruebas.ps1 -BackendCount 3 -BalancerMethod byrequests -Cargas 100
  .\scripts\capturar_estado.ps1 -Etiqueta despues
#>
[CmdletBinding()]
param([string]$Etiqueta = 'manual')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comun.ps1')

$puerto = Get-Setting 'BALANCER_PORT' '8080'
$base = "http://127.0.0.1:$puerto"
$nombre = "estado_{0}_{1}" -f ($Etiqueta -replace '[^\w\-]', '_'), (Get-Date -Format 'yyyyMMdd_HHmmss')
$dir = Join-Path $script:LogsDir $nombre
New-Item -ItemType Directory -Force $dir | Out-Null

$fallos = 0
foreach ($p in @(
        @('/server-status?auto', 'server-status.txt'),
        @('/server-status', 'server-status.html'))) {
    try {
        Invoke-WebRequest -Uri "$base$($p[0])" -UseBasicParsing -TimeoutSec 10 -OutFile (Join-Path $dir $p[1])
        Write-Host ("  OK   {0,-22} -> {1}" -f $p[0], $p[1]) -ForegroundColor Green
    }
    catch {
        $fallos++
        Write-Host ("  FALLO {0}: {1}" -f $p[0], $_.Exception.Message) -ForegroundColor Red
    }
}
# Comprobar que el panel administrativo no sea accesible desde el host.
try {
    $respuesta = Invoke-WebRequest -Uri "$base/balancer-manager" -UseBasicParsing -TimeoutSec 10
    $fallos++
    Write-Host "  FALLO /balancer-manager: HTTP $($respuesta.StatusCode); se esperaba 403" -ForegroundColor Red
}
catch {
    $codigo = 0
    if ($_.Exception.Response) {
        $codigo = [int]$_.Exception.Response.StatusCode
    }

    if ($codigo -eq 403) {
        Write-Host "  OK   /balancer-manager restringido (HTTP 403)" -ForegroundColor Green
    }
    else {
        $fallos++
        Write-Host "  FALLO /balancer-manager: HTTP $codigo; se esperaba 403" -ForegroundColor Red
    }
}
Write-Host "Captura guardada en: $dir"
if ($fallos) { exit 1 } else { exit 0 }
