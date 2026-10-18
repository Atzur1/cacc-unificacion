# Parche definitivo para el Portal Deportivo

Resuelve los 10 puntos de `hallazgos-otro-equipo.md` y deja al QR consultando la deuda al Portal Administrativo. Son dos parches
sobre el `main` del Deportivo (commit `afa4e60`):

| Parche | Carpeta donde se aplica | Qué toca |
|---|---|---|
| `parches/ellos-definitivo.patch` | `BackEnd` | 24 archivos: DAO, controladores, `Program.cs`, pruebas |
| `parches/ellos-definitivo-frontend.patch` | `FrontEnd` | 15 archivos: alta de jugador, QR, pantalla de ingreso, sesión |

## Cómo aplicarlo

El repo del Deportivo puede tener saltos de línea CRLF y BOM; el parche está en LF. Por eso se aplica con el script, que conserva el
formato de cada archivo y, si algo no encaja, deja todo como estaba:

```powershell
cd parches
.\aplicar-parche.ps1 -Parche .\ellos-definitivo.patch          -Carpeta C:\ruta\al\repo\BackEnd  -Verificar   # solo comprueba
.\aplicar-parche.ps1 -Parche .\ellos-definitivo.patch          -Carpeta C:\ruta\al\repo\BackEnd
.\aplicar-parche.ps1 -Parche .\ellos-definitivo-frontend.patch -Carpeta C:\ruta\al\repo\FrontEnd
```

Después: `dotnet test BackEnd\CACC.Tests` (55 pruebas) y, en `FrontEnd`, `npx ng test --watch=false --browsers=ChromeHeadless`.

## Qué cambia para ellos

**Base de datos.** Usan la base unificada (no la `Bbdd CACC.sql` vieja). Los nombres de tablas coinciden con los suyos.

**Altas.** `OUTPUT … INTO`, sin ids a mano (los de tutores ya no se calculan con `MAX+1`). **Género (Masculino/Femenino) y categoría son
obligatorios** en el formulario, en el servidor (400) y en la base (si faltan, la base rechaza el alta). Al editar, el género nunca queda
vacío: si no viene se conserva el que tiene y si viene debe ser Masculino o Femenino.

**Bajas.** Los listados, el plantel y el QR solo muestran jugadores activos. `DELETE /api/jugadores/{id}` ya no borra nada: da de baja
(`fecha_baja = hoy`) y conserva persona, pagos, descuentos, asistencias y ficha médica. La reincorporación se hace desde el Administrativo.

**Categorías.** No se borra una categoría con jugadores ni aranceles (409 con el motivo). Ya no se deja `FK_id_categoria = NULL`.

**Auditoría.** Toda conexión de los DAO se abre con `OpenAuditadaAsync`, que copia el usuario del token a `SESSION_CONTEXT('idUsuario')`.
Una prueba (`DonQrSqlContractTests`) falla si alguien vuelve a abrir una conexión con `OpenAsync` a secas.

**Sesión.** `Program.cs` valida en cada pedido que el usuario siga activo y que `tokenVersion` coincida (igual que el Administrativo): cerrar
sesión en un portal la cierra en los dos. Clave, emisor y audiencia del JWT salen de `Jwt:Key/Issuer/Audience` (variables `Jwt__Key`, …) y
**deben ser los mismos que los del Administrativo**. En producción la app no arranca con la clave de ejemplo del repositorio.

**Login único.** `POST api/auth/login` responde 410 (se enciende solo con `Auth:LoginPropio=true`, para desarrollo sin el otro portal).
La pantalla de ingreso del Deportivo ya no pide usuario y contraseña: recibe la sesión del Administrativo (`/login#sso=<token>`), la guarda
y borra el token de la barra de direcciones; si no hay sesión, manda a iniciar sesión en el Administrativo. El rol 2 (Administrador) no entra al
Deportivo: se quitó de `UserScopeService` y su token no trae permisos deportivos.

**QR y estado de cuota.** La deuda ya no se lee de `VISTA_ESTADO_DEUDA`: la informa `GET {AdministrativoApi:BaseUrl}/api/estado-deuda/dni/{dni}` con
el mismo token del usuario. Los listados piden el estado de todos los jugadores con una sola llamada (`POST …/lote`). El Deportivo conserva
la decisión de acceso y el registro de la asistencia (idempotente por día).

| Estado | QR |
|---|---|
| habilitado | pasa, verde |
| solo_entrenamientos (1 cuota vencida) | pasa, amarillo |
| inhabilitado / baja | no pasa, rojo |
| el Administrativo no responde | no pasa nadie (503), no se registra asistencia |

Decisión del club: **si el Administrativo no responde, no pasa nadie** (`AdministrativoApi:SiNoResponde = Denegar`, valor por defecto). Existe la
opción `Permitir` (entra solo un jugador activo y la asistencia queda `SIN_VERIFICAR`), pero no se usa.

## Configuración nueva

```json
"AdministrativoApi": { "BaseUrl": "http://localhost:5118", "TimeoutSegundos": 3 }
```

Variables de entorno equivalentes: `AdministrativoApi__BaseUrl`, … En desarrollo, `BaseUrl` vale `http://localhost:5118` si no se configura.
CORS sale de `Cors:AllowedOrigins`; por defecto permite los puertos 4200 (Administrativo) y 4300 (Deportivo). En el FrontEnd la dirección del
Administrativo está en `src/app/core/auth/portales.config.ts`; en el Administrativo, la del Deportivo en `environments/environment*.ts`.

## Qué está probado y qué no

- Pruebas del Deportivo: 55 en el BackEnd (antes 18; se reescribieron las del QR porque ahora consulta al Administrativo) y 59 en el FrontEnd (antes 46). Una prueba del FrontEnd
  (`admin-coordinador-legacy-routes`) ya fallaba antes del parche, por nombres de clases; no tiene relación.
- `scripts/probar.ps1`: 88 verificaciones contra las dos APIs y la base real, sin pendientes.
- **No** probado en un navegador de punta a punta: el pase de sesión entre los dos sitios (`#sso=`) está cubierto por pruebas unitarias de
  cada lado, pero falta recorrerlo a mano con los dos frontends levantados.
