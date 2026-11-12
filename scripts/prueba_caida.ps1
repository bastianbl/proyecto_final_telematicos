<#
.SYNOPSIS
  Prueba de caída y recuperación de un backend bajo tráfico continuo. Integrante 6.
.DESCRIPTION
  Con el sistema ya levantado:
    1. Mide el reparto inicial.
    2. Envía peticiones secuenciales continuas al balanceador durante -Duracion segundos.
    3. En el segundo -SegundoCaida detiene el backend elegido; en -SegundoRecuperacion lo vuelve a iniciar.
    4. Mide errores, cuándo deja de recibir tráfico y cuándo vuelve a recibirlo (sin reiniciar Apache).
    5. Guarda CSV, resumen y logs de Apache/backend en evidencias\logs\.
  Todos los números salen de la medición real de esta ejecución; no se inventa nada.
  Es una prueba secuencial (≈10 peticiones/s): NO sustituye a Artillery ni sirve para p95/p99.
  Para la caída bajo carga concurrente use:  .\scripts\correr_pruebas.ps1 -Escenario caida ...
.EXAMPLE
  .\scripts\prueba_caida.ps1
  .\scripts\prueba_caida.ps1 -BackendCount 7 -Backend 4 -Duracion 60 -SegundoCaida 15 -SegundoRecuperacion 35
#>
[CmdletBinding()]
param(
    [ValidateSet(0, 3, 5, 7)][int]$BackendCount = 0,
    [ValidateRange(1, 7)][int]$Backend = 2,
    [ValidateRange(30, 600)][int]$Duracion = 45,
    [int]$SegundoCaida = 10,
    [int]$SegundoRecuperacion = 25,
    [ValidateRange(0, 5000)][int]$IntervaloMs = 100,
    [string]$Ruta = '/'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comun.ps1')

$n = Resolve-BackendCount $BackendCount
if ($Backend -gt $n) { throw "-Backend $Backend no existe en un escenario de $n backends." }
if (-not ($SegundoCaida -ge 3 -and $SegundoCaida -lt $SegundoRecuperacion -and $SegundoRecuperacion -le ($Duracion - 15))) {
    throw 'Tiempos incoherentes: se requiere 3 <= SegundoCaida < SegundoRecuperacion <= Duracion-15 (15 s para observar la recuperación).'
}

$puerto = Get-Setting 'BALANCER_PORT' '8080'
$base = "http://127.0.0.1:$puerto"
$url = "$base$Ruta"
$victima = "backend$Backend"
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'

# --- Comprobaciones previas ---
$sano = Invoke-Req "$base/health" 5
if (-not $sano.Ok) { throw "El balanceador no responde en $base. Levanta el sistema primero:  .\scripts\compose.ps1 -Action Up -BackendCount $n" }
$idVictima = @(Invoke-Docker (Get-ComposeArgs $n @('ps', '-q', $victima))) | Where-Object { $_ -match '^[0-9a-f]{12,}$' } | Select-Object -First 1
if (-not $idVictima) { throw "El contenedor $victima no está en ejecución; no se puede probar su caída." }

$metodo = Get-MetodoActivo $n
$nombreBase = "caida_${victima}_${n}b_${metodo}_$ts"
$reloj = [System.Diagnostics.Stopwatch]::StartNew()

Write-Log "=== Prueba de caída y recuperación  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" 'Cyan'
Write-Log "Backends: $n | Método: $metodo | Backend a detener: $victima | Ruta: $Ruta"
Write-Log "Duración: ${Duracion}s | Parada en t=${SegundoCaida}s | Inicio en t=${SegundoRecuperacion}s | Intervalo: ${IntervaloMs} ms"
Write-Log ''

# --- Fase 0: reparto inicial ---
$ini = New-Object System.Collections.Generic.List[string]
for ($i = 1; $i -le (10 * $n); $i++) { $ini.Add((Invoke-Req $url 10).Body) }
Write-Log "Reparto inicial ($(10 * $n) peticiones): $(Format-Conteo (Get-Conteo $ini))"
Write-Log ''
Write-Log '--- Tráfico continuo ---' 'Cyan'

# --- Fase 1: tráfico continuo con parada y arranque programados ---
$filas = New-Object System.Collections.Generic.List[object]
$pStop = $null; $pStart = $null
$tStop = $null; $tStart = $null
$horaStop = ''; $horaStart = ''
$k = 0; $ultimoAviso = -1
$loop = [System.Diagnostics.Stopwatch]::StartNew()

try {
    while ($loop.Elapsed.TotalSeconds -lt $Duracion) {
        $t = $loop.Elapsed.TotalSeconds

        if ($null -eq $tStop -and $t -ge $SegundoCaida) {
            $tStop = $t; $horaStop = (Get-Date).ToString('HH:mm:ss.fff')
            $pStop = Start-DockerSegundoPlano (Get-ComposeArgs $n @('stop', $victima))
            Write-Log ("[t={0,6:N1}s {1}] >>> ORDEN: docker compose stop {2}" -f $t, $horaStop, $victima) 'Yellow'
        }
        if ($null -eq $tStart -and $t -ge $SegundoRecuperacion) {
            $tStart = $t; $horaStart = (Get-Date).ToString('HH:mm:ss.fff')
            $pStart = Start-DockerSegundoPlano (Get-ComposeArgs $n @('start', $victima))
            Write-Log ("[t={0,6:N1}s {1}] >>> ORDEN: docker compose start {2}" -f $t, $horaStart, $victima) 'Yellow'
        }

        $k++
        $r = Invoke-Req $url 5
        $filas.Add([pscustomobject]@{
                N = $k; T = [math]::Round($t, 3); Hora = (Get-Date).ToString('HH:mm:ss.fff')
                Backend = $r.Body; Estado = $r.Status; Ok = $r.Ok; Ms = $r.Ms
            })

        $seg = [int][math]::Floor($t)
        if ($seg -ne $ultimoAviso -and ($seg % 5) -eq 0) {
            $ultimoAviso = $seg
            $errAhora = @($filas | Where-Object { -not $_.Ok }).Count
            Write-Host ("  t={0,3}s  peticiones={1,4}  errores={2}" -f $seg, $k, $errAhora)
        }

        $espera = $IntervaloMs - [int]$r.Ms
        if ($espera -gt 0) { Start-Sleep -Milliseconds $espera }
    }
}
finally {
    # Seguridad: si se interrumpe el script (Ctrl+C), no dejar el backend caído.
    $sigue = @(Invoke-Docker (Get-ComposeArgs $n @('ps', '-q', $victima))) | Where-Object { $_ -match '^[0-9a-f]{12,}$' } | Select-Object -First 1
    if (-not $sigue) {
        Write-Host "Seguridad: $victima estaba detenido, se vuelve a iniciar..." -ForegroundColor Yellow
        $null = @(Invoke-Docker (Get-ComposeArgs $n @('start', $victima)))
    }
}

foreach ($p in @($pStop, $pStart)) { if ($p) { $null = $p.WaitForExit(30000) } }
if ($null -eq $tStop) { $tStop = $SegundoCaida }
if ($null -eq $tStart) { $tStart = $SegundoRecuperacion }

# --- Análisis (solo con datos medidos) ---
$ok = @($filas | Where-Object { $_.Ok })
$err = @($filas | Where-Object { -not $_.Ok })
$antes = @($filas | Where-Object { $_.T -lt $tStop })
$durante = @($filas | Where-Object { $_.T -ge $tStop -and $_.T -lt $tStart })
$despues = @($filas | Where-Object { $_.T -ge $tStart })

Write-Log ''
Write-Log '--- Resultados ---' 'Cyan'
Write-Log ("Peticiones: {0} | Correctas: {1} | Con error: {2} | Éxito: {3:N2} %" -f $filas.Count, $ok.Count, $err.Count, (100.0 * $ok.Count / [math]::Max(1, $filas.Count)))
if ($ok.Count) {
    $lat = $ok | Measure-Object -Property Ms -Average -Maximum
    Write-Log ("Latencia (peticiones correctas): media {0:N1} ms | máxima {1:N1} ms" -f $lat.Average, $lat.Maximum)
}

foreach ($fase in @(@('Antes de la caída', $antes), @('Backend caído', $durante), @('Tras iniciarlo', $despues))) {
    $conteo = Get-Conteo (@($fase[1]) | ForEach-Object { $_.Backend })
    Write-Log ("  {0,-20} {1,4} peticiones | {2}" -f $fase[0], @($fase[1]).Count, (Format-Conteo $conteo))
}
Write-Log ''

if ($err.Count) {
    $primerErr = ($err | Measure-Object -Property T -Minimum).Minimum
    $ultimoErr = ($err | Measure-Object -Property T -Maximum).Maximum
    $tipos = ($err | Group-Object Estado | ForEach-Object { "HTTP $($_.Name)=$($_.Count)" }) -join ', '
    Write-Log ("Errores: {0} ({1}). Primero a t={2:N1}s ({3:N1}s tras la orden de parada); último a t={4:N1}s ({5:N1}s tras la orden)." -f $err.Count, $tipos, $primerErr, ($primerErr - $tStop), $ultimoErr, ($ultimoErr - $tStop)) 'Yellow'
    Write-Log '  (Estado 0 = sin respuesta/tiempo agotado; 5xx = error devuelto por Apache, p. ej. AH00898 al no resolver el backend caído)'
}
else {
    Write-Log 'Errores: ninguno durante toda la prueba.' 'Green'
}

$trasParada = @($filas | Where-Object { $_.Backend -eq $victima -and $_.T -ge $tStop })
if ($trasParada.Count) {
    $ultima = ($trasParada | Measure-Object -Property T -Maximum).Maximum
    Write-Log ("Última respuesta de {0} tras la orden de parada: t={1:N1}s ({2:N1}s después)." -f $victima, $ultima, ($ultima - $tStop))
}
else {
    Write-Log "$victima no respondió ninguna petición después de la orden de parada."
}

$trasInicio = @($filas | Where-Object { $_.Backend -eq $victima -and $_.T -ge $tStart })
$recuperado = $false
if ($trasInicio.Count) {
    $primera = ($trasInicio | Measure-Object -Property T -Minimum).Minimum
    $recuperado = $true
    Write-Log ("{0} vuelve a recibir tráfico a t={1:N1}s: {2:N1}s después de la orden de arranque (sin reiniciar Apache)." -f $victima, $primera, ($primera - $tStart)) 'Green'
}
else {
    Write-Log "$victima NO volvió a recibir tráfico dentro de la ventana medida. Aumenta -Duracion o revisa los logs." 'Red'
}

# --- Comprobación final de reparto ---
Write-Log ''
$fin = New-Object System.Collections.Generic.List[string]
for ($i = 1; $i -le (10 * $n); $i++) { $fin.Add((Invoke-Req $url 10).Body) }
$cuentaFin = Get-Conteo $fin
Write-Log "Reparto final ($(10 * $n) peticiones): $(Format-Conteo $cuentaFin)"
$todos = @(1..$n | Where-Object { -not $cuentaFin.ContainsKey("backend$_") }).Count -eq 0
$sinError = -not $cuentaFin.ContainsKey('ERROR')
if ($todos -and $sinError) { Write-Log 'Comprobación final: los backends participan en el balanceo sin errores.' 'Green' }
else { Write-Log 'Comprobación final: FALLÓ (algún backend no recibe tráfico o hay errores).' 'Red' }

# --- Guardar evidencias ---
New-Item -ItemType Directory -Force $script:LogsDir | Out-Null
$csv = Join-Path $script:LogsDir "$nombreBase.csv"
$filas | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8

$desde = "$([int][math]::Ceiling($reloj.Elapsed.TotalSeconds) + 15)s"
$logApache = @(Invoke-Docker (Get-ComposeArgs $n @('logs', '--no-color', '--since', $desde, 'balanceador')))
$logApache | Out-File -FilePath (Join-Path $script:LogsDir "${nombreBase}_apache.log") -Encoding utf8
$eventos = @($logApache | Where-Object { $_ -match 'AH0\d+|" 5\d\d |\[error\]|\[warn\]|hcheck' })
$eventos | Out-File -FilePath (Join-Path $script:LogsDir "${nombreBase}_apache_eventos.log") -Encoding utf8
$logVictima = @(Invoke-Docker (Get-ComposeArgs $n @('logs', '--no-color', '--since', $desde, $victima)))
$logVictima | Out-File -FilePath (Join-Path $script:LogsDir "${nombreBase}_${victima}.log") -Encoding utf8

Write-Log ''
Write-Log "Eventos de Apache durante la prueba (errores/avisos): $($eventos.Count) líneas"
foreach ($e in ($eventos | Select-Object -First 10)) { Write-Log "  $e" }
if ($eventos.Count -gt 10) { Write-Log "  ... (ver ${nombreBase}_apache_eventos.log)" }

Write-Log ''
Write-Log ("Órdenes: parada {0} (t={1:N1}s) | arranque {2} (t={3:N1}s)" -f $horaStop, $tStop, $horaStart, $tStart)
$resumen = Join-Path $script:LogsDir "${nombreBase}_resumen.txt"
Save-Log $resumen
Write-Host ''
Write-Host "Archivos guardados en evidencias\logs\ con prefijo: $nombreBase" -ForegroundColor Green
Write-Host '  Haz una captura de esta pantalla y guárdala en evidencias\capturas\' -ForegroundColor Green

if ($recuperado -and $todos -and $sinError) { exit 0 } else { exit 1 }
