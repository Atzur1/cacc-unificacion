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
$alta = @{ dni = '41000001'; nombre = 'Juan'; apellido = 'Perez'; fechaNacimiento = '2010-05-05'; genero = 'Masculino'; categoria = '3'; posicion = 'Delantero'; clubOrigen = 'Club X'; aptoFisico = $true
    tutor = @{ dni = '20000001'; nombre = 'Marta'; apellido = 'Perez'; telefono = '3511234567'; email = 'marta@ejemplo.com'; parentesco = 'Madre' } }
$r = Call 'POST' "$B/api/jugadores" $T $alta; Chk 'Flujo' 'el Deportivo da de alta un jugador con tutor' ($r.s -in 200, 201) "HTTP $($r.s) $($r.b)"
$id = [int](SQ "SELECT j.PK_id_jugador FROM JUGADORES j JOIN PERSONAS p ON p.PK_id_persona = j.FK_id_persona WHERE p.dni = '41000001'")
Chk 'Flujo' 'quedan creados jugador, historial de permanencia y vinculo con el tutor' ($id -gt 0 -and (SQ "SELECT CAST((SELECT COUNT(*) FROM JUGADORES_PERIODOS WHERE FK_id_jugador=$id) AS varchar)+'/'+CAST((SELECT COUNT(*) FROM JUGADORES_RESPONSABLES WHERE FK_id_jugador=$id) AS varchar)") -eq '1/1') "jugador #$id"
$r = Call 'GET' "$A/api/players/search?term=41000001" $T; Chk 'Flujo' 'el Administrativo encuentra al jugador cargado por el Deportivo' ($r.s -eq 200 -and $r.b -match 'Perez') "HTTP $($r.s)"
Chk 'Flujo' 'el alta del Deportivo guarda el genero y la categoria' ((SQ "SELECT genero+'/'+CAST(FK_id_categoria AS varchar) FROM JUGADORES j JOIN PERSONAS p ON p.PK_id_persona=j.FK_id_persona WHERE p.dni='41000001'") -eq 'Masculino/3') ''
# Genero y categoria son obligatorios: el servidor del Deportivo los exige (y la base los rechaza si faltan, venga de donde venga).
$r = Call 'POST' "$B/api/jugadores" $T @{ dni = '41000010'; nombre = 'Sin'; apellido = 'Genero'; fechaNacimiento = '2012-01-01'; categoria = '3' }; Chk 'Obligatorios' 'el Deportivo rechaza un alta sin genero' ($r.s -eq 400) "HTTP $($r.s) $($r.b)"
$r = Call 'POST' "$B/api/jugadores" $T @{ dni = '41000011'; nombre = 'Sin'; apellido = 'Categoria'; fechaNacimiento = '2012-01-01'; genero = 'Masculino' }; Chk 'Obligatorios' 'el Deportivo rechaza un alta sin categoria' ($r.s -eq 400) "HTTP $($r.s) $($r.b)"
Chk 'Obligatorios' 'ninguna de las altas incompletas dejo una persona o un jugador en la base' ((SQ "SELECT COUNT(*) FROM PERSONAS WHERE dni IN ('41000010','41000011')") -eq '0') ''
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

# ================= 2b. API DE ESTADO DE DEUDA (la fuente que el Deportivo va a consultar)
Write-Host '--- 2b. API de estado de deuda' -ForegroundColor Cyan
$r = Call 'GET' "$A/api/estado-deuda/dni/41000001" $T; $e = if ($r.s -eq 200) { $r.b | ConvertFrom-Json } else { $null }
Chk 'EstadoDeuda' 'consulta por DNI' ($r.s -eq 200 -and $e.estado -eq 'solo_entrenamientos' -and $e.accesoPermitido) "HTTP $($r.s) $($r.b)"
$vista = SQ "SELECT CAST(cantidad_cuotas_vencidas AS varchar)+'/'+CAST(CAST(deuda_total AS int) AS varchar) FROM VISTA_ESTADO_DEUDA WHERE FK_id_jugador=$id"
Chk 'EstadoDeuda' 'la API coincide con la vista provisoria (no se desalinean)' ($null -ne $e -and ("$($e.cuotasVencidas)/$([int]$e.deudaTotal)" -eq $vista)) "API=$($e.cuotasVencidas)/$([int]$e.deudaTotal) vista=$vista"
$r = Call 'GET' "$A/api/estado-deuda/dni/41.000.001" $T; Chk 'EstadoDeuda' 'acepta el DNI con puntos' ($r.s -eq 200) "HTTP $($r.s)"
$r = Call 'GET' "$A/api/estado-deuda/dni/10000001" $T; Chk 'EstadoDeuda' 'DNI que no es de un jugador: 404' ($r.s -eq 404) "HTTP $($r.s)"
$r = Call 'GET' "$A/api/estado-deuda/dni/abc" $T; Chk 'EstadoDeuda' 'DNI invalido: 400' ($r.s -eq 400) "HTTP $($r.s)"
$r = Call 'POST' "$A/api/estado-deuda/lote" $T @{ dnis = @('41.000.001', '10000001', 'xx') }; $l = if ($r.s -eq 200) { $r.b | ConvertFrom-Json } else { $null }
Chk 'EstadoDeuda' 'consulta por lote separa encontrados y no encontrados' ($r.s -eq 200 -and @($l.items).Count -eq 1 -and @($l.noEncontrados).Count -eq 2) "HTTP $($r.s) $($r.b)"
$r = Call 'GET' "$A/api/estado-deuda/dni/41000001" $null; Chk 'EstadoDeuda' 'sin token: 401' ($r.s -eq 401) "HTTP $($r.s)"
$r = Call 'GET' "$A/api/estado-deuda/dni/41000001" $TM; Chk 'EstadoDeuda' 'la Medica (solo Deportivo) puede consultar con su token' ($r.s -eq 200) "HTTP $($r.s)"
$r = Call 'GET' "$A/api/estado-deuda/dni/41000001" $TD; Chk 'EstadoDeuda' 'el DT de la categoria del jugador (3) puede consultar' ($r.s -eq 200) "HTTP $($r.s)"
# ================= 2c. INSCRIPCION POR GENERO (las mujeres hoy no pagan; el club puede empezar a cobrarla)
Write-Host '--- 2c. Inscripcion por genero' -ForegroundColor Cyan
$alta = { param($dni, $genero) Call 'POST' "$A/api/players" $T @{ firstName = 'Prueba'; lastName = "Insc$dni"; dni = $dni; birthDate = '2012-03-03'; gender = $genero; categoryId = 3 } }
$r = & $alta '42000001' 'Masculino'; Chk 'Inscripcion' 'sin arancel masculino vigente no hay alta de varones' ($r.s -ge 400 -and $r.s -lt 500) "HTTP $($r.s)"
$r = Call 'POST' "$A/api/enrollmentfees" $T @{ gender = 'Masculino'; amount = 70000; startDate = (& $f $hoy) }; Chk 'Inscripcion' 'se programa la inscripcion masculina' ($r.s -eq 201) "HTTP $($r.s) $($r.b)"
$r = & $alta '42000002' 'Femenino'; $j = if ($r.s -eq 201) { $r.b | ConvertFrom-Json } else { $null }
Chk 'Inscripcion' 'una mujer sin arancel femenino se da de alta sin inscripcion' ($r.s -eq 201 -and $null -eq $j.enrollmentFeeAmount) "HTTP $($r.s) inscripcion=$($j.enrollmentFeeAmount)"
$r = Call 'POST' "$A/api/enrollmentfees" $T @{ gender = 'Femenino'; amount = 30000; startDate = (& $f $hoy) }; Chk 'Inscripcion' 'el mismo dia se programa tambien la femenina (cada genero tiene su historia)' ($r.s -eq 201) "HTTP $($r.s) $($r.b)"
$r = Call 'POST' "$A/api/enrollmentfees" $T @{ gender = 'Femenino'; amount = 31000; startDate = (& $f $hoy) }; Chk 'Inscripcion' 'no se repite un arancel del mismo genero el mismo dia' ($r.s -eq 400) "HTTP $($r.s)"
$r = Call 'POST' "$A/api/enrollmentfees" $T @{ amount = 31000; startDate = (& $f $hoy.AddDays(1)) }; Chk 'Inscripcion' 'el genero es obligatorio' ($r.s -eq 400) "HTTP $($r.s)"
$r = & $alta '42000003' 'Femenino'; $j = if ($r.s -eq 201) { $r.b | ConvertFrom-Json } else { $null }
Chk 'Inscripcion' 'con arancel femenino vigente, la alta de una mujer paga la inscripcion femenina ($30.000)' ($r.s -eq 201 -and $j.enrollmentFeeAmount -eq 30000) "HTTP $($r.s) inscripcion=$($j.enrollmentFeeAmount)"
$r = & $alta '42000004' 'Masculino'; $j = if ($r.s -eq 201) { $r.b | ConvertFrom-Json } else { $null }
Chk 'Inscripcion' 'la alta de un varon sigue pagando la inscripcion masculina ($70.000)' ($r.s -eq 201 -and $j.enrollmentFeeAmount -eq 70000) "HTTP $($r.s) inscripcion=$($j.enrollmentFeeAmount)"
$r = Call 'GET' "$A/api/enrollmentfees" $T; $lista = if ($r.s -eq 200) { $r.b | ConvertFrom-Json } else { @() }
Chk 'Inscripcion' 'el historial trae el genero de cada arancel' ($r.s -eq 200 -and @($lista | Where-Object { $_.gender -eq 'Femenino' }).Count -ge 1 -and @($lista | Where-Object { $_.gender -eq 'Masculino' }).Count -ge 1) "HTTP $($r.s)"
$r = Call 'GET' "$A/api/enrollmentfees/current?gender=Femenino" $T; Chk 'Inscripcion' 'consulta del arancel vigente por genero' ($r.s -eq 200 -and ($r.b | ConvertFrom-Json).amount -eq 30000) "HTTP $($r.s)"
# $0 = deja de cobrarse: se programa para manana y hoy sigue vigente el de $30.000
$r = Call 'POST' "$A/api/enrollmentfees" $T @{ gender = 'Femenino'; amount = 0; startDate = (& $f $hoy.AddDays(1)) }; Chk 'Inscripcion' 'se puede programar $0 (ese genero deja de pagar inscripcion)' ($r.s -eq 201) "HTTP $($r.s) $($r.b)"
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
$r = Call 'POST' "$A/api/enrollmentfees" $TA @{ gender = 'Femenino'; amount = 1; startDate = (& $f $hoy.AddDays(5)) }; Chk 'Inscripcion' 'el Administrador (rol 2) no programa aranceles de inscripcion: 403' ($r.s -eq 403) "HTTP $($r.s)"
$r = Call 'GET' "$A/api/estado-deuda/dni/41000001" $TA; Chk 'EstadoDeuda' 'el Administrador (rol 2) no consulta el estado deportivo: 403' ($r.s -eq 403) "HTTP $($r.s)"
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
