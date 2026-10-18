SET NOCOUNT ON; SET XACT_ABORT OFF;
BEGIN TRAN;
-- 1. secuencias y alta de jugador + historial de periodos
INSERT PERSONAS(nombre,apellido,dni,genero) VALUES (N'Test',N'Uno','90000001','Masculino'); DECLARE @pa INT=SCOPE_IDENTITY();
INSERT PERSONAS(nombre,apellido,dni,genero) VALUES (N'Test',N'Dos','90000002','Femenino');  DECLARE @pb INT=SCOPE_IDENTITY();
INSERT JUGADORES(FK_id_persona,FK_id_categoria,fecha_alta) VALUES (@pa,3,'2026-01-01');
DECLARE @a INT=(SELECT PK_id_jugador FROM JUGADORES WHERE FK_id_persona=@pa);
SELECT 'T1 id por secuencia='+CAST(@a AS varchar)+' activo='+CAST((SELECT activo FROM JUGADORES WHERE PK_id_jugador=@a) AS varchar)+' periodos='+CAST((SELECT COUNT(*) FROM JUGADORES_PERIODOS WHERE FK_id_jugador=@a) AS varchar);
UPDATE JUGADORES SET fecha_baja='2026-02-28' WHERE PK_id_jugador=@a;
SELECT 'T2 baja: activo='+CAST((SELECT activo FROM JUGADORES WHERE PK_id_jugador=@a) AS varchar)+' periodo cerrado='+CONVERT(varchar,(SELECT fecha_baja FROM JUGADORES_PERIODOS WHERE FK_id_jugador=@a));
UPDATE JUGADORES SET fecha_baja=NULL, fecha_alta='2026-08-01' WHERE PK_id_jugador=@a;
SELECT 'T3 reingreso: periodos='+CAST((SELECT COUNT(*) FROM JUGADORES_PERIODOS WHERE FK_id_jugador=@a) AS varchar)+' abiertos='+CAST((SELECT COUNT(*) FROM JUGADORES_PERIODOS WHERE FK_id_jugador=@a AND fecha_baja IS NULL) AS varchar);
UPDATE JUGADORES SET fecha_alta='2026-08-05' WHERE PK_id_jugador=@a;
SELECT 'T4 correccion alta: '+(SELECT STRING_AGG(CONVERT(varchar,fecha_alta)+'->'+ISNULL(CONVERT(varchar,fecha_baja),'abierto'),' | ') FROM JUGADORES_PERIODOS WHERE FK_id_jugador=@a);
-- jugador cargado ya dado de baja (importacion de historicos)
INSERT JUGADORES(FK_id_persona,FK_id_categoria,fecha_alta,fecha_baja) VALUES (@pb,13,'2026-03-01','2026-07-31');
DECLARE @b INT=(SELECT PK_id_jugador FROM JUGADORES WHERE FK_id_persona=@pb);
SELECT 'T5 insert con baja: activo='+CAST((SELECT activo FROM JUGADORES WHERE PK_id_jugador=@b) AS varchar)+' periodos abiertos='+CAST((SELECT COUNT(*) FROM JUGADORES_PERIODOS WHERE FK_id_jugador=@b AND fecha_baja IS NULL) AS varchar);
-- 2. vista de deuda (hoy AR = ver abajo)
DECLARE @hoy DATE=CAST(SYSDATETIMEOFFSET() AT TIME ZONE 'Argentina Standard Time' AS DATE); PRINT 'hoy AR='+CONVERT(varchar,@hoy);
DECLARE @ult DATE = CASE WHEN DAY(@hoy)>=10 THEN DATEFROMPARTS(YEAR(@hoy),MONTH(@hoy),1) ELSE DATEADD(MONTH,-1,DATEFROMPARTS(YEAR(@hoy),MONTH(@hoy),1)) END;
DECLARE @mesA DATE = DATEADD(MONTH,-2,@ult), @mesS DATE = DATEADD(MONTH,-1,@ult), @mesO DATE = @ult;
INSERT TIPOS_DESCUENTO(tipo_descuento) VALUES (N'TestBeca'); DECLARE @t INT=SCOPE_IDENTITY();
INSERT JUGADORES_DESCUENTOS(FK_id_jugador,FK_id_descuento,tipo_valor,porcentaje,fecha_inicio,fecha_fin) VALUES (@a,@t,'%',50,@mesS,EOMONTH(@mesS)); DECLARE @d1 INT=SCOPE_IDENTITY();
INSERT JUGADORES_DESCUENTOS(FK_id_jugador,FK_id_descuento,tipo_valor,porcentaje,fecha_inicio,fecha_fin) VALUES (@a,@t,'%',100,@mesO,EOMONTH(@mesO));
INSERT PAGOS(FK_id_jugador,monto_base,monto_final,fecha_vencimiento,estado,concepto) VALUES (@a,100000,80000,@mesA,0,'Cuota');   -- agosto: abono de 20000
INSERT PAGOS(FK_id_jugador,monto_base,monto_final,fecha_pago,metodo_pago,fecha_vencimiento,estado,concepto) VALUES (@a,100000,20000,@hoy,'Efectivo',@mesA,1,'Cuota');
INSERT PAGOS(FK_id_jugador,monto_base,monto_final,fecha_vencimiento,estado,concepto) VALUES (@a,100000,100000,@mesS,0,'Cuota');  -- sep: beca 50%
INSERT PAGOS(FK_id_jugador,monto_base,monto_final,fecha_vencimiento,estado,concepto) VALUES (@a,100000,100000,@mesO,0,'Cuota');  -- oct: beca 100%, no vence aun
INSERT PAGOS(FK_id_jugador,monto_base,monto_final,fecha_vencimiento,estado,concepto) VALUES (@a,70000,70000,@mesA,0,'Inscripcion');
SELECT 'T6 vista (esperado deuda=80000+50000+0+70000=200000, vencidas=2): '+(SELECT 'deuda='+CAST(deuda_total AS varchar)+' vencidas='+CAST(cantidad_cuotas_vencidas AS varchar) FROM VISTA_ESTADO_DEUDA WHERE FK_id_jugador=@a);
SELECT 'T6b jugador sin deuda no aparece: '+CAST((SELECT COUNT(*) FROM VISTA_ESTADO_DEUDA WHERE FK_id_jugador=@b) AS varchar);
-- 3. un solo pendiente por cuota
BEGIN TRY INSERT PAGOS(FK_id_jugador,monto_base,monto_final,fecha_vencimiento,estado,concepto) VALUES (@a,1,1,@mesS,0,'Cuota'); PRINT 'T7 FALLO: dejo duplicar la cuota pendiente'; END TRY BEGIN CATCH PRINT 'T7 ok duplicado rechazado'; END CATCH
-- 4. inscripcion por genero
BEGIN TRY INSERT ARANCELES_INSCRIPCION(monto,vigente_desde) VALUES (70000,'2026-10-01'); PRINT 'T8b FALLO: dejo cargar un arancel de inscripcion sin genero'; END TRY BEGIN CATCH PRINT 'T8b ok: un arancel de inscripcion sin genero se rechaza'; END CATCH
INSERT ARANCELES_INSCRIPCION(monto,vigente_desde,genero) VALUES (0,'2026-10-01','Femenino');
INSERT ARANCELES_INSCRIPCION(monto,vigente_desde,genero) VALUES (70000,'2026-10-01','Masculino');
BEGIN TRY INSERT ARANCELES_INSCRIPCION(monto,vigente_desde,genero) VALUES (5,'2026-10-01','Femenino'); PRINT 'T8 FALLO duplicado genero'; END TRY BEGIN CATCH PRINT 'T8 ok: inscripcion femenina monto 0 permitida y duplicado por genero rechazado'; END CATCH
-- 5. DNI unico / formato
BEGIN TRY INSERT PERSONAS(nombre,apellido,dni) VALUES (N'X',N'Y','90000001'); PRINT 'T9 FALLO dni duplicado'; END TRY BEGIN CATCH PRINT 'T9 ok dni duplicado rechazado'; END CATCH
BEGIN TRY INSERT PERSONAS(nombre,apellido,dni) VALUES (N'X',N'Y','12AB5678'); PRINT 'T9b FALLO dni no numerico'; END TRY BEGIN CATCH PRINT 'T9b ok dni no numerico rechazado'; END CATCH
-- 6. auditoria con operador
INSERT USUARIOS(FK_id_persona,FK_id_rol,email,activo) VALUES (@pa,1,'test.uno@ejemplo.com',1); DECLARE @u INT=SCOPE_IDENTITY();
EXEC sys.sp_set_session_context @key=N'idUsuario', @value=@u;
UPDATE CATEGORIAS SET asociacion='AFA' WHERE PK_id_categoria=3;
UPDATE PAGOS SET monto_final=79000 WHERE FK_id_jugador=@a AND estado=0 AND fecha_vencimiento=@mesA;
SELECT 'T10 auditoria: '+(SELECT STRING_AGG(entidad+'/'+accion+'/'+ISNULL(email_usuario,'sin operador')+'/'+ISNULL(dni_usuario,'-'),' ; ') FROM AUDITORIA_CAMBIOS WHERE id_usuario=@u);
-- 7. acceso nace cerrado
SELECT 'T11 cuenta nueva: acceso_portal='+CAST((SELECT acceso_portal FROM USUARIOS WHERE PK_id_usuario=@u) AS varchar)+' token_version='+CAST((SELECT token_version FROM USUARIOS WHERE PK_id_usuario=@u) AS varchar);
-- 8. borrar categoria con arancel debe fallar
INSERT ARANCELES(FK_id_categoria,monto,vigente_desde) VALUES (3,100,'2026-10-01');
BEGIN TRY DELETE FROM CATEGORIAS WHERE PK_id_categoria=3; PRINT 'T12 FALLO: borro categoria con arancel'; END TRY BEGIN CATCH PRINT 'T12 ok: no se puede borrar una categoria con arancel o jugadores'; END CATCH
ROLLBACK;

