# Hallazgos en el código del Portal Deportivo (main del 15/10, commit afa4e60)

Probado contra la base unificada con `scripts/probar.ps1`.

**Estado: los 10 puntos están resueltos en `parches/ellos-definitivo.patch` y `parches/ellos-definitivo-frontend.patch`** (ver `parche-deportivo.md`):
`probar.ps1` ya no tiene ningún GAP pendiente. La tabla queda como registro de qué se encontró y por qué.

| # | Problema | Dónde | Arreglo |
|---|---|---|---|
| 1 | `INSERT … OUTPUT` sin `INTO` en `PERSONAS` y `JUGADORES`: SQL Server lo prohíbe en tablas con trigger de auditoría. El alta devuelve 500. | `BackEnd/CACC.DAO/JugadorDao.cs` (4 sentencias) | `OUTPUT INSERTED.id INTO @tabla` y leer el id de ahí. |
| 2 | Calcula `MAX(id)+1` y lo inserta a mano en `RESPONSABLES` y `JUGADORES_RESPONSABLES`, que son IDENTITY (también en su propio script SQL). El alta con tutor devuelve 500. | `JugadorDao.cs` (4 sentencias) | No mandar el id; leer el generado. |
| 3 | El alta no pide **género ni categoría** (solo nombre y DNI). Sin género no hay arancel que corresponda (ni inscripción); sin categoría el jugador desaparece de Deudas y Morosidad. **Ahora la base los exige** (`V20261018_02`): un alta incompleta falla. | DTO `JugadorCreateDto`, `JugadorAlta`, `JugadorDao`, `JugadoresController`, formulario de alta | Dos campos obligatorios (género Masculino/Femenino y categoría) en el formulario y en el servidor, y guardar el género en `PERSONAS` antes de crear el jugador. Ya está en `ellos-provisorio.patch` (solo servidor). |
| 4 | No filtra las **bajas**: lista a los jugadores dados de baja y el QR los deja entrar. | Listados de `JugadorDao`/`CategoriaDao`, `AsistenciaDao` | `WHERE activo = 1` (la columna se calcula sola). |
| 5 | `EliminarAsync` hace `DELETE` de `PAGOS`, `JUGADORES_DESCUENTOS` y `PERSONAS`. | `JugadorDao.cs` (~línea 588) | Baja lógica: `fecha_baja = hoy`. **Nunca borrar pagos.** |
| 6 | Borrar una categoría deja `FK_id_categoria = NULL` en los jugadores. | `CategoriaDao.cs` (~línea 195) | Rechazar el borrado si la categoría tiene jugadores o aranceles. |
| 7 | Sus escrituras no dicen quién las hizo, por lo que la auditoría queda sin responsable. | Todos los DAO | Al abrir la conexión: `EXEC sys.sp_set_session_context N'idUsuario', <id del token>`. |
| 8 | El cierre de sesión no vale en el Deportivo: no valida `tokenVersion` ni que el usuario siga activo. | `Program.cs` | Validar en `OnTokenValidated`, como el Administrativo. |
| 9 | Tiene login propio (`api/auth/login`). | `AuthController.cs` y pantalla de login | Dejar de usarlo: el login es el del Administrativo. Misma clave/emisor/audiencia JWT, desde variables de entorno. |
| 10 | `UserScopeService` trata el rol 2 ("Administrativo") como lector de jugadores. El Administrador **solo usa el Portal Administrativo**. | `Authorization/UserScopeService.cs` | Quitar el rol 2. |

El QR ya no lee `VISTA_ESTADO_DEUDA`: consulta la API de estado de deuda del Administrativo (la vista puente queda solo como control de paridad).
