# API de estado de deuda (Portal Administrativo)

Fuente única de "cuánto debe un jugador y qué puede hacer" para el Portal Deportivo (QR de ingreso y listados).
Usa las reglas del Administrativo: becas y descuentos, abonos parciales y el vencimiento de la cuota el **día 10 del mes siguiente**.
Reemplaza a la vista provisoria `VISTA_ESTADO_DEUDA`, que seguirá en la base hasta que el Deportivo termine de migrar.

Base: la URL del Portal Administrativo (en pruebas, `http://localhost:5318`).

## Autenticación
El **mismo token** de los dos portales: el Deportivo reenvía el `Authorization: Bearer ...` del usuario que está operando.
Pueden consultar: SuperAdmin del Administrativo, `Administrador (Tesorero)`, `Don QR`, `Coordinador`, `Médico`,
`Director Técnico` y `Preparador Físico`. **El Administrador del Administrativo (rol 2) no.**
- Ven a cualquier jugador: SuperAdmin, Administrador (Tesorero), Don QR, Coordinador y Médico.
- Director Técnico y Preparador Físico ven solo a los jugadores de las categorías de su token (claims `id_categoria`). Lo demás responde como "no encontrado".

## `GET /api/estado-deuda/dni/{dni}`
El DNI puede venir con puntos (`41.000.001`).

| Respuesta | Cuándo |
|---|---|
| `200` | Hay un jugador con ese DNI. |
| `400` | El DNI no es válido (solo números, de 6 a 9 dígitos). |
| `404` | No es un jugador, o no es de tu alcance. |
| `409` | El DNI corresponde a más de un jugador. |
| `401` / `403` | Sin token / el rol no puede consultar. |

```json
{
  "dni": "41000001",
  "idJugador": 1,
  "estado": "solo_entrenamientos",
  "accesoPermitido": true,
  "cuotasVencidas": 1,
  "deudaTotal": 170000.0,
  "enTermino": false,
  "fechaBaja": null
}
```

## `POST /api/estado-deuda/lote`
Para los listados. Hasta 500 DNI por pedido.
```json
{ "dnis": ["41.000.001", "42000002"] }
```
Responde `{ "items": [ ...igual que arriba... ], "noEncontrados": ["42000002"] }`. En `noEncontrados` van los DNI inválidos,
los que no son de un jugador y los que están fuera del alcance de quien consulta.

## Significado de los campos
| Campo | Qué es |
|---|---|
| `estado` | `habilitado` (0 cuotas vencidas), `solo_entrenamientos` (1), `inhabilitado` (2 o más), `baja` (el jugador se fue del club). |
| `accesoPermitido` | `true` en `habilitado` y `solo_entrenamientos`. Es lo que decide el semáforo del QR. |
| `cuotasVencidas` | Cuotas con saldo cuyo vencimiento ya pasó. Lo que el QR del Deportivo muestra (verde 0, amarillo 1, rojo 2 o más). |
| `deudaTotal` | Todo lo pendiente (cuotas e inscripción) con la beca ya descontada. |
| `enTermino` | Debe algo pero nada vencido todavía. |

## Cómo lo usaría el QR
`AsistenciaDao.ProcesarIngresoAsync` hoy lee `VISTA_ESTADO_DEUDA`. Para pasar a esta API: en lugar de la vista, llamar a
`GET /api/estado-deuda/dni/{dni}` con el token del usuario y usar `accesoPermitido`, `cuotasVencidas` y `deudaTotal`
(el contrato de respuesta del QR hacia su frontend no cambia). Sigue siendo el Deportivo quien registra la asistencia.

**Pendiente de decidir:** qué hace el QR si esta API no responde (permitir y marcar "sin verificar", o denegar).
