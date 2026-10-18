<#
  Corre las pruebas del proyecto del Portal Administrativo (ApiGestion.Tests) contra una base unificada de pruebas.
  Crea (o recrea) la base ClubCamionerosUnificadaV2_Test con el script de /base-de-datos y las cuentas de prueba,
  define CACC_TEST_DB para esta ejecucion y corre dotnet test.

  Uso:  .\scripts\pruebas-del-proyecto.ps1 -RepoNuestro "C:\...\Sistema Administrativo - CACC"
#>
param(
    [Parameter(Mandatory)][string]$RepoNuestro,
    [string]$Servidor = 'localhost',
    [string]$Base = 'ClubCamionerosUnificadaV2_Test'
)
$ErrorActionPreference = 'Stop'
$raiz = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$proyecto = Join-Path $RepoNuestro 'ApiGestion.Tests\ApiGestion.Tests.csproj'
if (-not (Test-Path $proyecto)) { Write-Host "No encuentro $proyecto" -ForegroundColor Red; exit 1 }

$existe = (sqlcmd -S $Servidor -E -C -h -1 -W -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.databases WHERE name = N'$Base'") -join ''
if ($existe.Trim() -ne '0') { sqlcmd -S $Servidor -E -C -b -Q "ALTER DATABASE [$Base] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$Base];" }
$sql = [IO.File]::ReadAllText((Join-Path $raiz 'base-de-datos\ClubCamioneros_unificada_v2_crear_base.sql')).Replace('ClubCamionerosUnificadaV2', $Base)
$tmp = Join-Path $env:TEMP 'crear_base_test.sql'; [IO.File]::WriteAllText($tmp, $sql, (New-Object Text.UTF8Encoding($false)))
sqlcmd -S $Servidor -E -C -b -f 65001 -i $tmp | Out-Null
sqlcmd -S $Servidor -E -C -I -b -f 65001 -d $Base -i (Join-Path $raiz 'pruebas\seed_cuentas_prueba.sql') | Out-Null
Write-Host "Base $Base lista."

$env:CACC_TEST_DB = "Server=$Servidor;Database=$Base;Trusted_Connection=True;TrustServerCertificate=True;"
dotnet test $proyecto --nologo
exit $LASTEXITCODE
