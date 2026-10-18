<#
  Corre todas las pruebas contra las dos APIs ya levantadas (scripts\iniciar.ps1) y la base de prueba.
  Resultado de cada comprobacion:
    PASA  = funciona
    FALLA = error nuestro o de la base: hay que arreglarlo
    GAP   = problema CONOCIDO del codigo del otro equipo (ver docs\hallazgos-otro-equipo.md). No cuenta como falla;
            cuando el otro equipo aplique su parche, el GAP pasa solo a PASA.
  Termina con codigo 1 si hubo alguna FALLA.
#>
param(
    [string]$Servidor = 'localhost',
    [string]$Base = 'ClubCamionerosUnificadaV2_Prueba',
    [string]$Destino = '',
    [string]$Administrativo = 'http://localhost:5318',
    [string]$Deportivo = 'http://localhost:5319'
)
$ErrorActionPreference = 'Continue'
$raiz = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Destino) { $Destino = Join-Path $PSScriptRoot '..\trabajo' }
$Destino = (Resolve-Path $Destino).Path
$A = $Administrativo; $B = $Deportivo; $PW = 'Camioneros.Test.2026!'
$res = New-Object System.Collections.Generic.List[object]

function Call($m, $url, $tok, $body) {
    $h = @{}; if ($tok) { $h['Authorization'] = "Bearer $tok" }
    try {
        $p = @{ Method = $m; Uri = $url; Headers = $h; UseBasicParsing = $true; TimeoutSec = 90 }
        if ($body) { $p.Body = ($body | ConvertTo-Json -Depth 6); $p.ContentType = 'application/json; charset=utf-8' }
        $r = Invoke-WebRequest @p; return @{ s = [int]$r.StatusCode; b = [string]$r.Content }
    } catch {
        $s = 0; $b = ''
        if ($_.Exception.Response) { $s = [int]$_.Exception.Response.StatusCode; try { $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $b = $sr.ReadToEnd() } catch {} } else { $b = $_.Exception.Message }
        return @{ s = $s; b = $b }
    }
}
function SQ($q) { (sqlcmd -S $Servidor -E -C -I -h -1 -W -f 65001 -d $Base -Q "SET NOCOUNT ON; $q") -join ' ; ' }
function Corto($t, $n = 110) { if ($null -eq $t) { return '' }; $t = [string]$t; $t.Substring(0, [Math]::Min($n, $t.Length)) -replace '\s+', ' ' }
function Chk($g, $n, $ok, $d) { $res.Add([pscustomobject]@{ T = 'PASA'; G = $g; N = $n; Ok = [bool]$ok }) | Out-Null; $e = if ($ok) { 'PASA ' } else { 'FALLA' }; if (-not $ok) { $res[$res.Count - 1].T = 'FALLA' }; Write-Host ("{0} | {1} | {2} | {3}" -f $e, $g, $n, (Corto $d)) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' }) }
function Gap($g, $n, $ok, $d) { $t = if ($ok) { 'PASA' } else { 'GAP' }; $res.Add([pscustomobject]@{ T = $t; G = $g; N = $n; Ok = [bool]$ok }) | Out-Null; $e = if ($ok) { 'PASA ' } else { 'GAP  ' }; Write-Host ("{0} | {1} | {2} | {3}" -f $e, $g, $n, (Corto $d)) -ForegroundColor $(if ($ok) { 'Green' } else { 'Yellow' }) }
function Login($dni, $clave = $PW) { $r = Call 'POST' "$A/api/auth/login" $null @{ username = $dni; password = $clave }; if ($r.s -eq 200) { return ($r.b | ConvertFrom-Json).token }; return $null }
function ReiniciarNuestro {
    Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'ApiGestion\.(csproj|dll|exe)' -and $_.Name -match '^(dotnet|ApiGestion)(\.exe)?$' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep 3
    $env:ASPNETCORE_ENVIRONMENT = 'Development'
    Start-Process dotnet -ArgumentList "run --project `"$Destino\nuestro\ApiGestion\ApiGestion.csproj`" --no-build --urls $A" -RedirectStandardOutput "$Destino\log_nuestro.txt" -RedirectStandardError "$Destino\log_nuestro_err.txt" -WindowStyle Hidden
    $limite = (Get-Date).AddSeconds(90)
    do { Start-Sleep 2; $listo = (Test-Path "$Destino\log_nuestro.txt") -and ((Get-Content "$Destino\log_nuestro.txt" -Raw -ErrorAction SilentlyContinue) -match 'Cuotas del mes') } while (-not $listo -and (Get-Date) -lt $limite)
}

# Las pruebas de la base consumen ids de las secuencias (los datos se revierten, los numeros no): se las deja en el maximo + 1.
function Secuencias {
    $mp = [int](SQ "SELECT ISNULL(MAX(PK_id_pago),0)+1 FROM PAGOS"); $mj = [int](SQ "SELECT ISNULL(MAX(PK_id_jugador),0)+1 FROM JUGADORES")
    sqlcmd -S $Servidor -E -C -I -d $Base -Q "ALTER SEQUENCE dbo.SEQ_PAGOS RESTART WITH $mp; ALTER SEQUENCE dbo.SEQ_JUGADORES RESTART WITH $mj;" | Out-Null
}
# ---- fechas del club (hora argentina)
$hoy = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, 'Argentina Standard Time').Date
$ultimo = if ($hoy.Day -ge 10) { Get-Date -Year $hoy.Year -Month $hoy.Month -Day 1 } else { (Get-Date -Year $hoy.Year -Month $hoy.Month -Day 1).AddMonths(-1) }
$ultimo = $ultimo.Date                    # ultimo periodo cuya cuota ya se emite
$p1 = $ultimo.AddMonths(-1); $p2 = $ultimo.AddMonths(-2)   # siempre vencidos hoy
$f = { param($d) $d.ToString('yyyy-MM-dd') }
Write-Host "Hoy (Argentina): $(& $f $hoy). Ultimo periodo emitible: $(& $f $ultimo). Periodos vencidos de prueba: $(& $f $p1) y $(& $f $p2).`n"

# ================= 0. LA BASE (con datos de prueba que se revierten)
Write-Host '--- 0. La base' -ForegroundColor Cyan
Secuencias
$salida = sqlcmd -S $Servidor -E -C -I -h -1 -W -f 65001 -d $Base -i (Join-Path $raiz 'pruebas\base-de-datos.sql') 2>&1
$fallos = @($salida | Where-Object { $_ -match 'FALLO|^Msg ' })
$oks = @($salida | Where-Object { $_ -match '^T\d+b? ok|^T\d' }).Count
Chk 'Base' 'restricciones, secuencias, historial de permanencias, vista de deuda y auditoria' ($fallos.Count -eq 0 -and $oks -ge 10 -and (($salida -join " ") -match "deuda=200000\.0+ vencidas=2")) "$oks verificaciones; $($fallos.Count) errores $($fallos -join ' ')"
Secuencias

# ================= 1. LOGIN UNICO Y PERMISOS
Write-Host '--- 1. Login unico y permisos' -ForegroundColor Cyan
$T = Login '20111222'; $TM = Login '30000003'; $TD = Login '30000004'
Chk 'Login' 'SuperAdmin entra por DNI' ($null -ne $T) ''
Chk 'Login' 'Medica (solo Deportivo) tambien entra con el mismo login' ($null -ne $TM) ''
Chk 'Login' 'Director Tecnico (solo Deportivo) entra' ($null -ne $TD) ''
$r = Call 'POST' "$A/api/auth/login" $null @{ username = '20111222'; password = 'incorrecta' }; Chk 'Login' 'contrasena incorrecta rechazada' ($r.s -eq 401) "HTTP $($r.s)"
$r = Call 'GET' "$A/api/usuarios/candidatos" $T; Chk 'Permisos' 'SuperAdmin ve los candidatos a habilitar (Ana)' ($r.s -eq 200 -and $r.b -match 'Administrativa') "HTTP $($r.s) $($r.b)"
$r = Call 'GET' "$B/api/categorias" $T; Chk 'Permisos' 'el Deportivo acepta el token del Administrativo' ($r.s -eq 200) "HTTP $($r.s)"
$r = Call 'GET' "$A/api/usuarios/candidatos" $TM; Chk 'Permisos' 'la Medica NO entra al Administrativo' ($r.s -eq 403) "HTTP $($r.s)"
$r = Call 'GET' "$B/api/categorias" $TM; Chk 'Permisos' 'la Medica SI lee en el Deportivo' ($r.s -eq 200) "HTTP $($r.s)"
$r = Call 'POST' "$B/api/jugadores" $TM @{ dni = '41999999'; nombre = 'X'; apellido = 'Y'; categoria = '3' }; Chk 'Permisos' 'la Medica no puede dar altas' ($r.s -eq 403) "HTTP $($r.s)"
$r = Call 'GET' "$B/api/categorias/3/jugadores" $TD; Chk 'Permisos' 'el DT lee su categoria' ($r.s -eq 200) "HTTP $($r.s)"
$r = Call 'GET' "$B/api/categorias/5/jugadores" $TD; Chk 'Permisos' 'el DT no lee otra categoria' ($r.s -in 401, 403) "HTTP $($r.s)"

# ================= 2. FLUJO ENTRE LOS DOS SISTEMAS
Write-Host '--- 2. Flujo: alta en el Deportivo -> cuota y cobro en el Administrativo -> QR' -ForegroundColor Cyan
$r = Call 'POST' "$A/api/aranceles/programar" $T @{ genero = 'Masculino'; monto = 85000; vigenteDesde = (& $f $hoy) }; Chk 'Flujo' 'arancel masculino programado' ($r.s -eq 200) "HTTP $($r.s) $($r.b)"
$r = Call 'POST' "$A/api/aranceles/programar" $T @{ genero = 'Femenino'; monto = 70000; vigenteDesde = (& $f $hoy) }; Chk 'Flujo' 'arancel femenino programado' ($r.s -eq 200) "HTTP $($r.s)"
$alta = @{ dni = '41000001'; nombre = 'Juan'; apellido = 'Perez'; fechaNacimiento = '2010-05-05'; categoria = '3'; posicion = 'Delantero'; clubOrigen = 'Club X'; aptoFisico = $true
    tutor = @{ dni = '20000001'; nombre = 'Marta'; apellido = 'Perez'; telefono = '3511234567'; email = 'marta@ejemplo.com'; parentesco = 'Madre' } }
$r = Call 'POST' "$B/api/jugadores" $T $alta; Chk 'Flujo' 'el Deportivo da de alta un jugador con tutor' ($r.s -in 200, 201) "HTTP $($r.s) $($r.b)"
$id = [int](SQ "SELECT j.PK_id_jugador FROM JUGADORES j JOIN PERSONAS p ON p.PK_id_persona = j.FK_id_persona WHERE p.dni = '41000001'")
Chk 'Flujo' 'quedan creados jugador, historial de permanencia y vinculo con el tutor' ($id -gt 0 -and (SQ "SELECT CAST((SELECT COUNT(*) FROM JUGADORES_PERIODOS WHERE FK_id_jugador=$id) AS varchar)+'/'+CAST((SELECT COUNT(*) FROM JUGADORES_RESPONSABLES WHERE FK_id_jugador=$id) AS varchar)") -eq '1/1') "jugador #$id"
$r = Call 'GET' "$A/api/players/search?term=41000001" $T; Chk 'Flujo' 'el Administrativo encuentra al jugador cargado por el Deportivo' ($r.s -eq 200 -and $r.b -match 'Perez') "HTTP $($r.s)"
Gap 'Flujo' 'el alta del Deportivo guarda el genero (sin genero no hay cuota)' ((SQ "SELECT genero FROM PERSONAS WHERE dni='41000001'") -notmatch 'NULL') "genero=$(SQ "SELECT ISNULL(genero,'NULL') FROM PERSONAS WHERE dni='41000001'")"
SQ "UPDATE PERSONAS SET genero='Masculino' WHERE dni='41000001'" | Out-Null   # lo que haria el formulario corregido
ReiniciarNuestro   # el generador de cuotas corre al iniciar y cada 6 horas
$T = Login '20111222'
$cuotas = [int](SQ "SELECT COUNT(*) FROM PAGOS WHERE FK_id_jugador=$id AND concepto='Cuota' AND fecha_vencimiento='$(& $f $ultimo)' AND estado=0 AND monto_final=85000")
if ($hoy.Day -ge 10) { Chk 'Flujo' 'el generador emite la cuota del mes ($85.000) del jugador cargado por el Deportivo' ($cuotas -eq 1) "cuotas=$cuotas" }
else { Chk 'Flujo' 'antes del dia 10 no se emite la cuota del mes en curso (regla del club)' ($cuotas -eq 0) "cuotas=$cuotas" }
$r = Call 'POST' "$B/api/asistencias/verificar-y-registrar" $T @{ dni = '41000001' }; $j = $r.b | ConvertFrom-Json
Chk 'QR' '0 cuotas vencidas: acceso permitido y asistencia registrada' ($r.s -eq 200 -and $j.accesoPermitido -and $j.cuotasVencidas -eq 0 -and $j.asistenciaRegistrada) "vencidas=$($j.cuotasVencidas) deuda=$($j.deudaTotal) $($j.mensaje)"
$r = Call 'POST' "$B/api/asistencias/verificar-y-registrar" $T @{ dni = '41000001' }; $j = $r.b | ConvertFrom-Json; Chk 'QR' 'segundo escaneo del dia: ya registrada' ($j.yaRegistrada) $j.mensaje
SQ "INSERT PAGOS(FK_id_jugador,monto_base,monto_final,fecha_vencimiento,estado,concepto) VALUES ($id,85000,85000,'$(& $f $p1)',0,'Cuota'),($id,85000,85000,'$(& $f $p2)',0,'Cuota')" | Out-Null
SQ "DELETE FROM ASISTENCIAS WHERE FK_id_jugador=$id" | Out-Null
$r = Call 'POST' "$B/api/asistencias/verificar-y-registrar" $T @{ dni = '41000001' }; $j = $r.b | ConvertFrom-Json
Chk 'QR' '2 cuotas vencidas: acceso denegado' ($j.cuotasVencidas -eq 2 -and -not $j.accesoPermitido) "vencidas=$($j.cuotasVencidas) deuda=$($j.deudaTotal) $($j.mensaje)"
$idPago = [int](SQ "SELECT PK_id_pago FROM PAGOS WHERE FK_id_jugador=$id AND fecha_vencimiento='$(& $f $p2)' AND estado=0")
$r = Call 'POST' "$A/api/pagos/cobro" $T @{ idJugador = $id; idsPago = @($idPago); metodoPago = 'Efectivo' }; Chk 'Flujo' 'se cobra la cuota mas vieja en el Administrativo' ($r.s -eq 200) "HTTP $($r.s)"
$r = Call 'POST' "$B/api/asistencias/verificar-y-registrar" $T @{ dni = '41000001' }; $j = $r.b | ConvertFrom-Json
Chk 'QR' 'tras el cobro queda 1 vencida: permitido (solo entrenamientos)' ($j.cuotasVencidas -eq 1 -and $j.accesoPermitido) "vencidas=$($j.cuotasVencidas) deuda=$($j.deudaTotal) $($j.mensaje)"
$r = Call 'POST' "$A/api/jugadores/$id/baja" $T @{ fecha = (& $f $hoy) }; Chk 'Flujo' 'baja del jugador desde el Administrativo' ($r.s -eq 200) "HTTP $($r.s)"
Chk 'Flujo' 'la baja marca activo=0 y cierra el periodo de permanencia' ((SQ "SELECT CAST(activo AS varchar)+'/'+CAST((SELECT COUNT(*) FROM JUGADORES_PERIODOS WHERE FK_id_jugador=$id AND fecha_baja IS NOT NULL) AS varchar) FROM JUGADORES WHERE PK_id_jugador=$id") -eq '0/1') ''
$r = Call 'GET' "$B/api/jugadores" $T; Gap 'Bajas' 'el listado del Deportivo no muestra a los jugadores dados de baja' ($r.b -notmatch '41000001') "HTTP $($r.s)"
SQ "DELETE FROM ASISTENCIAS WHERE FK_id_jugador=$id" | Out-Null
$r = Call 'POST' "$B/api/asistencias/verificar-y-registrar" $T @{ dni = '41000001' }; $j = $r.b | ConvertFrom-Json; Gap 'Bajas' 'el QR no deja entrar a un jugador dado de baja' (-not $j.accesoPermitido) "accesoPermitido=$($j.accesoPermitido) $($j.mensaje)"
$r = Call 'POST' "$A/api/jugadores/$id/reactivar" $T; Chk 'Flujo' 'reingreso desde el Administrativo' ($r.s -eq 200) "HTTP $($r.s)"
Chk 'Flujo' 'el reingreso abre un periodo nuevo y conserva el anterior' ((SQ "SELECT CAST((SELECT COUNT(*) FROM JUGADORES_PERIODOS WHERE FK_id_jugador=$id) AS varchar)+'/'+CAST((SELECT COUNT(*) FROM JUGADORES_PERIODOS WHERE FK_id_jugador=$id AND fecha_baja IS NULL) AS varchar)") -eq '2/1') ''
Gap 'Auditoria' 'lo que escribe el Deportivo queda con responsable' ([int](SQ "SELECT COUNT(*) FROM AUDITORIA_CAMBIOS WHERE entidad='JUGADORES' AND accion='INSERT' AND id_entidad='$id' AND id_usuario IS NOT NULL") -ge 1) 'alta de jugador por el Deportivo'
Chk 'Auditoria' 'lo que escribe el Administrativo queda con responsable' ([int](SQ "SELECT COUNT(*) FROM AUDITORIA_CAMBIOS WHERE entidad='PAGOS' AND accion='UPDATE' AND id_usuario IS NOT NULL") -ge 1) 'cobro'

# ================= 3. BARRIDO DE LECTURAS DEL ADMINISTRATIVO
Write-Host '--- 3. Barrido de lecturas del Administrativo' -ForegroundColor Cyan
$rutas = @('/api/aranceles/historial', '/api/aranceles/resumen', '/api/auditoria/cambios', '/api/categorias', '/api/cuotas-faltantes', '/api/estadisticas/resumen-general', '/api/enrollmentfees',
    '/api/jugadores', "/api/jugadores/$id", "/api/jugadores/$id/historial-pagos", '/api/pagos/resumen', '/api/pagos/pendientes', '/api/pagos/player-accounts', "/api/pagos/deuda-por-categoria?anio=$($hoy.Year)",
    '/api/pagos/recientes', '/api/pagos/resumen-hoy', '/api/pagos/registrados', "/api/pagos/deuda/$id", "/api/pagos/cuotas/$id", "/api/pagos/jugador/$id/estado-de-cuenta", '/api/players/search?term=Perez',
    '/api/players/discounts', '/api/players/discounts/all', '/api/players/discounts/types', "/api/players/$id/discounts", "/api/players/$id/discount/first-period",
    '/api/usuarios/candidatos', '/api/usuarios/habilitados', '/api/usuarios/deshabilitados', '/api/reportes/deudores/csv', '/api/reportes/deudores/pdf', '/api/reportes/pagos-recientes/csv',
    '/api/reportes/pagos-recientes/pdf', '/api/reportes/becados/csv', '/api/reportes/becados/pdf', '/api/reportes/aranceles/csv', '/api/reportes/aranceles/pdf')
$malas = @(); foreach ($u in $rutas) { $r = Call 'GET' "$A$u" $T; if ($r.s -ne 200) { $malas += "HTTP $($r.s) $u" } }
Chk 'Lecturas' "$($rutas.Count) lecturas del Administrativo responden bien" ($malas.Count -eq 0) ($malas -join ' | ')
$r = Call 'GET' "$A/api/auditoria/cambios" $T; Chk 'Lecturas' 'la auditoria muestra nombre y DNI del operador (desde PERSONAS)' ($r.b -match '"userDni":"20111222"') ''

# ================= 4. HABILITAR UNA CUENTA NUEVA
Write-Host '--- 4. Habilitar una cuenta nueva (Ana)' -ForegroundColor Cyan
$ana = [int](SQ "SELECT PK_id_usuario FROM USUARIOS WHERE email='ana.prueba@ejemplo.com'")
$r = Call 'POST' "$A/api/usuarios/$ana/habilitar" $T @{ email = 'ana.prueba@ejemplo.com'; rolPortal = 2 }; Chk 'Cuentas' 'el SuperAdmin habilita a Ana como Administradora' ($r.s -eq 200) "HTTP $($r.s)"
Start-Sleep 2
$linea = (Select-String -Path "$Destino\log_nuestro.txt" -Pattern 'token=' -ErrorAction SilentlyContinue | Select-Object -Last 1).Line
$tk = if ($linea) { [regex]::Match($linea, 'token=(\S+)').Groups[1].Value } else { '' }
Chk 'Cuentas' 'se genera el enlace de activacion' ($tk.Length -gt 20) ''
$r = Call 'POST' "$A/api/auth/account-access/complete" $null @{ token = $tk; password = 'Ana-Camioneros-7731' }; Chk 'Cuentas' 'la politica rechaza una clave con el nombre de la persona' ($r.s -eq 400) "HTTP $($r.s)"
$r = Call 'POST' "$A/api/auth/account-access/complete" $null @{ token = $tk; password = 'Camioneros-Club-7731' }; Chk 'Cuentas' 'Ana crea su contrasena con el enlace' ($r.s -eq 200) "HTTP $($r.s)"
$TA = Login '30000002' 'Camioneros-Club-7731'; Chk 'Cuentas' 'Ana entra por DNI' ($null -ne $TA) ''
$r = Call 'GET' "$A/api/pagos/resumen" $TA; Chk 'Cuentas' 'Ana (rol 2) trabaja en el Administrativo' ($r.s -eq 200) "HTTP $($r.s)"
$r = Call 'GET' "$A/api/auditoria/cambios" $TA; Chk 'Cuentas' 'Ana no ve Auditoria (solo SuperAdmin)' ($r.s -eq 403) "HTTP $($r.s)"
$r = Call 'GET' "$B/api/jugadores" $TA; Chk 'Cuentas' 'Ana (solo Administrativo) no entra al Deportivo' ($r.s -in 401, 403) "HTTP $($r.s)"
$claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($TA.Split('.')[1].Replace('-', '+').Replace('_', '/') + ('=' * ((4 - $TA.Split('.')[1].Length % 4) % 4)))))
Chk 'Cuentas' 'el token del Administrador (rol 2) no lleva permisos del Deportivo' ($claims -notmatch '"id_rol"') (Corto $claims 80)

# ================= 5. CIERRE DE SESION
Write-Host '--- 5. Cierre de sesion' -ForegroundColor Cyan
$TM = Login '30000003'
$r = Call 'POST' "$A/api/auth/logout" $TM; Chk 'Sesion' 'logout en el Administrativo' ($r.s -eq 204) "HTTP $($r.s)"
$r = Call 'GET' "$A/api/categorias" $TM; Chk 'Sesion' 'el token ya no sirve en el Administrativo' ($r.s -eq 401) "HTTP $($r.s)"
$r = Call 'GET' "$B/api/categorias" $TM; Gap 'Sesion' 'el token tampoco sirve en el Deportivo' ($r.s -eq 401) "HTTP $($r.s)"

# ================= RESUMEN
$pasa = @($res | Where-Object T -eq 'PASA').Count; $falla = @($res | Where-Object T -eq 'FALLA').Count; $gap = @($res | Where-Object T -eq 'GAP').Count
Write-Host "`n=== RESUMEN: $pasa PASAN | $falla FALLAN | $gap GAP (pendientes del otro equipo)" -ForegroundColor $(if ($falla) { 'Red' } else { 'Green' })
$res | ForEach-Object { "{0,-5} | {1} | {2}" -f $_.T, $_.G, $_.N } | Set-Content "$Destino\resultado.txt" -Encoding UTF8
if ($falla) { exit 1 }
