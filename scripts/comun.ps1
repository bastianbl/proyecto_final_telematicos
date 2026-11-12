# Funciones compartidas por los scripts del integrante 6 (verificar, prueba_caida, recolectar_evidencias).
# No se ejecuta directamente. Se carga con:  . (Join-Path $PSScriptRoot 'comun.ps1')

$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest es mucho más rápido sin barra de progreso

$script:Raiz        = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:ComposeFile = Join-Path $script:Raiz 'docker-compose.yml'
$script:LogsDir     = Join-Path $script:Raiz 'evidencias\logs'
$script:Lineas      = New-Object System.Collections.Generic.List[string]
$script:DockerExit  = 0

# ---------- Salida en pantalla + informe ----------
function Write-Log {
    param([string]$Texto = '', [string]$Color = '')
    $script:Lineas.Add($Texto)
    if ($Color) { Write-Host $Texto -ForegroundColor $Color } else { Write-Host $Texto }
}

function Save-Log {
    param([string]$Ruta)
    New-Item -ItemType Directory -Force (Split-Path $Ruta) | Out-Null
    $script:Lineas | Out-File -FilePath $Ruta -Encoding utf8
}

# ---------- Configuración (variable de entorno > .env > valor por defecto) ----------
function Get-EnvFile {
    $cfg = @{}
    $envFile = Join-Path $script:Raiz '.env'
    if (Test-Path $envFile) {
        foreach ($line in Get-Content $envFile) {
            if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
                $v = $Matches[2]
                if ($v.Length -ge 2 -and (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'")))) {
                    $v = $v.Substring(1, $v.Length - 2)
                }
                $cfg[$Matches[1]] = $v
            }
        }
    }
    return $cfg
}

function Get-Setting {
    param([string]$Nombre, [string]$Defecto)
    $v = [Environment]::GetEnvironmentVariable($Nombre)
    if ($v) { return $v }
    $cfg = Get-EnvFile
    if ($cfg.ContainsKey($Nombre) -and $cfg[$Nombre]) { return $cfg[$Nombre] }
    return $Defecto
}

function Resolve-BackendCount {
    param([int]$Valor)
    if ($Valor -ne 0) { return $Valor }
    $v = Get-Setting 'BACKEND_COUNT' '3'
    if ($v -notmatch '^(3|5|7)$') { throw "BACKEND_COUNT debe ser 3, 5 o 7 (actual: $v)." }
    return [int]$v
}

# ---------- Docker ----------
function Get-ComposeArgs {
    param([int]$Cantidad, [string[]]$Extra)
    $perfil = @()
    if ($Cantidad -eq 5) { $perfil = @('--profile', 'cinco') }
    if ($Cantidad -eq 7) { $perfil = @('--profile', 'siete') }
    return @('compose', '-f', $script:ComposeFile) + $perfil + $Extra
}

# Ejecuta docker, devuelve las líneas (stdout+stderr) y guarda el código de salida en $script:DockerExit.
# No lanza error por escribir en stderr (Docker lo hace en operaciones normales).
function Invoke-Docker {
    param([string[]]$Arguments)
    $previo = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $salida = & docker @Arguments 2>&1 | ForEach-Object { "$_" }
        $script:DockerExit = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previo }
    if ($null -ne $salida) { $salida }
}

# Lanza docker sin esperar (para parar/arrancar un backend mientras el script sigue enviando tráfico).
function Start-DockerSegundoPlano {
    param([string[]]$Arguments)
    $texto = ($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $p = Start-Process -FilePath 'docker' -ArgumentList $texto -WindowStyle Hidden -PassThru
    $null = $p.Handle   # necesario en Windows PowerShell 5.1 para poder leer ExitCode después
    return $p
}

function Get-MetodoActivo {
    param([int]$Cantidad)
    $conf = @(Invoke-Docker (Get-ComposeArgs $Cantidad @('exec', '-T', 'balanceador', 'cat', '/usr/local/apache2/conf/extra/balancer-members.conf')))
    foreach ($l in $conf) { if ($l -match 'lbmethod=(\w+)') { return $Matches[1] } }
    return 'desconocido'
}

# ---------- HTTP ----------
function Invoke-Req {
    param([string]$Url, [int]$TimeoutSec = 10)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec
        $sw.Stop()
        return [pscustomobject]@{
            Ok = $true; Status = [int]$r.StatusCode
            Body = ([string]$r.Content).Trim(); Ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
        }
    }
    catch {
        $sw.Stop()
        $status = 0
        try { if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode } } catch { }
        return [pscustomobject]@{
            Ok = $false; Status = $status
            Body = 'ERROR'; Ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
        }
    }
}

# ---------- Conteos ----------
function Get-Conteo {
    param($Respuestas)
    $h = @{}
    foreach ($x in $Respuestas) {
        if ($h.ContainsKey($x)) { $h[$x]++ } else { $h[$x] = 1 }
    }
    return $h
}

function Format-Conteo {
    param($Conteo)
    if ($Conteo.Count -eq 0) { return '(sin respuestas)' }
    return (($Conteo.Keys | Sort-Object | ForEach-Object { "$_=$($Conteo[$_])" }) -join ', ')
}
