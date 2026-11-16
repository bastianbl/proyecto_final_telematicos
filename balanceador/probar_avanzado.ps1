<#
.SYNOPSIS
  Cuenta los backends que respondieron a N peticiones del balanceador.
.EXAMPLE
  .\balanceador\probar_avanzado.ps1 -Solicitudes 100 -Puerto 8080
#>
[CmdletBinding()]
param(
    [ValidateRange(1,10000)][int]$Solicitudes = 100,
    [ValidateRange(1,65535)][int]$Puerto = 8080
)

$conteos = @{}
$url = "http://127.0.0.1:$Puerto/"

for ($i = 1; $i -le $Solicitudes; $i++) {
    try {
        $respuesta = (Invoke-RestMethod -Uri $url -TimeoutSec 10).Trim()
        if ($respuesta -notmatch '^backend[1-7]$') {
            $respuesta = "INESPERADA: $respuesta"
        }
    }
    catch {
        $respuesta = 'ERROR'
    }
    if (-not $conteos.ContainsKey($respuesta)) {
        $conteos[$respuesta] = 0
    }
    $conteos[$respuesta]++
}

$conteos.Keys | Sort-Object | ForEach-Object {
    [PSCustomObject]@{
        Backend = $_
        Solicitudes = $conteos[$_]
        Porcentaje = [math]::Round(100 * $conteos[$_] / $Solicitudes, 2)
    }
} | Format-Table -AutoSize
