<#
.SYNOPSIS
  Reúne en una carpeta el estado del sistema, logs y estadísticas como evidencia. Integrante 6.
.DESCRIPTION
  Guarda en evidencias\logs\snapshot_<N>b_<fecha>\ : versión de Docker, estado de contenedores,
  configuración resuelta de Compose, consumo (docker stats), configuración y logs de Apache,
  logs de cada backend, información de Git y listado de pruebas\resultados.
  No modifica ni detiene nada. No incluye el archivo .env.
.EXAMPLE
  .\scripts\recolectar_evidencias.ps1
  .\scripts\recolectar_evidencias.ps1 -BackendCount 7 -Etiqueta despues_de_artillery
#>
[CmdletBinding()]
param(
    [ValidateSet(0, 3, 5, 7)][int]$BackendCount = 0,
    [string]$Etiqueta = '',
    [int]$LineasLog = 500
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comun.ps1')

$n = Resolve-BackendCount $BackendCount
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$nombre = "snapshot_${n}b_$ts"
if ($Etiqueta) { $nombre += '_' + ($Etiqueta -replace '[^\w\-]', '_') }
$dir = Join-Path $script:LogsDir $nombre
New-Item -ItemType Directory -Force $dir | Out-Null

function Guardar {
    param([string]$Archivo, [string[]]$Arguments)
    $salida = @(Invoke-Docker $Arguments)
    $salida | Out-File -FilePath (Join-Path $dir $Archivo) -Encoding utf8
    Write-Host ("  {0,-30} {1,5} líneas" -f $Archivo, $salida.Count)
}

Write-Host "Recolectando evidencias en: $dir" -ForegroundColor Cyan

$todosPerfiles = @('compose', '-f', $script:ComposeFile, '--profile', 'cinco', '--profile', 'siete', '--profile', 'artillery')

Guardar 'docker_version.txt' @('version')
Guardar 'compose_ps.txt' ($todosPerfiles + @('ps', '-a'))
Guardar 'compose_config.txt' (Get-ComposeArgs $n @('config'))
Guardar 'docker_stats.txt' @('stats', '--no-stream', '--format', 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}')

Guardar 'apache_httpd_t.txt' (Get-ComposeArgs $n @('exec', '-T', 'balanceador', 'httpd', '-t'))
Guardar 'apache_modulos.txt' (Get-ComposeArgs $n @('exec', '-T', 'balanceador', 'httpd', '-M'))
Guardar 'apache_miembros.txt' (Get-ComposeArgs $n @('exec', '-T', 'balanceador', 'cat', '/usr/local/apache2/conf/extra/balancer-members.conf'))
Guardar 'apache_logs.txt' (Get-ComposeArgs $n @('logs', '--no-color', '--tail', "$LineasLog", 'balanceador'))

foreach ($i in 1..$n) {
    Guardar "backend${i}_logs.txt" (Get-ComposeArgs $n @('logs', '--no-color', '--tail', '100', "backend$i"))
}

# Git (si está disponible)
try {
    $git = @()
    $git += "Rama:    $(& git -C $script:Raiz branch --show-current 2>&1)"
    $git += "Commit:  $(& git -C $script:Raiz log -1 --oneline 2>&1)"
    $git += 'Estado:'
    $git += @(& git -C $script:Raiz status --short 2>&1 | ForEach-Object { "  $_" })
    $git | Out-File -FilePath (Join-Path $dir 'git_info.txt') -Encoding utf8
    Write-Host ("  {0,-30} {1,5} líneas" -f 'git_info.txt', $git.Count)
}
catch { Write-Host '  (git no disponible: se omite git_info.txt)' -ForegroundColor Yellow }

# Resultados de Artillery ya generados
$res = Join-Path $script:Raiz 'pruebas\resultados'
if (Test-Path $res) {
    Get-ChildItem $res | Sort-Object Name | Select-Object Name, Length, LastWriteTime |
        Format-Table -AutoSize | Out-String | Out-File -FilePath (Join-Path $dir 'pruebas_resultados.txt') -Encoding utf8
    Write-Host ("  {0,-30}" -f 'pruebas_resultados.txt')
}

Write-Host ''
Write-Host "Listo. Revisa la carpeta antes de hacer commit (no debe contener datos privados)." -ForegroundColor Green
