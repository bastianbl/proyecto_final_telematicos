[CmdletBinding()]
param(
    [ValidateSet('Up', 'Down', 'Restart', 'Status', 'Logs', 'Artillery')]
    [string]$Action = 'Up',

    [ValidateSet(0, 3, 5, 7)]
    [int]$BackendCount = 0,

    [string]$BalancerMethod
)

$ErrorActionPreference = 'Stop'
$composeFile = Join-Path $PSScriptRoot '..\docker-compose.yml'
$composeBase = @('compose', '-f', $composeFile)
$envFile = Join-Path $PSScriptRoot '..\.env'
$fileSettings = @{}

if (Test-Path $envFile) {
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
            $value = $Matches[2]
            if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $fileSettings[$Matches[1]] = $value
        }
    }
}

if ($BackendCount -eq 0) {
    $configuredCount = $env:BACKEND_COUNT
    if (-not $configuredCount) { $configuredCount = $fileSettings['BACKEND_COUNT'] }
    if (-not $configuredCount) { $configuredCount = '3' }
    if ($configuredCount -notmatch '^(3|5|7)$') {
        throw "BACKEND_COUNT debe ser 3, 5 o 7 (actual: $configuredCount)."
    }
    $BackendCount = [int]$configuredCount
}

if ([string]::IsNullOrWhiteSpace($BalancerMethod)) {
    $BalancerMethod = $env:BALANCER_METHOD
    if (-not $BalancerMethod) { $BalancerMethod = $fileSettings['BALANCER_METHOD'] }
    if (-not $BalancerMethod) { $BalancerMethod = 'byrequests' }
}
if ($BalancerMethod -notin @('byrequests', 'bybusyness')) {
    throw "BALANCER_METHOD debe ser byrequests o bybusyness (actual: $BalancerMethod)."
}

function Invoke-Compose {
    param([string[]]$Arguments)

    & docker @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Falló docker $($Arguments -join ' ') con código $LASTEXITCODE."
    }
}

function Get-ProfileArguments {
    if ($BackendCount -eq 5) { return @('--profile', 'cinco') }
    if ($BackendCount -eq 7) { return @('--profile', 'siete') }
    return @()
}

function Get-BackendNames {
    return @(
        for ($i = 1; $i -le $BackendCount; $i++) { "backend$i" }
    )
}

function Start-Stack {
    $profileArgs = Get-ProfileArguments
    $backends = Get-BackendNames

    # Arranca y espera los healthchecks de todos los backends seleccionados.
    Invoke-Compose ($composeBase + $profileArgs + @('up', '-d', '--build', '--wait') + $backends)
    # Apache genera su pool al iniciar; levantarlo después evita resolver backends antes de que existan.
    Invoke-Compose ($composeBase + $profileArgs + @('up', '-d', '--build', 'balanceador'))
}

function Stop-Stack {
    # Activa todos los perfiles para retirar también servicios que quedaron de una ejecución de 5/7.
    $allProfiles = @('--profile', 'cinco', '--profile', 'siete', '--profile', 'artillery')
    Invoke-Compose ($composeBase + $allProfiles + @('down', '--remove-orphans'))
}

$oldBackendCount = $env:BACKEND_COUNT
$oldBalancerMethod = $env:BALANCER_METHOD
$env:BACKEND_COUNT = "$BackendCount"
$env:BALANCER_METHOD = $BalancerMethod

try {
    switch ($Action) {
        'Up' { Start-Stack }
        'Down' { Stop-Stack }
        'Restart' {
            Stop-Stack
            Start-Stack
        }
        'Status' {
            $profileArgs = @('--profile', 'cinco', '--profile', 'siete', '--profile', 'artillery')
            Invoke-Compose ($composeBase + $profileArgs + @('ps', '-a'))
        }
        'Logs' {
            $profileArgs = Get-ProfileArguments
            Invoke-Compose ($composeBase + $profileArgs + @('logs', '--follow', '--tail', '100'))
        }
        'Artillery' {
            Start-Stack
            $profileArgs = Get-ProfileArguments
            Invoke-Compose ($composeBase + $profileArgs + @('--profile', 'artillery', 'run', '--rm', 'artillery'))
        }
    }
}
finally {
    if ($null -eq $oldBackendCount) { Remove-Item Env:BACKEND_COUNT -ErrorAction SilentlyContinue }
    else { $env:BACKEND_COUNT = $oldBackendCount }
    if ($null -eq $oldBalancerMethod) { Remove-Item Env:BALANCER_METHOD -ErrorAction SilentlyContinue }
    else { $env:BALANCER_METHOD = $oldBalancerMethod }
}
