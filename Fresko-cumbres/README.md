# Fresko Cumbres · Registro de personal

Formulario de registro para la activación en calle del **9 al 13 de septiembre de 2026**
en Cumbres, Monterrey. Guarda los candidatos en Supabase, entrega un folio y controla
los dos programas de bonos (capacitación y referidos).

**Producción:** https://fresko-cumbres.abdev.click
**Base de datos:** Supabase · proyecto `activaciones-personal` (`eykfdnoczpwjccunzfgh`)

---

## Estructura

```
Fresko-cumbres/
├── public/
│   └── index.html      ← el sitio (esto es lo único que se publica)
├── db/
│   ├── 01_esquema.sql              respaldo del esquema (ya aplicado)
│   └── 02_carga_folios_whatsapp.sql  los folios 006-027 entregados por WhatsApp
├── docs/
│   ├── manual-de-operacion.md      cómo operarlo el día de la capacitación
│   └── mensajes-whatsapp.md        plantillas de mensajes
└── vercel.json
```

`vercel.json` limita el despliegue a `public/`, así que `db/` y `docs/` **no quedan
accesibles desde internet** aunque estén en el repo.

---

## Desplegar en Vercel

Como el repo tiene varios proyectos, hay que apuntar Vercel a esta carpeta:

1. vercel.com → **Add New → Project** → importa `abalderasdev/tools-abdev`.
2. En **Root Directory**, presiona *Edit* y selecciona `Fresko-cumbres`.
3. Framework Preset: **Other**. Build Command: vacío. Output Directory: `public`.
4. **Deploy**.

### Dominio

Project → Settings → Domains → agrega `fresko-cumbres.abdev.click`.
En el DNS de `abdev.click`:

```
Tipo:   CNAME
Nombre: fresko-cumbres
Valor:  cname.vercel-dns.com
```

Si el DNS está en Cloudflare, deja el registro en **DNS only** (nube gris) o el
certificado no se emite.

---

## Configuración

Las llaves están al final de `public/index.html`:

```js
const SUPABASE_URL = "https://eykfdnoczpwjccunzfgh.supabase.co";
const SUPABASE_KEY = "sb_publishable_...";
const CAMPANA      = "FRESKO-CUMBRES-SEP26";
const WHATSAPP     = "525561800423";
```

La llave es pública a propósito: con el RLS del esquema **solo puede registrar**,
no leer ni modificar nada. Los datos se consultan desde el panel de Supabase.

---

## Cómo funciona

- Cada registro recibe un folio consecutivo de 3 dígitos. El contador arranca en
  **030** porque los folios previos se entregaron por WhatsApp antes de tener el
  formulario. Ese rango llegó al 027, no al 029.
- Si alguien captura el folio de quien lo invitó, se genera un bono de $50 en estado
  `pendiente`. Pasa a `por_pagar` **solo cuando el invitado asiste a la capacitación**.
- El pase de confirmación incluye un botón que comparte el link con `?ref=SU_FOLIO`,
  para que el invitado no tenga que escribirlo.
- Al llegar a 70 registros, los nuevos entran como `lista_espera` en vez de rechazarse.

Ver `docs/manual-de-operacion.md` para las consultas del día de la capacitación.

---

## Pendiente

- [ ] Definir el monto del bono de capacitación (hoy está en $0):
      `update parametros set bono_capacitacion = X where campana = 'FRESKO-CUMBRES-SEP26';`
- [ ] Cargar los folios entregados por WhatsApp con `db/02_carga_folios_whatsapp.sql`
- [ ] Avisar su nuevo folio a las 4 personas reasignadas (006, 007, 008, 009)
