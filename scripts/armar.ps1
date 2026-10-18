<#
  Arma el entorno de prueba de la unificacion desde cero:
    1. copia tu repo y un clon del repo del otro equipo a la carpeta de trabajo (no los modifica),
    2. aplica los parches de /parches,
    3. crea la base de datos de prueba con el script de /base-de-datos y carga las cuentas de prueba,
    4. escribe la configuracion (clave JWT compartida generada al azar, sin credenciales de correo),
    5. compila las dos APIs.
  Con -Iniciar tambien las levanta (Administrativo 5318, Deportivo 5319).

  Uso:
    .\scripts\armar.ps1 -RepoNuestro "C:\...\Sistema Administrativo - CACC" -RepoEllos "C:\...\App-Club-Atletico-Camioneros" -Recrear -Iniciar

  Requisitos: .NET SDK 9, sqlcmd, Git para Windows (se usa su patch.exe) y SQL Server local con autenticacion de Windows.
  La carpeta de trabajo (por defecto ..\trabajo) esta en .gitignore: se puede borrar cuando se quiera.
#>
param(
    [Parameter(Mandatory)][string]$RepoNuestro,
    [Parameter(Mandatory)][string]$RepoEllos,
    [string]$Destino = '',
    [string]$Servidor = 'localhost',
    [string]$Base = 'ClubCamionerosUnificadaV2_Prueba',
    [switch]$Recrear,
    [switch]$Iniciar
)
$ErrorActionPreference = 'Stop'
if (-not $Destino) { $Destino = Join-Path $PSScriptRoot '..\trabajo' }
$raiz = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Fallar($m) { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }
function Paso($m) { Write-Host "`n== $m" -ForegroundColor Cyan }

# ---- 0. comprobaciones
if (-not (Test-Path (Join-Path $RepoNuestro 'ApiGestion\ApiGestion.csproj'))) { Fallar "No encuentro ApiGestion\ApiGestion.csproj en -RepoNuestro ($RepoNuestro)." }
if (-not (Test-Path (Join-Path $RepoEllos 'BackEnd\CACC.API\CACC.API.csproj'))) { Fallar "No encuentro BackEnd\CACC.API\CACC.API.csproj en -RepoEllos ($RepoEllos). Tiene que ser un clon de NejoCHZ/App-Club-Atletico-Camioneros (rama main)." }
foreach ($c in 'dotnet', 'sqlcmd') { if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { Fallar "Falta '$c' en el PATH." } }
$patch = (Get-Command patch -ErrorAction SilentlyContinue).Source
if (-not $patch) {
    $git = (Get-Command git -ErrorAction SilentlyContinue).Source
    if ($git) { $cand = Join-Path (Split-Path (Split-Path $git)) 'usr\bin\patch.exe'; if (Test-Path $cand) { $patch = $cand } }
}
if (-not $patch) { Fallar "No encuentro patch.exe (viene con Git para Windows, en Git\usr\bin)." }

$versiones = Get-Content (Join-Path $raiz 'versiones.json') -Raw | ConvertFrom-Json
Write-Host "Versiones esperadas -> nuestro: $($versiones.nuestro.commit) ($($versiones.nuestro.rama)) | ellos: $($versiones.ellos.commit) ($($versiones.ellos.rama))"
Write-Host "Si los parches no aplican, es que alguno de los repos cambio desde esas versiones."

New-Item -ItemType Directory -Force $Destino | Out-Null
$Destino = (Resolve-Path $Destino).Path
$marca = Join-Path $Destino '.cacc-unificacion'

# ---- 1. frenar APIs y limpiar la carpeta de trabajo (solo si es nuestra)
& (Join-Path $PSScriptRoot 'detener.ps1') | Out-Null
if ((Get-ChildItem $Destino -Force | Measure-Object).Count -gt 0 -and -not (Test-Path $marca)) { Fallar "La carpeta $Destino no esta vacia y no es de este repo. Elegi otra con -Destino." }
Paso "Copiando los repos a $Destino"
foreach ($d in 'nuestro', 'ellos') { $p = Join-Path $Destino $d; if (Test-Path $p) { Remove-Item $p -Recurse -Force } }
Set-Content $marca 'carpeta de trabajo de cacc-unificacion (se puede borrar)'

function Copiar($origen, $destino, $extraXD = @()) {
    robocopy $origen $destino /E /XD bin obj node_modules .git .vs @extraXD /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Fallar "robocopy fallo copiando $origen" }
}
$n = Join-Path $Destino 'nuestro'
foreach ($d in 'ApiGestion', 'DaoLibrary', 'ServiceLibrary', 'EntityLibrary') { Copiar (Join-Path $RepoNuestro $d) (Join-Path $n $d) }
Copiar (Join-Path $RepoNuestro 'database\migrations') (Join-Path $n 'database\migrations')
foreach ($f in 'SistemaCamionerosBackend.slnx', 'global.json') { Copy-Item (Join-Path $RepoNuestro $f) $n -Force }
# el proyecto incrusta esta imagen del frontend en los correos
New-Item -ItemType Directory -Force (Join-Path $n 'frontend-cacc\public') | Out-Null
Copy-Item (Join-Path $RepoNuestro 'frontend-cacc\public\cacc-email-header.jpg') (Join-Path $n 'frontend-cacc\public') -Force
Remove-Item (Join-Path $n 'ApiGestion\appsettings.Development.json') -Force -ErrorAction SilentlyContinue   # trae credenciales reales
Copiar (Join-Path $RepoEllos 'BackEnd') (Join-Path $Destino 'ellos\BackEnd')

# ---- 1b. saltos de linea: los parches estan en LF y sin BOM. Un clon en Windows puede traer CRLF o BOM:
#          se normaliza la COPIA de trabajo (nunca tus repos). Se trabaja byte a byte (Latin-1), sin alterar acentos.
Paso "Normalizando saltos de linea de la copia"
$latin1 = [Text.Encoding]::GetEncoding(28591); $norm = 0
Get-ChildItem $Destino -Recurse -Filter *.cs -File | Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' } | ForEach-Object {
    $b = [IO.File]::ReadAllBytes($_.FullName)
    $t = $latin1.GetString($b)
    $t2 = $t.Replace("`r`n", "`n")
    if ($t2.Length -gt 0 -and $t2[0] -eq [char]0xEF -and $t2.StartsWith([string]([char]0xEF) + [char]0xBB + [char]0xBF)) { $t2 = $t2.Substring(3) }
    if ($t2 -ne $t) { [IO.File]::WriteAllBytes($_.FullName, $latin1.GetBytes($t2)); $norm++ }
}
Write-Host "  $norm archivos normalizados."
# ---- 2. parches
Paso "Aplicando parches"
function Aplicar($carpeta, $archivo) {
    Push-Location $carpeta
    try {
        & $patch --binary -p1 -N -s -i $archivo
        if ($LASTEXITCODE -ne 0) { Fallar "El parche $(Split-Path $archivo -Leaf) no aplica sobre $carpeta (codigo $LASTEXITCODE)." }
    } finally { Pop-Location }
    Write-Host "  OK $(Split-Path $archivo -Leaf)"
}
# Si el repo del Administrativo ya trae los cambios (rama feat/base-unificada o posterior), el parche no se aplica de nuevo.
$yaAdaptado = (Select-String -Path (Join-Path $n 'DaoLibrary\AuthDao.cs') -Pattern 'FROM USUARIOS' -Quiet)
if ($yaAdaptado) { Write-Host "  El repo del Administrativo ya esta adaptado a la base unificada: se omite nuestro.patch." }
else { Aplicar $n (Join-Path $raiz 'parches\nuestro.patch') }
Aplicar (Join-Path $Destino 'ellos\BackEnd') (Join-Path $raiz 'parches\ellos-provisorio.patch')
if (Test-Path (Join-Path $raiz 'parches\ellos.patch')) { Aplicar (Join-Path $Destino 'ellos\BackEnd') (Join-Path $raiz 'parches\ellos.patch') }

# ---- 3. configuracion (clave JWT compartida, aleatoria por armado)
Paso "Escribiendo la configuracion"
$bytes = New-Object byte[] 48; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$clave = [Convert]::ToBase64String($bytes)
$cadena = "Server=$Servidor;Database=$Base;Trusted_Connection=True;TrustServerCertificate=True;"
$json = @{
    Jwt = @{ Key = $clave; Issuer = 'CACC-Unificado'; Audience = 'CACC-Unificado' }
    ConnectionStrings = @{ ConexionSQL = $cadena }
    Email = @{ PublicBaseUrl = 'http://localhost:4318'; LogResetLink = $true }
} | ConvertTo-Json -Depth 5
Set-Content (Join-Path $n 'ApiGestion\appsettings.Development.json') $json -Encoding UTF8
$json2 = @{
    JwtSettings = @{ Key = $clave; Issuer = 'CACC-Unificado'; Audience = 'CACC-Unificado'; ExpirationMinutes = '60' }
    ConnectionStrings = @{ DefaultConnection = $cadena }
} | ConvertTo-Json -Depth 5
Set-Content (Join-Path $Destino 'ellos\BackEnd\CACC.API\appsettings.Development.json') $json2 -Encoding UTF8
Write-Host "  Sin credenciales de correo: los enlaces de activacion se escriben en el log de la API."

# ---- 4. base de datos
Paso "Creando la base $Base en $Servidor"
$existe = (sqlcmd -S $Servidor -E -C -h -1 -W -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.databases WHERE name = N'$Base'") -join ''
if ($existe.Trim() -ne '0') {
    if (-not $Recrear) { Fallar "La base $Base ya existe. Usa -Recrear para borrarla y volver a crearla (es solo de prueba)." }
    sqlcmd -S $Servidor -E -C -b -Q "ALTER DATABASE [$Base] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$Base];"
    if ($LASTEXITCODE -ne 0) { Fallar "No pude borrar $Base." }
}
$sql = [IO.File]::ReadAllText((Join-Path $raiz 'base-de-datos\ClubCamioneros_unificada_v2_crear_base.sql')).Replace('ClubCamionerosUnificadaV2', $Base)
$tmp = Join-Path $Destino 'crear_base.sql'; [IO.File]::WriteAllText($tmp, $sql, (New-Object Text.UTF8Encoding($false)))
sqlcmd -S $Servidor -E -C -b -f 65001 -i $tmp | Out-Null
if ($LASTEXITCODE -ne 0) { Fallar "Fallo el script de la base." }
sqlcmd -S $Servidor -E -C -I -b -f 65001 -d $Base -i (Join-Path $raiz 'pruebas\seed_cuentas_prueba.sql') | Out-Null
if ($LASTEXITCODE -ne 0) { Fallar "Fallo la carga de las cuentas de prueba." }
Write-Host "  Base creada, con los catalogos y 4 cuentas de prueba."

# ---- 5. compilar
Paso "Compilando"
Push-Location $n; dotnet build ApiGestion\ApiGestion.csproj -v q --nologo | Select-String 'error|Compilaci|Build succeeded'; $c1 = $LASTEXITCODE; Pop-Location
Push-Location (Join-Path $Destino 'ellos\BackEnd'); dotnet build CACC.API\CACC.API.csproj -v q --nologo | Select-String 'error|Compilaci|Build succeeded'; $c2 = $LASTEXITCODE; Pop-Location
if ($c1 -ne 0 -or $c2 -ne 0) { Fallar "No compilo alguna de las APIs." }

if ($Iniciar) { & (Join-Path $PSScriptRoot 'iniciar.ps1') -Destino $Destino }
else { Write-Host "`nListo. Para levantar las APIs: .\scripts\iniciar.ps1   |   para probar: .\scripts\probar.ps1" -ForegroundColor Green }
