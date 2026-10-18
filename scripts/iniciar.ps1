# Levanta las dos APIs de la carpeta de trabajo: Administrativo en 5318 y Deportivo en 5319.
# Los logs quedan en la carpeta de trabajo (log_nuestro.txt, log_ellos.txt).
param([string]$Destino = '')
if (-not $Destino) { $Destino = Join-Path $PSScriptRoot '..\trabajo' }
$Destino = (Resolve-Path $Destino).Path
$env:ASPNETCORE_ENVIRONMENT = 'Development'
Start-Process dotnet -ArgumentList "run --project `"$Destino\nuestro\ApiGestion\ApiGestion.csproj`" --no-build --urls http://localhost:5318" `
    -RedirectStandardOutput "$Destino\log_nuestro.txt" -RedirectStandardError "$Destino\log_nuestro_err.txt" -WindowStyle Hidden
Start-Process dotnet -ArgumentList "run --project `"$Destino\ellos\BackEnd\CACC.API\CACC.API.csproj`" --no-build --urls http://localhost:5319" `
    -RedirectStandardOutput "$Destino\log_ellos.txt" -RedirectStandardError "$Destino\log_ellos_err.txt" -WindowStyle Hidden
Write-Host 'Esperando que arranquen...'
$limite = (Get-Date).AddSeconds(90)
do { Start-Sleep 2; $p = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in 5318, 5319 } | Select-Object -ExpandProperty LocalPort -Unique) } while ($p.Count -lt 2 -and (Get-Date) -lt $limite)
if ($p.Count -lt 2) { Write-Host "No levantaron las dos APIs (puertos abiertos: $($p -join ', ')). Mira los logs en $Destino." -ForegroundColor Red; exit 1 }
Write-Host 'Administrativo: http://localhost:5318   |   Deportivo: http://localhost:5319' -ForegroundColor Green
