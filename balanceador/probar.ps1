# Ejecutar desde la raiz del repositorio: .\balanceador\probar.ps1
param(
    [int]$Peticiones = 21,
    [string]$Url = 'http://localhost:8080/'
)
$ErrorActionPreference = 'Stop'
$observaciones = @(
    for ($i = 1; $i -le $Peticiones; $i++) {
        (Invoke-RestMethod -Uri $Url -TimeoutSec 10).Trim()
    }
)
Write-Host "Respuestas recibidas: $($observaciones.Count)"
$observaciones | Group-Object | Sort-Object Name | Select-Object Name, Count | Format-Table -AutoSize
