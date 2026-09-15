# Fresko Cumbres — estado del proyecto

Última actualización: **15 de septiembre de 2026, tarde**

Este archivo existe para que cualquiera —otra sesión de Claude, MiniMax,
otro programador— entre en contexto leyendo un solo documento, sin que
Alberto tenga que volver a explicar la historia.

---

## Qué es esto

Activación de promotores en calle para la inauguración del **Fresko Valle
de Cumbres**, Mitras Poniente 66035, Monterrey. Alberto Balderas recluta,
coordina y paga en efectivo. Contacto: 55 6180 0423.

Va en **dos etapas**:

| | Etapa 1 | Etapa 2 (viva) |
|---|---|---|
| Campaña | `FRESKO-CUMBRES-SEP26` | `FRESKO-CUMBRES-ETAPA2` |
| Fechas | 9 al 13 de septiembre | **14 al 24 de septiembre** |
| Horario | 9 am a 3 pm | **1 pm a 7 pm** |
| Capacitación | Martes 8, con $200 | **No hay** |
| Gente | ~41 trabajaron | **15 titulares + 2 suplentes** |
| Registro | cerrado | **abierto** |

Pago en las dos: **$400 por día, entregados a la mañana siguiente**, más
**$50 diarios de puntualidad** y **$50 por referido**, ambos al cierre.
Uniforme: pantalón de mezclilla azul y tenis; playera, gorra, mandil y
agua los pone la empresa.

---

## Dónde vive todo

- **Código**: repo `abalderasdev/tools-abdev`, carpeta `Fresko-cumbres/`.
  Rama `main`. Cada push despliega solo.
- **Sitio**: https://fresko-cumbres.abdev.click (Vercel, `outputDirectory:
  Fresko-cumbres/public`, `cleanUrls: true` — por eso `/pase` sirve
  `pase.html`).
- **Base de datos**: Supabase, proyecto `eykfdnoczpwjccunzfgh`.
  MCP: https://mcp.supabase.com/mcp

> **La fuente de verdad de la base es la base, no los `.sql` del repo.**
> Los archivos en `db/` documentan qué se aplicó y por qué, pero las
> migraciones se aplicaron directo. Para ver lo vigente, consulta el
> proyecto.

---

## Las pantallas

| Ruta | Para quién | Qué hace |
|---|---|---|
| `/` | público | Registro. Sube foto de INE desde el celular. Da folio al momento y la liga del grupo de WhatsApp. |
| `/presente` | promotor | Marca entrada y salida con GPS. **Solo sirve para el bono**, no para el pago. Muestra la misión del día. |
| `/milugar` | promotor | Consulta si es titular, suplente o reserva, y **por qué**. Sin contraseña: folio + últimos 4 del teléfono. |
| `/pase` | coordinador | Pase de lista por folio. **Esto es lo que se paga.** Muestra si vino ayer, cuánto se le debe, botón de pagado y de adelanto. |
| `/dash` | admin | Panel. Abre en "Etapa 2 · hoy": plantilla, presentes, misiones, dinero, expedientes. |
| `/lista` | coordinador | Alta en sitio, completar datos, captura de INE, equipos. |
| `/puestos` | coordinador | Quién está en su puesto, suplencias. |
| `/recordatorio` | coordinador | Mensajes de WhatsApp por pestañas, uno por situación. Abre `wa.me` con el texto ya escrito. |
| `/confirmo` | público | Confirmación de asistencia por enlace (de la Etapa 1). |
| `/equipo` | staff | Acepta invitación y crea contraseña. |

Sesión del personal: `sesion.js`, compartido. Guarda el `refresh_token`
en `localStorage` y lo renueva solo — por eso el celular queda dentro
por días. "Salir" revoca del lado del servidor.

---

## Las reglas del negocio, que costaron trabajo fijar

**Quién pasa asistencia.** El coordinador, en `/pase`. Eso es lo que se
paga. `/presente` es **solo** para el bono de puntualidad.

**Cuándo se paga.** El día trabajado se vuelve pagable **a la mañana
siguiente**, nunca el mismo día. Por eso `/pase` muestra "le debes" al
día siguiente.

**Días de descanso.** `parametros.descansos` es un arreglo de fechas en
las que no se trabaja aunque caigan dentro del rango. El 16 de
septiembre está ahí. Sin eso, alguien podría marcar entrada un día
feriado y generar una jornada que nadie trabajó.

**Ventanas de checada (Etapa 2).** Entrada: de 1:00 a 2:00 pm — después
ya no deja marcar. Salida: nunca antes de las 7:00 pm. **A la gente se le
dice que hay 30 minutos de tolerancia; el sistema aguanta 60**, a
propósito, para no castigar al que se atrasó tantito.

**Si la marca se acepta, es puntual.** La ventana *es* la puntualidad.
Así nadie tiene que explicar por qué algo quedó registrado pero no contó.

**Equipo D · Globos.** Didier (079) coordina, $800/día desde el 15 sep.
Erick (103) está con los globos todo el día y tiene
`marca_automatica`: se le registra entrada y salida solo cada día
laborable, con puntualidad, sin pedirle que marque con GPS. Si le
pasaron lista tarde a mano, esa marca se promueve a puntual — la
decisión fue que no tiene que marcar, así que no debe costarle el bono.

**Una marca a mano nunca da puntualidad.** Si el coordinador pasa lista
tarde, eso no debe quitarle ni regalarle el bono a nadie.

**Un solo libro de jornadas.** `asistencia` (Etapa 1) y `presencia`
(Etapa 2) se leen juntas por la vista **`v_jornadas`**. Todo lo que
pregunte "¿quién trabajó qué día?" lee esa vista, nunca las tablas.

**Orden de la fila** (`v_prioridad_etapa2`), decidido por Alberto:
1. Se presentó el primer día (14 de septiembre)
2. **Ya se inscribió a esta etapa** — quien levantó la mano va antes
   que quien todavía no responde
3. Ya trabajó en la etapa anterior
4. Llegó primero

Los primeros 15 son titulares, los 2 siguientes suplentes, el resto
reserva. **A nadie se le dice "no"**: se le dice que está cubierto y que
sigue en la fila para vacantes, suplencias y las próximas activaciones.
Cuando le toque, se le avisa **con un día de anticipación**.

**Folios de prueba.** `candidatos.es_prueba` marca los que Alberto usa
para probar (hoy el 030). Siguen funcionando en todas las pantallas,
pero quedan fuera de la fila, de la plantilla, de los conteos y de los
mensajes. No se borran ni se dan de baja: se necesitan vivos.

**La bitácora es privada.** La tabla `bitacora` tiene RLS activo y **cero
políticas a propósito**: no se lee por la API con ninguna sesión, solo
desde el editor SQL. Registra toda operación que cambia algo, con el
valor anterior.

**Las fotos de INE.** Bucket privado `ine`. El público solo puede
**escribir** en `ine/registro/`, nunca leer. Se prometió borrarlas al
terminar; ya existe la política de borrado para el personal.

---

## Cómo está la base (15 sep)

| | |
|---|---|
| Candidatos con folio | 93 |
| Inscritos a Etapa 2 | 13 de 15 |
| En la fila de prioridad | 93 |
| Marcaron el día 1 | 7 |
| Pagos registrados | 169 — Etapa 1 liquidada |
| Misiones escritas | 1 (sin publicar) |
| **15 sep: marcaron a tiempo** | **12 de 15 inscritos** |

### Tablas propias
`candidatos`, `participaciones`, `asistencia`, `presencia`, `pagos`,
`adelantos`, `bonos`, `bono_dia`, `misiones`, `equipos`, `suplencias`,
`puntos`, `parametros`, `bitacora`, `dashboard_acceso`, `invitaciones`.

### Vistas clave
`v_jornadas` (une asistencia + presencia), `v_prioridad_etapa2` (la
fila), `v_confirmacion`, `v_estado_cuenta`.

### Funciones que importan
`registrar_candidato`, `guardar_ine`, `registrar_presencia`,
`estado_presencia`, `mi_lugar`, `pase_lista`, `pase_lista_dia`,
`marcar_pagado`, `deshacer_pago`, `dar_adelanto`, `deshacer_adelanto`,
`plantilla_etapa2`, `resumen_etapa2`, `mision_del_dia`,
`guardar_mision`, `misiones_lista`, `expediente`.

---

## Lo que falta — plan de acción

### 1. Publicar la misión del día 15
Está escrita y en borrador. `/dash` → Etapa 2 → abajo. Botón "Ver como
la verá el equipo" antes de publicar.

### 2. Mandar la convocatoria
`/recordatorio` → pestaña "🎯 Etapa 2 · convocar". Sale para los que
trabajaron la Etapa 1 y no están inscritos. Alberto tiene un módulo
aparte para enviar por WhatsApp.

### 3. Punto de encuentro — PENDIENTE DE COORDENADAS
El equipo se coloca en **la entrada del fraccionamiento**, no en la
puerta de la tienda. El geocerco (`puntos.cumbres-e2`) sigue apuntando
a la tienda con 300 m de radio. Si la entrada queda fuera de ese radio,
nadie podrá marcar entrada. **Falta el pin exacto.**

### 4. Agente conversacional
`/milugar` ya resuelve la mayoría de las dudas sin IA. Para uno que
converse hace falta `ANTHROPIC_API_KEY` en Vercel y un endpoint.

### 5. Pendientes menores
- Dos archivos de prueba en el bucket: `registro/099-test.jpg` y
  `registro/999-test.jpg`. Sin folio que los referencie.
- Supabase tiene **"Confirm email" encendido**: cada invitación al panel
  se rompe a la mitad. Apagarlo en Authentication → Sign In → Email.
- `dash.fresko-cumbres.abdev.click` nunca se dio de alta en Vercel.

---

## Trampas conocidas

- **Hay un repo git en la raíz de `C:\`** que rastrea todo el disco.
  Verificar `git rev-parse --show-toplevel` antes de cualquier commit.
  El repo bueno está en el clon de `tools-abdev`.
- **Los heredoc de bash fallan** con SQL que trae `$`. Usar la
  herramienta de escritura de archivos.
- **WhatsApp Web** solo funciona por el MCP `chrome-devtools`; el
  navegador integrado lo bloquea por user-agent. La lista de chats es
  virtualizada: lo que no está en pantalla no aparece en el DOM, y eso
  hace creer que un chat no existe.
- **Al subir a Storage, no mandar `x-upsert`**: sobrescribir exige
  permiso de UPDATE que el público no tiene, y con esa cabecera *todas*
  las subidas fallan con 403.
