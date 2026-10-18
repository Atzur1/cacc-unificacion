# Base unificada v2 (17/10/2026)

Base vacia `ClubCamionerosUnificadaV2`, creada con `ClubCamioneros_unificada_v2_crear_base.sql`
(`sqlcmd -S localhost -E -C -b -i ClubCamioneros_unificada_v2_crear_base.sql`; repetirlo no cambia nada).

Reemplaza a `..\esquema\ClubCamioneros_unificada_crear_base.sql` (7/10), que ya no alcanzaba para el codigo actual.
No toca el repositorio ni las bases existentes. Para borrarla: `DROP DATABASE ClubCamionerosUnificadaV2;`

## Que tiene
- Solo catalogos: ROLES (7, ids fijos del Portal Deportivo), CATEGORIAS (13, con asociacion) y TIPOS_DESCUENTO (Becado, Descuento).
  Sin aranceles, sin configuracion de cobranza, sin personas, jugadores, pagos ni becas.
- Todo lo del Portal Administrativo a la fecha: secuencias SEQ_PAGOS / SEQ_JUGADORES, PAGOS_ANULADOS, INTENTOS_LOGIN,
  becas con anulado / cancelada_por_baja / fecha_asignacion, auditoria con triggers, TOKEN_ACCESO_CUENTA.
- Todo lo del Portal Deportivo (main del 15/10): JUGADORES_CATEGORIAS, CREDENCIALES_QR, HISTORIAL_PARTIDOS, FICHAS_MEDICAS, etc.
- Nuevo: JUGADORES_PERIODOS (historial de altas y bajas, lo mantiene un trigger), JUGADORES.activo calculado,
  ARANCELES_INSCRIPCION por genero (monto 0 permitido), CONFIGURACION_CLUB (clave `inicio_cobranza`, todavia sin uso en el codigo).
- `__CaccMigraciones` con las 20 migraciones del repo (mismo hash que calcula la API).
- VISTA_ESTADO_DEUDA: puente transitorio con las reglas del Portal Administrativo. La fuente de verdad sera la API.

## Lo que el codigo del Portal Administrativo tiene que cambiar para usarla (aun NO hecho)
1. Nombres: `PERSONA`->`PERSONAS`, `USUARIO`->`USUARIOS`, `TIPO_DESCUENTO`->`TIPOS_DESCUENTO` (64 lineas en DaoLibrary / ApiGestion,
   20 en las pruebas), incluidos los nombres de entidad de `AuditReferences` / `AuditReferenceResolver`. La columna `Dni` pasa a `dni`.
2. Credencial: `USUARIO.password_hash` -> `USUARIOS.contrasenia` (AccountAccessDao, AuthDao, UsuariosPortalDao: ~20 lineas). El hash ya es BCrypt.
3. Identidad: `USUARIO.nombre/apellido/dni` ya no existen; se leen de PERSONAS (AccountAccessDao:155, UsuariosPortalDao:158 y 217).
4. Inscripcion por genero: `InscripcionesService` cobra solo a `Genero.Masculino`; `EnrollmentFeeDao` no manda genero.
5. `inicio_cobranza`: el generador y el aviso de cuotas faltantes deben ignorar los meses anteriores.
6. API de estado de deuda para el Portal Deportivo (por DNI y por lote).
7. Migraciones futuras: se escriben ya con los nombres nuevos.

## Lo que pedirle al otro equipo
- No borrar jugadores ni pagos (baja = JUGADORES.fecha_baja). No dejar NULL la categoria de un jugador al borrar una categoria.
- Un solo login (el del Portal Administrativo), con el mismo token. Fijar el operador de auditoria al abrir cada conexion.
- Insertar en JUGADORES / PAGOS sin id (lo pone la secuencia). Reemplazar VISTA_ESTADO_DEUDA por la API cuando este lista.
