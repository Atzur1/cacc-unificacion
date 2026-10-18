# Decisiones tomadas

- **Una sola base**, entregada **vacía**. Solo se cargarán después los jugadores del Excel del club; nada de historial de pagos, ni becas.
- **Nombres de tablas** del Portal Deportivo (`PERSONAS`, `USUARIOS`, `TIPOS_DESCUENTO`, `JUGADORES_RESPONSABLES`, `STAFF_CATEGORIAS`).
- **Un solo login: el del Administrativo** (por DNI), con un token que aceptan las dos APIs. Contraseña única (`USUARIOS.contrasenia`, BCrypt).
- **El Administrador (rol de portal 2) solo usa el Portal Administrativo**: tareas contables, deudores, becas y descuentos. Sin pantalla de portales y sin acceso al Deportivo.
- **Estado de deuda para el Deportivo: por API del Administrativo** (por DNI y por lote). Hasta entonces, la vista puente `VISTA_ESTADO_DEUDA`.
- **Altas**: las hace el Deportivo. El Administrativo solo habilita acceso a personas ya cargadas.
- **Jugadores no se borran**: baja con `fecha_baja`. El reingreso conserva el historial en `JUGADORES_PERIODOS`; `fecha_alta` es la del último reingreso.
- **Inscripción por género**: las mujeres hoy no pagan inscripción (monto 0) y la cuota femenina es otro arancel; debe poder cambiarse desde la pantalla de aranceles.
- **Cobranza**: todos arrancan sin deuda. `inicio_cobranza` (tabla `CONFIGURACION_CLUB`) fija el primer mes que se cobra.

# Pendiente
1. Llevar `parches/nuestro.patch` a una rama del repo real, actualizar sus pruebas y apuntar sus configuraciones a la base unificada.
2. ~~API de estado de deuda (por DNI y por lote)~~ Hecha (docs/api-estado-deuda.md, rama feat/base-unificada). Falta el aviso de "jugadores sin género" en el Resumen General.
3. Inscripción por género y `inicio_cobranza` en el código del Administrativo.
4. ~~Que el token del Administrador (rol 2) no lleve permisos del Deportivo.~~ Hecho (ClaimsDelToken, rama feat/base-unificada).
5. Parche definitivo para el Deportivo (`hallazgos-otro-equipo.md`).
6. Decidir qué hace el QR si la API de estado de deuda no responde (permitir y marcar "sin verificar", o denegar).
7. Probar las pantallas de los dos portales y el traspaso de sesión entre ellos.
8. Provisionar el primer SuperAdmin de producción (hoy hay un bloque comentado al final del script).
