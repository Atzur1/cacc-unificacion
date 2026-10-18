<#
  Aplica uno de los parches del Portal Deportivo sobre su carpeta (BackEnd o FrontEnd) cuidando los saltos de linea.

  Los parches estan escritos con saltos de linea LF y sin BOM, pero los archivos del repo pueden traer CRLF y/o BOM (segun
  el editor y la configuracion de git de cada uno). Aplicarlos tal cual falla. Este script, por cada archivo que toca el parche:
    1. recuerda como esta (CRLF o LF, con o sin BOM) y lo pasa a LF sin BOM,
    2. aplica el parche con "git apply",
    3. devuelve cada archivo a su formato original (los archivos nuevos toman el formato mas comun de los demas).
  Si el parche no aplica, deja TODO como estaba.

  Uso (desde cualquier carpeta):
    .\aplicar-parche.ps1 -Parche .\ellos-definitivo.patch          -Carpeta C:\ruta\al\repo\BackEnd
    .\aplicar-parche.ps1 -Parche .\ellos-definitivo-frontend.patch -Carpeta C:\ruta\al\repo\FrontEnd
  Con -Verificar solo comprueba que aplica, sin tocar nada.
#>
param(
    [Parameter(Mandatory)][string]$Parche,
    [Parameter(Mandatory)][string]$Carpeta,
    [switch]$Verificar
)
$ErrorActionPreference = 'Stop'
$Parche = (Resolve-Path $Parche).Path
$Carpeta = (Resolve-Path $Carpeta).Path
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Hace falta Git instalado (git apply).' }

$bom = [byte[]](0xEF, 0xBB, 0xBF)
function TieneBom([byte[]]$b) { $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF }
function TieneCrlf([byte[]]$b) { for ($i = 0; $i -lt $b.Length - 1; $i++) { if ($b[$i] -eq 13 -and $b[$i + 1] -eq 10) { return $true } }; return $false }
function ALf([byte[]]$b) {
    $o = New-Object System.Collections.Generic.List[byte] ($b.Length)
    $desde = if (TieneBom $b) { 3 } else { 0 }
    for ($i = $desde; $i -lt $b.Length; $i++) { if ($b[$i] -eq 13 -and $i + 1 -lt $b.Length -and $b[$i + 1] -eq 10) { continue }; $o.Add($b[$i]) }
    return , $o.ToArray()
}
function ACrlf([byte[]]$b, [bool]$conBom) {
    $o = New-Object System.Collections.Generic.List[byte] ($b.Length + 1024)
    if ($conBom) { $o.AddRange($bom) }
    foreach ($x in $b) { if ($x -eq 10) { $o.Add(13) }; $o.Add($x) }
    return , $o.ToArray()
}
function ConBom([byte[]]$b) { $o = New-Object System.Collections.Generic.List[byte]; $o.AddRange($bom); $o.AddRange($b); return , $o.ToArray() }

# archivos que toca el parche (rutas a/... y b/... relativas a la carpeta)
$rutas = @(Get-Content $Parche -Encoding UTF8 | Where-Object { $_ -match '^\+\+\+ b/' } | ForEach-Object { ($_ -replace '^\+\+\+ b/', '') -replace "`t.*$", '' } | Sort-Object -Unique)
if ($rutas.Count -eq 0) { throw "No encontre archivos en $Parche." }

$original = @{}   # ruta -> @{ Bytes; Bom; Crlf }
foreach ($r in $rutas) {
    $f = Join-Path $Carpeta ($r -replace '/', '\')
    if (Test-Path $f) { $b = [IO.File]::ReadAllBytes($f); $original[$r] = @{ Bytes = $b; Bom = (TieneBom $b); Crlf = (TieneCrlf $b) } }
}
$usaCrlf = @($original.Values | Where-Object { $_.Crlf }).Count -gt (@($original.Values).Count / 2)

function Restaurar { foreach ($r in $original.Keys) { [IO.File]::WriteAllBytes((Join-Path $Carpeta ($r -replace '/', '\')), $original[$r].Bytes) }
    foreach ($r in $rutas) { if (-not $original.ContainsKey($r)) { $f = Join-Path $Carpeta ($r -replace '/', '\'); if (Test-Path $f) { Remove-Item $f -Force } } } }

try {
    foreach ($r in $original.Keys) {
        $f = Join-Path $Carpeta ($r -replace '/', '\')
        $lf = ALf $original[$r].Bytes
        if ($lf.Length -ne $original[$r].Bytes.Length) { [IO.File]::WriteAllBytes($f, $lf) }
    }
    Push-Location $Carpeta
    try {
        git apply -p1 --whitespace=nowarn --check $Parche 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw 'El parche no aplica sobre esta version del repo (cambiaron los archivos?).' }
        if (-not $Verificar) {
            git apply -p1 --whitespace=nowarn $Parche 2>&1 | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) { throw 'Fallo la aplicacion del parche.' }
        }
    } finally { Pop-Location }

    if ($Verificar) { Restaurar; Write-Host "OK: el parche aplica ($($rutas.Count) archivos). No se modifico nada." -ForegroundColor Green; return }

    foreach ($r in $rutas) {
        $f = Join-Path $Carpeta ($r -replace '/', '\')
        if (-not (Test-Path $f)) { continue }   # el parche lo borra
        $b = [IO.File]::ReadAllBytes($f)
        if ($original.ContainsKey($r)) { $crlf = $original[$r].Crlf; $conBom = $original[$r].Bom } else { $crlf = $usaCrlf; $conBom = $false }
        if ($crlf) { $b = ACrlf $b $conBom } elseif ($conBom) { $b = ConBom $b }
        [IO.File]::WriteAllBytes($f, $b)
    }
    Write-Host "Parche aplicado: $($rutas.Count) archivos (formato de cada archivo conservado)." -ForegroundColor Green
} catch {
    Restaurar
    Write-Host "ERROR: $($_.Exception.Message) No se modifico nada." -ForegroundColor Red
    exit 1
}
