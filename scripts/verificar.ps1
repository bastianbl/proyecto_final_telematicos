<#
.SYNOPSIS
  Verifica que el sistema levantado (balanceador + backends) funciona. Integrante 6.
.DESCRIPTION
  No levanta ni detiene nada: el sistema debe estar arriba (scripts\compose.ps1 -Action Up).
  Comprueba contenedores, configuración de Apache, endpoints, reparto de peticiones y que
  los endpoints administrativos NO estén expuestos. Guarda el informe en evidencias\logs\.
  Código de salida: 0 si todo pasa, 1 si algo falla.
.EXAMPLE
  .\scripts\verificar.ps1
  .\scripts\verificar.ps1 -BackendCount 7 -Solicitudes 140
#>
[CmdletBinding()]
param(
    [ValidateSet(0, 3, 5, 7)][int]$BackendCount = 0,   # 0 = leer de BACKEND_COUNT / .env / 3
    [int]$Solicitudes = 0,                              # 0 = 10 por backend
    [switch]$SinGuardar
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comun.ps1')

$n = Resolve-BackendCount $BackendCount
$puerto = Get-Setting 'BALANCER_PORT' '8080'
$base = "http://127.0.0.1:$puerto"
if ($Solicitudes -le 0) { $Solicitudes = 10 * $n }
$script:fallos = 0

function Confirmar {
    param([bool]$Ok, [string]$Nombre, [string]$Detalle = '')
    if ($Ok) { Write-Log ("[ OK  ] {0} {1}" -f $Nombre, $Detalle) 'Green' }
    else { $script:fallos++; Write-Log ("[FALLO] {0} {1}" -f $Nombre, $Detalle) 'Red' }
}

function Finalizar {
    Write-Log ''
    if ($script:fallos -eq 0) { Write-Log 'RESULTADO: todas las verificaciones pasaron.' 'Green' }
    else { Write-Log "RESULTADO: fallaron $($script:fallos) verificación(es)." 'Red' }
    if (-not $SinGuardar) {
        $ruta = Join-Path $script:LogsDir ("verificacion_{0}b_{1}.txt" -f $n, (Get-Date -Format 'yyyyMMdd_HHmmss'))
        Save-Log $ruta
        Write-Host "Informe guardado en: $ruta"
    }
    if ($script:fallos -gt 0) { exit 1 } else { exit 0 }
}

Write-Log "=== Verificación del sistema  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" 'Cyan'
Write-Log "Escenario esperado: $n backends | URL: $base"
Write-Log ''

# 1. Docker y Compose
Write-Log '--- 1. Docker ---' 'Cyan'
$v = @(Invoke-Docker @('version', '--format', '{{.Server.Version}}'))
Confirmar ($script:DockerExit -eq 0) 'Docker responde' "($($v -join ' '))"
if ($script:DockerExit -ne 0) { Finalizar }
$null = @(Invoke-Docker (Get-ComposeArgs $n @('config', '--quiet')))
Confirmar ($script:DockerExit -eq 0) 'docker compose config es válido'

# 2. Contenedores
Write-Log ''
Write-Log '--- 2. Contenedores ---' 'Cyan'
$servicios = @('balanceador') + (1..$n | ForEach-Object { "backend$_" })
foreach ($s in $servicios) {
    $id = @(Invoke-Docker (Get-ComposeArgs $n @('ps', '-q', $s))) | Where-Object { $_ -match '^[0-9a-f]{12,}$' } | Select-Object -First 1
    if (-not $id) { Confirmar $false "Contenedor $s" '(no existe o no está iniciado)'; continue }
    $est = @(Invoke-Docker @('inspect', '-f', '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}sin-healthcheck{{end}}', $id))[0]
    $partes = $est -split '\|'
    $ok = ($partes[0] -eq 'running') -and (@('healthy', 'sin-healthcheck') -contains $partes[1])
    Confirmar $ok "Contenedor $s" "($est)"
}

# 3. Apache
Write-Log ''
Write-Log '--- 3. Configuración de Apache ---' 'Cyan'
$t = (@(Invoke-Docker (Get-ComposeArgs $n @('exec', '-T', 'balanceador', 'httpd', '-t'))) -join ' ')
Confirmar ($t -match 'Syntax OK') 'httpd -t' "($t)"

$mods = (@(Invoke-Docker (Get-ComposeArgs $n @('exec', '-T', 'balanceador', 'httpd', '-M'))) -join "`n")
foreach ($m in @('proxy_module', 'proxy_http_module', 'proxy_balancer_module', 'proxy_hcheck_module', 'lbmethod_byrequests_module', 'lbmethod_bybusyness_module')) {
    Confirmar ($mods -match "\b$m\b") "Módulo $m"
}

$conf = @(Invoke-Docker (Get-ComposeArgs $n @('exec', '-T', 'balanceador', 'cat', '/usr/local/apache2/conf/extra/balancer-members.conf')))
$miembros = @($conf | Where-Object { $_ -match 'BalancerMember' })
Confirmar ($miembros.Count -eq $n) 'Pool de Apache coincide con BACKEND_COUNT' "($($miembros.Count) miembros, esperados $n)"
$sinHc = @($miembros | Where-Object { $_ -notmatch 'hcuri=/health' })
Confirmar ($sinHc.Count -eq 0) 'Monitoreo activo (hcheck) en todos los miembros'
$metodo = 'desconocido'
foreach ($l in $conf) { if ($l -match 'lbmethod=(\w+)') { $metodo = $Matches[1] } }
Write-Log "       Método de balanceo activo: $metodo"

# 4. Endpoints
Write-Log ''
Write-Log '--- 4. Endpoints a través del balanceador ---' 'Cyan'
$h = Invoke-Req "$base/health"
Confirmar ($h.Ok -and $h.Status -eq 200 -and $h.Body -match '^ok backend[1-7]$') 'GET /health' "(HTTP $($h.Status), '$($h.Body)')"
$r = Invoke-Req "$base/"
Confirmar ($r.Ok -and $r.Body -match '^backend[1-7]$') 'GET / identifica al backend' "('$($r.Body)')"
$w = Invoke-Req "$base/work" 15
Confirmar ($w.Ok -and $w.Body -match '^backend[1-7]$') 'GET /work' "('$($w.Body)', $($w.Ms) ms)"

# 5. Reparto
Write-Log ''
Write-Log "--- 5. Reparto de $Solicitudes solicitudes secuenciales ---" 'Cyan'
$resp = New-Object System.Collections.Generic.List[string]
for ($i = 1; $i -le $Solicitudes; $i++) { $resp.Add((Invoke-Req "$base/" 10).Body) }
$cuenta = Get-Conteo $resp
Write-Log "       $(Format-Conteo $cuenta)"
$esperados = @(1..$n | ForEach-Object { "backend$_" })
$faltan = @($esperados | Where-Object { -not $cuenta.ContainsKey($_) })
Confirmar ($faltan.Count -eq 0) 'Todos los backends reciben tráfico' $(if ($faltan.Count) { "(sin tráfico: $($faltan -join ', '))" } else { '' })
$raros = @($cuenta.Keys | Where-Object { $esperados -notcontains $_ })
Confirmar ($raros.Count -eq 0) 'Sin errores ni respuestas inesperadas' $(if ($raros.Count) { "($($raros -join ', '))" } else { '' })
$valores = @($esperados | ForEach-Object { if ($cuenta.ContainsKey($_)) { $cuenta[$_] } else { 0 } })
$min = ($valores | Measure-Object -Minimum).Minimum
$max = ($valores | Measure-Object -Maximum).Maximum
Write-Log "       Mín/Máx por backend: $min / $max (informativo; es una prueba funcional, no de rendimiento)"

# 6. Endpoints administrativos
Write-Log ''
Write-Log '--- 6. Endpoints administrativos no expuestos ---' 'Cyan'
foreach ($ruta in @('/balancer-manager', '/server-status')) {
    $a = Invoke-Req "$base$ruta" 5
    Confirmar ($a.Status -eq 403) "Acceso restringido a $ruta" "(HTTP $($a.Status); se espera 403)"
}

Finalizar
