# Análisis de la unificación (octubre 2026)

## Punto de partida
Dos sistemas con dos bases:
- **Portal Administrativo** (este equipo): finanzas. Cuotas, pagos, becas y descuentos, aranceles, auditoría, usuarios y permisos.
  20 migraciones aplicadas por la propia API.
- **Portal Deportivo** (NejoCHZ/App-Club-Atletico-Camioneros): jugadores, staff, categorías, fichas médicas, partidos y QR de asistencia.

Objetivo: **una sola base**, un solo login (el del Administrativo), cada portal consume lo del otro.

## Qué se encontró
1. La base unificada del sandbox del 7/10 estaba **atrasada** respecto del código actual: sin las secuencias de `PAGOS`/`JUGADORES`,
   sin `PAGOS_ANULADOS`, `INTENTOS_LOGIN`, ni las columnas nuevas de becas. Se reemplazó por `base-de-datos/…v2…`.
2. Tu lógica de cuotas vive en el código, no en la base:
   - `PAGOS.fecha_vencimiento` es el **primer día del mes que cubre** la cuota, no su vencimiento (vence el día 10 del mes siguiente).
   - Una cuota = una fila pendiente (`estado = 0`, saldo en `monto_final`) + una fila por cada abono (`estado = 1`).
   - El beneficio no se graba en el pago: se aplica al leer (`DescuentosSql`). Las becas cubren meses completos.
3. La vista `VISTA_ESTADO_DEUDA` que usa el Deportivo contradecía esa lógica (`fecha_vencimiento < GETDATE()`, sin abonos ni becas):
   con datos reales 4 de 6 jugadores tenían mal el conteo de cuotas vencidas, y el QR le negaba el ingreso a alguien que debía poder entrar.
4. El código del Deportivo no está preparado para esta base: ver `hallazgos-otro-equipo.md`.

## Qué se resolvió
- Base unificada v2, vacía, con todo lo del Administrativo y lo del Deportivo (`base-de-datos/`).
- Vista puente `VISTA_ESTADO_DEUDA` con las reglas del Administrativo, hasta que el Deportivo consuma la API de estado de deuda.
- Historial de permanencias de cada jugador (`JUGADORES_PERIODOS`, mantenido por trigger) y `JUGADORES.activo` calculado.
- Inscripción por género (monto 0 permitido) y tabla de configuración (`inicio_cobranza`).
- Parche para el Administrativo (`parches/nuestro.patch`) y pruebas de integración entre las dos APIs.

## Qué falta
Ver `decisiones.md` (sección "Pendiente"). En resumen: llevar el parche a una rama del repo real, la API de estado de deuda,
inscripción por género y fecha de inicio de cobranza en el código, el parche definitivo para el Deportivo y las pantallas (frontends).
