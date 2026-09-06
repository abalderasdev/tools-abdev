# tools-abdev

Herramientas internas de ABDev. Cada carpeta es un proyecto independiente que se
despliega por separado en Vercel apuntando **Root Directory** a esa carpeta.

| Proyecto | Qué es | Producción |
|---|---|---|
| [`Fresko-cumbres/`](Fresko-cumbres/) | Formulario de registro de personal para la activación de inauguración del Fresko Cumbres (Monterrey, 9–13 sep 2026). Entrega folio, controla bonos de capacitación y referidos, guarda en Supabase. | https://fresko-cumbres.abdev.click |

## Desplegar un proyecto

1. vercel.com → **Add New → Project** → importa `abalderasdev/tools-abdev`.
2. **Root Directory** → *Edit* → selecciona la carpeta del proyecto.
3. Cada proyecto trae su propio `vercel.json` con la configuración de salida.

Ver el README de cada carpeta para los detalles.
