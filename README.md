# cacc-unificacion

Banco de pruebas de la **base de datos única** del Club Atlético Camioneros: la comparten el Portal Administrativo
(este equipo) y el Portal Deportivo (NejoCHZ/App-Club-Atletico-Camioneros).

Este repo **no contiene el código de ninguno de los dos sistemas**. Guarda lo que hace falta para unirlos y probarlos:

| Carpeta | Qué hay |
|---|---|
| `base-de-datos/` | Script que crea la base unificada **vacía** (solo catálogos) y su contrato. |
| `parches/` | Cambios que se aplican sobre cada repo: `nuestro.patch` (Portal Administrativo) y `ellos-provisorio.patch` (mínimo para poder probar el Deportivo). |
| `pruebas/` | Pruebas de la base, cuentas de prueba y pruebas de integración entre las dos APIs. |
| `scripts/` | `armar.ps1`, `iniciar.ps1`, `probar.ps1`, `detener.ps1`. |
| `docs/` | Análisis, decisiones y hallazgos. Empezar por `docs/analisis-unificacion.md`. |
| `versiones.json` | Con qué versión de cada repo se probó. |

## Cómo se prueba (desde cero)

Requisitos: .NET SDK 9, `sqlcmd`, Git para Windows (se usa su `patch.exe`) y SQL Server local con autenticación de Windows.

1. Tené tu repo del Portal Administrativo y un **clon actualizado** del repo del otro equipo (rama `main`).
2. Armar el entorno (copia los repos a `trabajo/`, aplica los parches, crea la base de prueba y compila):
   ```powershell
   .\scripts\armar.ps1 -RepoNuestro "C:\ruta\Sistema Administrativo - CACC" -RepoEllos "C:\ruta\App-Club-Atletico-Camioneros" -Recrear -Iniciar
   ```
3. Correr las pruebas:
   ```powershell
   .\scripts\probar.ps1
   ```
4. Frenar las APIs: `.\scripts\detener.ps1`.

Las pruebas del proyecto del Administrativo (`ApiGestion.Tests`, 415) contra la base unificada:
```powershell
.\scripts\pruebas-del-proyecto.ps1 -RepoNuestro "C:\ruta\Sistema Administrativo - CACC"
```

Los repos originales **no se modifican**: todo ocurre en `trabajo/` (ignorada por git) y en la base `ClubCamionerosUnificadaV2_Prueba`.

## Cómo leer el resultado

- **PASA**: funciona.
- **FALLA**: error nuestro o de la base; hay que arreglarlo.
- **GAP**: problema conocido del código del otro equipo (`docs/hallazgos-otro-equipo.md`). No cuenta como falla; cuando
  ellos apliquen su parche pasa solo a PASA. Es la forma de comprobar que lo arreglaron.

## Cuentas de prueba (clave `Camioneros.Test.2026!`)

| DNI | Quién | Alcance |
|---|---|---|
| 20111222 | SuperAdmin | Administrativo y Deportivo |
| 30000003 | Médica | Solo Deportivo |
| 30000004 | Director Técnico (categoría 3) | Solo Deportivo |
| 30000002 | Ana, administrativa sin acceso aún | Se habilita en la prueba |

Son cuentas de una base local de pruebas; no existen en ningún entorno real.

## Reglas de este repo
- Sin secretos: ni claves de correo, ni cadenas de conexión reales, ni datos de personas reales. Las APIs de prueba usan una clave JWT generada al azar en cada armado.
- La base unificada se entrega **vacía**. La carga de datos del club es una tarea aparte.
- El código real de cada sistema se cambia en su propio repo (en una rama); acá solo viven los parches y las pruebas.
