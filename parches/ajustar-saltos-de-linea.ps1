<#
  Deja cada archivo modificado de un fork con los MISMOS saltos de linea (CRLF o LF) que tiene en el commit base, para que
  "git diff" muestre solo los cambios reales y no archivos enteros reescritos.

  Por defecto solo MUESTRA lo que haria. Con -Aplicar escribe los archivos.

  Uso (desde cualquier carpeta):
    .\ajustar-saltos-de-linea.ps1 -Repo C:\ruta\al\fork -Base afa4e60                 # solo mira
    .\ajustar-saltos-de-linea.ps1 -Repo C:\ruta\al\fork -Base afa4e60 -Aplicar        # corrige
  Despues, agregar SIN conversion:  git -c core.autocrlf=false add -A BackEnd FrontEnd .gitignore
#>
param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$Base,
    [switch]$Aplicar
)
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path $Repo).Path

function EjecutarGit([string[]]$argumentos) {
    $salida = & git.exe -C $Repo @argumentos
    if ($LASTEXITCODE -ne 0) { throw "git $($argumentos -join ' ') fallo." }
    return $salida
}
# Bytes exactos del archivo en el commit base (sin pasar por la consola, que cambiaria los saltos de linea).
function BytesDelCommit([string]$ruta) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git.exe'
    $psi.Arguments = "-C `"$Repo`" cat-file blob ${Base}:$ruta"
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $ms = New-Object System.IO.MemoryStream
    $p.StandardOutput.BaseStream.CopyTo($ms)
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) { return $null }
    return , $ms.ToArray()
}
function ConCrlf([byte[]]$b) { for ($i = 0; $i -lt $b.Length - 1; $i++) { if ($b[$i] -eq 13 -and $b[$i + 1] -eq 10) { return $true } }; return $false }
function ConBom([byte[]]$b) { return ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) }
# Pasa a LF, sin BOM
function ALf([byte[]]$b) {
    $o = New-Object System.Collections.Generic.List[byte] ($b.Length)
    $desde = if (ConBom $b) { 3 } else { 0 }
    for ($i = $desde; $i -lt $b.Length; $i++) { if ($b[$i] -eq 13 -and $i + 1 -lt $b.Length -and $b[$i + 1] -eq 10) { continue }; $o.Add($b[$i]) }
    return , $o.ToArray()
}
function Formato([byte[]]$lf, [bool]$crlf, [bool]$bom) {
    $o = New-Object System.Collections.Generic.List[byte] ($lf.Length + 4096)
    if ($bom) { $o.Add(0xEF); $o.Add(0xBB); $o.Add(0xBF) }
    foreach ($x in $lf) { if ($crlf -and $x -eq 10) { $o.Add(13) }; $o.Add($x) }
    return , $o.ToArray()
}

$modificados = @(EjecutarGit @('diff', '--name-only', '--diff-filter=M', $Base))
$nuevos = @(EjecutarGit @('diff', '--name-only', '--diff-filter=A', $Base))
$cambiados = 0
foreach ($ruta in $modificados) {
    $actual = Join-Path $Repo ($ruta -replace '/', '\')
    if (-not (Test-Path $actual)) { continue }
    $original = BytesDelCommit $ruta
    if ($null -eq $original) { continue }
    $ref = @{ Crlf = (ConCrlf $original); Bom = (ConBom $original) }
    $bytes = [System.IO.File]::ReadAllBytes($actual)
    $nuevo = Formato (ALf $bytes) $ref.Crlf $ref.Bom
    $igual = ($nuevo.Length -eq $bytes.Length)
    if ($igual) { for ($i = 0; $i -lt $bytes.Length; $i++) { if ($nuevo[$i] -ne $bytes[$i]) { $igual = $false; break } } }
    $estado = if ($igual) { 'ya estaba bien' } else { 'se corrige' }
    Write-Host ("{0,-15} {1}  (repo: {2}{3})" -f $estado, $ruta, $(if ($ref.Crlf) { 'CRLF' } else { 'LF' }), $(if ($ref.Bom) { ' + BOM' } else { '' }))
    if (-not $igual) { $cambiados++; if ($Aplicar) { [System.IO.File]::WriteAllBytes($actual, $nuevo) } }
}
# Los archivos nuevos toman el formato mas comun del repo (el de los archivos .cs que ya existian en el commit base).
$crlfs = 0; $total = 0
foreach ($ruta in ($modificados | Where-Object { $_ -like '*.cs' } | Select-Object -First 15)) { $o = BytesDelCommit $ruta; if ($o) { $total++; if (ConCrlf $o) { $crlfs++ } } }
$nuevoEsCrlf = ($total -gt 0 -and $crlfs -gt ($total / 2))
foreach ($ruta in $nuevos) {
    $actual = Join-Path $Repo ($ruta -replace '/', '\')
    if (-not (Test-Path $actual)) { continue }
    $bytes = [System.IO.File]::ReadAllBytes($actual)
    $nuevo = Formato (ALf $bytes) $nuevoEsCrlf $false
    $igual = ($nuevo.Length -eq $bytes.Length)
    if ($igual) { for ($i = 0; $i -lt $bytes.Length; $i++) { if ($nuevo[$i] -ne $bytes[$i]) { $igual = $false; break } } }
    Write-Host ("{0,-15} {1}  (nuevo: {2})" -f $(if ($igual) { 'ya estaba bien' } else { 'se corrige' }), $ruta, $(if ($nuevoEsCrlf) { 'CRLF' } else { 'LF' }))
    if (-not $igual) { $cambiados++; if ($Aplicar) { [System.IO.File]::WriteAllBytes($actual, $nuevo) } }
}
# Verificacion: se vuelve a leer cada archivo y se comprueba que quedo con el formato esperado.
if ($Aplicar) {
    $mal = 0
    foreach ($ruta in ($modificados + $nuevos)) {
        $f = Join-Path $Repo ($ruta -replace '/', '\')
        if (-not (Test-Path $f)) { continue }
        $b = [System.IO.File]::ReadAllBytes($f)
        $esperaCrlf = if ($modificados -contains $ruta) { (ConCrlf (BytesDelCommit $ruta)) } else { $nuevoEsCrlf }
        if ((ConCrlf $b) -ne $esperaCrlf) { $mal++; Write-Host "NO QUEDO BIEN: $ruta" -ForegroundColor Red }
    }
    if ($mal -eq 0) { Write-Host 'Verificado: todos los archivos quedaron con el formato del repo.' -ForegroundColor Green } else { Write-Host "$mal archivos no quedaron bien." -ForegroundColor Red }
}
Write-Host ''
if ($Aplicar) { Write-Host "Listo: $cambiados archivos corregidos. Ahora: git -c core.autocrlf=false add -A BackEnd FrontEnd .gitignore" -ForegroundColor Green }
else { Write-Host "Se corregirian $cambiados archivos. Para hacerlo, repetir con -Aplicar." -ForegroundColor Yellow }
