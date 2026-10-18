<#
  Deja todo listo para probar A MANO en el navegador:
    - Administrativo: API en 5118 + frontend en http://localhost:4200
    - Deportivo (con los dos parches): API en 5191 + frontend en http://localhost:4300
  Usa los puertos por defecto de cada proyecto, asi no hay que tocar ninguna configuracion.

  Requisitos: haber corrido antes, UNA vez, scripts\armar.ps1 (crea la base de prueba y la carpeta de trabajo).
  Conviene armarlo recien (con -Recrear) y NO correr probar.ps1 antes: deja datos de prueba en la base.

  Uso:
    .\scripts\armar.ps1 -RepoNuestro "C:\...\Sistema Administrativo - CACC" -RepoEllos "C:\...\App-Club-Atletico-Camioneros" -Recrear
    .\scripts\manual.ps1 -RepoNuestro "C:\...\Sistema Administrativo - CACC" -RepoEllos "C:\...\App-Club-Atletico-Camioneros"
  Para frenar todo: .\scripts\manual.ps1 -Detener
#>
param(
    [string]$RepoNuestro = '',
    [string]$RepoEllos = '',
    [string]$Destino = '',
    [switch]$Detener
)
$ErrorActionPreference = 'Stop'
$raiz = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Destino) { $Destino = Join-Path $raiz 'trabajo' }

function Parar {
    Get-CimInstance Win32_Process | Where-Object {
        ($_.CommandLine -match 'ApiGestion\.(csproj|dll|exe)|CACC\.API\.(csproj|dll|exe)') -or
        ($_.CommandLine -match 'ng(\.cmd)? serve|@angular[\\/]cli')
    } | Where-Object { $_.Name -match '^(dotnet|ApiGestion|CACC\.API|node|cmd|powershell)(\.exe)?$' -and $_.ProcessId -ne $PID } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep 2
}
if ($Detener) { Parar; Write-Host 'Todo detenido.'; exit 0 }

if (-not $RepoNuestro -or -not $RepoEllos) { throw 'Indica -RepoNuestro y -RepoEllos (las mismas carpetas que usaste en armar.ps1).' }
if (-not (Test-Path (Join-Path $Destino 'nuestro\ApiGestion\ApiGestion.csproj'))) { throw "No encuentro la carpeta de trabajo en $Destino. Corre antes scripts\armar.ps1." }
$Destino = (Resolve-Path $Destino).Path
$RepoNuestro = (Resolve-Path $RepoNuestro).Path
$RepoEllos = (Resolve-Path $RepoEllos).Path
$feEllos = Join-Path $Destino 'ellos\FrontEnd'
$feNuestro = Join-Path $RepoNuestro 'frontend-cacc'

# ---- 1. Frontend del Deportivo con el parche (copia de trabajo; tu repo no se toca)
if (-not (Test-Path (Join-Path $feEllos 'node_modules'))) {
    Write-Host '== Preparando el frontend del Deportivo (copia + parche + npm ci; la primera vez tarda unos minutos)' -ForegroundColor Cyan
    if (Test-Path $feEllos) { Remove-Item $feEllos -Recurse -Force }
    robocopy (Join-Path $RepoEllos 'FrontEnd') $feEllos /E /XD node_modules .angular dist .git /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw 'Fallo la copia del FrontEnd.' }
    & (Join-Path $raiz 'parches\aplicar-parche.ps1') -Parche (Join-Path $raiz 'parches\ellos-definitivo-frontend.patch') -Carpeta $feEllos
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo aplicar el parche del frontend.' }
    Push-Location $feEllos; $ErrorActionPreference = 'Continue'; try { npm ci --no-audit --no-fund 2>&1 | Out-Host; if ($LASTEXITCODE -ne 0) { Remove-Item (Join-Path $feEllos 'node_modules') -Recurse -Force -ErrorAction SilentlyContinue; throw 'Fallo npm ci del Deportivo.' } } finally { $ErrorActionPreference = 'Stop'; Pop-Location }
}
if (-not (Test-Path (Join-Path $feNuestro 'node_modules'))) {
    Write-Host '== npm ci del frontend del Administrativo' -ForegroundColor Cyan
    Push-Location $feNuestro; $ErrorActionPreference = 'Continue'; try { npm ci --no-audit --no-fund 2>&1 | Out-Host; if ($LASTEXITCODE -ne 0) { throw 'Fallo npm ci del Administrativo.' } } finally { $ErrorActionPreference = 'Stop'; Pop-Location }
}

# ---- 2. APIs en los puertos por defecto (las claves y la base son las de la carpeta de trabajo)
Write-Host '== Levantando las APIs' -ForegroundColor Cyan
Parar
$env:ASPNETCORE_ENVIRONMENT = 'Development'
$env:AdministrativoApi__BaseUrl = 'http://localhost:5118'   # el Deportivo consulta la deuda aca
Start-Process dotnet -ArgumentList "run --project `"$Destino\nuestro\ApiGestion\ApiGestion.csproj`" --no-build --urls http://localhost:5118" `
    -RedirectStandardOutput "$Destino\log_nuestro.txt" -RedirectStandardError "$Destino\log_nuestro_err.txt" -WindowStyle Hidden
Start-Process dotnet -ArgumentList "run --project `"$Destino\ellos\BackEnd\CACC.API\CACC.API.csproj`" --no-build --urls http://localhost:5191" `
    -RedirectStandardOutput "$Destino\log_ellos.txt" -RedirectStandardError "$Destino\log_ellos_err.txt" -WindowStyle Hidden
$limite = (Get-Date).AddSeconds(90)
do { Start-Sleep 2; $p = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in 5118, 5191 } | Select-Object -ExpandProperty LocalPort -Unique) } while ($p.Count -lt 2 -and (Get-Date) -lt $limite)
if ($p.Count -lt 2) { throw "No levantaron las dos APIs (puertos abiertos: $($p -join ', ')). Mira los logs en $Destino." }

# ---- 3. Frontends (cada uno en su ventana; se cierran con la X o con -Detener)
Write-Host '== Levantando los frontends (cada uno abre su ventana; esperar a que diga "Local: http://localhost:...")' -ForegroundColor Cyan
Start-Process powershell -ArgumentList '-NoExit', '-Command', "`$Host.UI.RawUI.WindowTitle='Frontend ADMINISTRATIVO 4200'; cd '$feNuestro'; npx ng serve --port 4200"
Start-Process powershell -ArgumentList '-NoExit', '-Command', "`$Host.UI.RawUI.WindowTitle='Frontend DEPORTIVO 4300'; cd '$feEllos'; npx ng serve --port 4300"

Write-Host ''
Write-Host 'Listo. Abri en el navegador:  http://localhost:4200   (Administrativo)' -ForegroundColor Green
Write-Host '  SuperAdmin  DNI 20111222  /  clave Camioneros.Test.2026!   (ve los dos portales)'
Write-Host '  Medica      DNI 30000003  (solo Deportivo)     Director Tecnico  DNI 30000004  (solo Deportivo, categoria 3)'
Write-Host 'APIs: Administrativo 5118 | Deportivo 5191.  Para frenar todo: .\scripts\manual.ps1 -Detener'
