// Dashboard de la activación Fresko Cumbres.
//
// Corre en el servidor de Vercel: valida el usuario y consulta Supabase aquí,
// de modo que ni la contraseña ni la llave de la base llegan nunca al navegador.
// Al cliente solo le llega el HTML ya armado.
//
// Variables de entorno necesarias (Vercel → Settings → Environment Variables):
//   DASH_USER            usuario del dashboard
//   DASH_PASS            contraseña del dashboard
//   SUPABASE_URL         https://eykfdnoczpwjccunzfgh.supabase.co
//   SUPABASE_SECRET_KEY  llave secreta (service_role) del proyecto Supabase
//
// Sin esas variables el dashboard NO sirve datos: falla cerrado a propósito.

const CAMPANA = "FRESKO-CUMBRES-SEP26";

export default async function handler(req, res) {
  const { DASH_USER, DASH_PASS, SUPABASE_URL, SUPABASE_SECRET_KEY } = process.env;

  if (!DASH_USER || !DASH_PASS || !SUPABASE_URL || !SUPABASE_SECRET_KEY) {
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    return res.status(500).send(paginaError(
      "Falta configuración",
      "El dashboard no tiene sus variables de entorno. En Vercel → Settings → Environment Variables hay que definir <code>DASH_USER</code>, <code>DASH_PASS</code>, <code>SUPABASE_URL</code> y <code>SUPABASE_SECRET_KEY</code>, y volver a desplegar."
    ));
  }

  if (!autorizado(req.headers.authorization, DASH_USER, DASH_PASS)) {
    res.setHeader("WWW-Authenticate", 'Basic realm="Fresko Cumbres", charset="UTF-8"');
    return res.status(401).send("Se necesita usuario y contraseña.");
  }

  try {
    const [candidatos, bonos, parametros] = await Promise.all([
      consulta(SUPABASE_URL, SUPABASE_SECRET_KEY, "candidatos", "select=*&order=folio.asc"),
      consulta(SUPABASE_URL, SUPABASE_SECRET_KEY, "bonos", "select=*"),
      consulta(SUPABASE_URL, SUPABASE_SECRET_KEY, "parametros", `select=*&campana=eq.${CAMPANA}`)
    ]);
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    res.setHeader("Cache-Control", "no-store");
    res.setHeader("X-Robots-Tag", "noindex, nofollow");
    return res.status(200).send(render(candidatos, bonos, parametros[0] || {}));
  } catch (e) {
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    return res.status(502).send(paginaError("No se pudo leer la base", esc(String(e.message || e))));
  }
}

function autorizado(header, usuario, clave) {
  if (!header || !header.startsWith("Basic ")) return false;
  let dec = "";
  try { dec = Buffer.from(header.slice(6), "base64").toString("utf8"); } catch { return false; }
  const i = dec.indexOf(":");
  if (i < 0) return false;
  return igualSeguro(dec.slice(0, i), usuario) & igualSeguro(dec.slice(i + 1), clave) ? true : false;
}

// Comparación de tiempo constante, para no filtrar la clave por cuánto tarda en fallar.
function igualSeguro(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return 0;
  const A = Buffer.from(a, "utf8"), B = Buffer.from(b, "utf8");
  let dif = A.length ^ B.length;
  const n = Math.max(A.length, B.length);
  for (let i = 0; i < n; i++) dif |= (A[i] || 0) ^ (B[i] || 0);
  return dif === 0 ? 1 : 0;
}

async function consulta(url, key, tabla, qs) {
  const r = await fetch(`${url}/rest/v1/${tabla}?${qs}`, {
    headers: { apikey: key, Authorization: `Bearer ${key}`, Accept: "application/json" }
  });
  if (!r.ok) throw new Error(`${tabla}: ${r.status} ${await r.text()}`);
  return r.json();
}

const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (m) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[m]));
const dash = '<span class="vacio">—</span>';
const val = (v) => (v === null || v === undefined || v === "" ? dash : esc(v));
const tel = (t) => (t ? esc(String(t).replace(/(\d{3})(\d{3})(\d{4})/, "$1 $2 $3")) : dash);

function render(candidatos, bonos, p) {
  const activos = candidatos.filter((c) => c.estatus !== "baja");
  const bajas = candidatos.filter((c) => c.estatus === "baja");
  const confirmados = activos.filter((c) => c.estatus === "confirmado");
  const asistieron = activos.filter((c) => c.asistio_capacitacion);
  const meta = p.meta_folios || 70;
  const faltan = Math.max(0, meta - activos.length);

  // ---- tallas ----
  const orden = ["CH", "M", "G", "XG", "XL"];
  const tallas = {};
  let sinTalla = 0;
  activos.forEach((c) => { if (c.talla_playera) tallas[c.talla_playera] = (tallas[c.talla_playera] || 0) + 1; else sinTalla++; });

  // ---- bonos ----
  const porTipo = {};
  bonos.forEach((b) => {
    const k = `${b.tipo}|${b.estatus}`;
    porTipo[k] = porTipo[k] || { n: 0, monto: 0 };
    porTipo[k].n++; porTipo[k].monto += Number(b.monto || 0);
  });
  const bonoCap = Number(p.bono_capacitacion || 0);
  const bonoPunt = Number(p.bono_puntualidad || 0);
  const bonoRef = Number(p.bono_referido || 0);
  const porPagar = bonos.filter((b) => b.estatus === "por_pagar").reduce((s, b) => s + Number(b.monto || 0), 0);
  const pendientes = bonos.filter((b) => b.estatus === "pendiente").reduce((s, b) => s + Number(b.monto || 0), 0);

  // ---- huecos de datos ----
  const huecos = activos.filter((c) => !c.talla_playera || c.tiene_ine !== true || !c.edad || !c.colonia);

  // ---- quién invitó a quién ----
  const nombrePorFolio = Object.fromEntries(candidatos.map((c) => [c.folio, c.nombre]));
  const referidos = {};
  activos.forEach((c) => { if (c.referido_por_folio) (referidos[c.referido_por_folio] ||= []).push(c); });

  const corte = new Date().toLocaleString("es-MX", {
    timeZone: "America/Monterrey", day: "2-digit", month: "long",
    hour: "2-digit", minute: "2-digit", hour12: true
  });

  const tile = (n, k, cls = "") => `<div class="tile ${cls}"><div class="n">${n}</div><div class="k">${k}</div></div>`;

  const filaCand = (c) => {
    const lugar = [c.colonia, c.municipio].filter(Boolean).join(", ");
    const invitado = c.referido_por_folio
      ? `<span class="mono">${esc(c.referido_por_folio)}</span> ${esc((nombrePorFolio[c.referido_por_folio] || "").split(" ")[0] || "")}`
      : dash;
    return `<tr class="${c.estatus === "baja" ? "baja" : ""}">
      <td class="mono folio">${val(c.folio)}</td>
      <td class="nom">${val(c.nombre)}</td>
      <td class="mono">${tel(c.telefono)}</td>
      <td class="mono num">${val(c.edad)}</td>
      <td>${lugar ? esc(lugar) : dash}</td>
      <td class="mono num">${c.talla_playera ? esc(c.talla_playera) : '<span class="alerta">falta</span>'}</td>
      <td class="num">${c.tiene_ine === true ? "sí" : c.tiene_ine === false ? '<span class="alerta">no</span>' : dash}</td>
      <td><span class="badge b-${esc(c.estatus)}">${esc(c.estatus).replace("_", " ")}</span></td>
      <td>${invitado}</td>
      <td class="notas">${c.notas_internas ? esc(c.notas_internas) : dash}</td>
    </tr>`;
  };

  return `<!doctype html>
<html lang="es-MX"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Panel · Activación Fresko Cumbres</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,600;12..96,800&family=Archivo:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
:root{
  --verde:#0B5D2E; --verde-2:#2E9E4F; --naranja:#F2681F;
  --arena:#FFF6EC; --panel:#fff; --tinta:#14231A; --tinta-2:#5A6B60; --tinta-3:#8A968D;
  --linea:#E7DFD4; --linea-2:#D3C8B8; --error:#C2321B; --ok:#0B5D2E;
  --radio:12px;
}
@media (prefers-color-scheme:dark){
  :root:not([data-theme="light"]){
    --arena:#12160F; --panel:#1A2018; --tinta:#EAF0E7; --tinta-2:#AFBCB0; --tinta-3:#7E8C81;
    --linea:#2A332A; --linea-2:#3A463A; --verde:#6FBF89; --verde-2:#4FA46A; --naranja:#F2681F;
  }
}
*{box-sizing:border-box}
body{margin:0;background:var(--arena);color:var(--tinta);
  font-family:"Archivo",-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-size:15px;line-height:1.5}
.wrap{max-width:1180px;margin:0 auto;padding:0 20px 70px}
header{background:var(--verde);color:#fff;padding:24px 20px 22px;border-bottom:4px solid var(--naranja)}
.head-in{max-width:1180px;margin:0 auto;display:flex;flex-wrap:wrap;gap:18px;justify-content:space-between;align-items:flex-end}
h1{font-family:"Bricolage Grotesque",sans-serif;font-weight:800;font-size:clamp(24px,4vw,34px);
  line-height:1;letter-spacing:-.02em;margin:0}
.sub{margin:6px 0 0;color:#BFE6CB;font-size:14px}
.progreso{min-width:230px}
.barra{height:12px;background:rgba(0,0,0,.28);border-radius:99px;overflow:hidden;margin-top:8px}
.barra i{display:block;height:100%;background:var(--naranja);border-radius:99px}
.progreso b{font-family:"Bricolage Grotesque",sans-serif;font-size:26px}
h2{font-family:"Bricolage Grotesque",sans-serif;font-weight:700;font-size:19px;margin:34px 0 4px;letter-spacing:-.01em}
.lede{margin:0 0 14px;color:var(--tinta-2);font-size:14px}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:1px;background:var(--linea);
  border:1px solid var(--linea);margin-top:24px}
.tile{background:var(--panel);padding:14px 15px 12px}
.tile .n{font-family:"Bricolage Grotesque",sans-serif;font-weight:800;font-size:30px;line-height:1;font-variant-numeric:tabular-nums}
.tile .k{font-size:11.5px;letter-spacing:.06em;text-transform:uppercase;color:var(--tinta-3);margin-top:6px;font-weight:600}
.tile.ok .n{color:var(--ok)} .tile.warn .n{color:var(--error)} .tile.act .n{color:var(--naranja)}
.tallas{display:grid;grid-template-columns:repeat(auto-fit,minmax(92px,1fr));gap:1px;background:var(--linea);border:1px solid var(--linea)}
.talla{background:var(--panel);padding:13px 14px}
.talla .s{font-family:"Bricolage Grotesque",sans-serif;font-weight:800;font-size:15px;color:var(--verde)}
.talla .c{font-family:"Bricolage Grotesque",sans-serif;font-weight:800;font-size:26px;font-variant-numeric:tabular-nums}
.tw{overflow-x:auto;border:1px solid var(--linea);background:var(--panel)}
table{border-collapse:collapse;width:100%;min-width:940px}
th{font-size:10.5px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--tinta-3);
  text-align:left;padding:10px 11px;border-bottom:1px solid var(--linea-2);background:var(--arena);white-space:nowrap}
td{padding:9px 11px;border-bottom:1px solid var(--linea);vertical-align:top;font-size:14px}
tr:last-child td{border-bottom:none}
tbody tr:hover{background:var(--arena)}
tr.baja{opacity:.5}
.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-variant-numeric:tabular-nums;font-size:13px}
.folio{font-weight:700;color:var(--verde);font-size:14.5px}
.nom{font-weight:600}
.num{text-align:center}
.notas{color:var(--tinta-2);font-size:12.5px;max-width:30ch}
.vacio{color:var(--tinta-3)}
.alerta{color:var(--error);font-weight:700}
.badge{display:inline-block;font-size:10.5px;font-weight:700;letter-spacing:.05em;text-transform:uppercase;
  padding:3px 7px;border-radius:3px;white-space:nowrap}
.b-confirmado{background:#DCEFE2;color:#0B5D2E}
.b-registrado{background:#E4EAF0;color:#2C5578}
.b-asistio_cita{background:#DCEFE2;color:#0B5D2E}
.b-lista_espera{background:#FBEEDC;color:#8A3708}
.b-baja,.b-no_asistio{background:#FAE5E0;color:#C2321B}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]) .b-confirmado{background:#1C3227;color:#6FBF89}
 :root:not([data-theme="light"]) .b-registrado{background:#1B2833;color:#7FA8CC}
 :root:not([data-theme="light"]) .b-baja{background:#3A211B;color:#E2705A}}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:12px}
.card{background:var(--panel);border:1px solid var(--linea);border-radius:var(--radio);padding:15px 16px}
.card h3{font-family:"Bricolage Grotesque",sans-serif;font-size:15px;margin:0 0 8px}
.card .big{font-family:"Bricolage Grotesque",sans-serif;font-weight:800;font-size:27px;line-height:1.1;font-variant-numeric:tabular-nums}
.card p{margin:6px 0 0;font-size:13.5px;color:var(--tinta-2)}
.pill{display:inline-block;background:var(--arena);border:1px solid var(--linea-2);border-radius:99px;
  padding:3px 10px;font-size:12.5px;margin:3px 4px 0 0}
footer{margin-top:40px;padding-top:14px;border-top:1px solid var(--linea);color:var(--tinta-3);font-size:12.5px}
</style></head><body>

<header><div class="head-in">
  <div>
    <h1>Activación Fresko Cumbres</h1>
    <p class="sub">Capacitación martes 8 de septiembre, 4:00 p.m. · Activación del 9 al 13 · Corte: ${esc(corte)}</p>
  </div>
  <div class="progreso">
    <div><b>${activos.length}</b> <span style="color:#BFE6CB">de ${meta} lugares</span></div>
    <div class="barra"><i style="width:${Math.min(100, Math.round((activos.length / meta) * 100))}%"></i></div>
    <div class="sub" style="margin-top:6px">Faltan ${faltan}</div>
  </div>
</div></header>

<div class="wrap">

  <div class="tiles">
    ${tile(activos.length, "Registrados")}
    ${tile(confirmados.length, "Confirmaron", "ok")}
    ${tile(faltan, "Faltan para la meta", "act")}
    ${tile(asistieron.length, "Asistieron el martes")}
    ${tile(huecos.length, "Con datos incompletos", huecos.length ? "warn" : "")}
    ${tile(bajas.length, "Bajas")}
  </div>

  <h2>Uniformes por talla</h2>
  <p class="lede">Sobre las ${activos.length} personas activas. Esto es lo que hay que pedir.</p>
  <div class="tallas">
    ${orden.filter((s) => tallas[s]).map((s) => `<div class="talla"><div class="s">${s}</div><div class="c">${tallas[s]}</div></div>`).join("")}
    ${sinTalla ? `<div class="talla"><div class="s" style="color:var(--error)">Sin dato</div><div class="c">${sinTalla}</div></div>` : ""}
  </div>

  <h2>Bonos</h2>
  <p class="lede">Montos vigentes de la campaña y lo que llevas comprometido.</p>
  <div class="cards">
    <div class="card">
      <h3>Capacitación</h3>
      <div class="big">$${bonoCap.toLocaleString("es-MX")}</div>
      <p>Por persona, el mismo martes al terminar.<br>
      Si llegan los ${activos.length} registrados: <b>$${(bonoCap * activos.length).toLocaleString("es-MX")}</b> en efectivo ese día.</p>
    </div>
    <div class="card">
      <h3>Puntualidad</h3>
      <div class="big">$${bonoPunt.toLocaleString("es-MX")} <span style="font-size:15px;color:var(--tinta-3)">por día</span></div>
      <p>Hasta <b>$${(bonoPunt * 5).toLocaleString("es-MX")}</b> por persona, si asiste los 5 días puntual.<br>Se paga el último día.</p>
    </div>
    <div class="card">
      <h3>Referidos</h3>
      <div class="big">$${bonoRef.toLocaleString("es-MX")} <span style="font-size:15px;color:var(--tinta-3)">c/u</span></div>
      <p>Pendientes: <b>$${pendientes.toLocaleString("es-MX")}</b> (esperan que el invitado llegue el martes)<br>
      Por pagar: <b>$${porPagar.toLocaleString("es-MX")}</b></p>
    </div>
  </div>

  ${Object.keys(referidos).length ? `
  <h2>Quién invitó a quién</h2>
  <p class="lede">El bono se libera cuando el invitado asiste a la capacitación.</p>
  <div class="cards">
    ${Object.entries(referidos).map(([folio, lista]) => `
      <div class="card">
        <h3><span class="mono">${esc(folio)}</span> ${esc(nombrePorFolio[folio] || "")}</h3>
        <div class="big">$${(bonoRef * lista.length).toLocaleString("es-MX")}</div>
        <p>Invitó a ${lista.length}:<br>${lista.map((c) => `<span class="pill">${esc(c.folio)} ${esc((c.nombre || "").split(" ").slice(0, 2).join(" "))}${c.asistio_capacitacion ? " ✓" : ""}</span>`).join("")}</p>
      </div>`).join("")}
  </div>` : ""}

  ${huecos.length ? `
  <h2>Datos que faltan</h2>
  <p class="lede">Hay que completarlos antes del martes: sin talla no se pide uniforme, y sin INE no entran a la capacitación.</p>
  <div class="tw"><table style="min-width:640px"><thead><tr>
    <th style="width:60px">Folio</th><th>Nombre</th><th>Teléfono</th><th>Qué falta</th></tr></thead><tbody>
    ${huecos.map((c) => {
      const f = [];
      if (!c.talla_playera) f.push("talla");
      if (c.tiene_ine !== true) f.push("INE");
      if (!c.edad) f.push("edad");
      if (!c.colonia) f.push("colonia");
      return `<tr><td class="mono folio">${val(c.folio)}</td><td class="nom">${val(c.nombre)}</td>
        <td class="mono">${tel(c.telefono)}</td><td><span class="alerta">${f.join(", ")}</span></td></tr>`;
    }).join("")}
  </tbody></table></div>` : ""}

  <h2>Todos los registrados <span style="font-weight:400;color:var(--tinta-3);font-size:14px">${candidatos.length} en total</span></h2>
  <p class="lede">Ordenados por folio. Las filas atenuadas son bajas.</p>
  <div class="tw"><table><thead><tr>
    <th style="width:56px">Folio</th><th>Nombre</th><th style="width:110px">Teléfono</th>
    <th style="width:48px">Edad</th><th>Colonia / municipio</th><th style="width:52px">Talla</th>
    <th style="width:48px">INE</th><th style="width:104px">Estatus</th><th style="width:120px">Lo invitó</th><th>Notas</th>
  </tr></thead><tbody>
    ${candidatos.map(filaCand).join("")}
  </tbody></table></div>

  <footer>
    Datos en vivo desde Supabase · proyecto <span class="mono">activaciones-personal</span> · campaña <span class="mono">${esc(CAMPANA)}</span><br>
    Esta página se genera en el servidor: la llave de la base nunca llega al navegador. No se indexa en buscadores.
  </footer>
</div></body></html>`;
}

function paginaError(titulo, detalle) {
  return `<!doctype html><html lang="es-MX"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>${esc(titulo)}</title>
<style>body{font-family:system-ui,-apple-system,sans-serif;background:#FFF6EC;color:#14231A;
display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0;padding:24px}
.c{max-width:520px;background:#fff;border:1px solid #E7DFD4;border-radius:12px;padding:26px}
h1{font-size:20px;margin:0 0 10px}p{margin:0;color:#5A6B60;line-height:1.6}
code{background:#FFF6EC;border:1px solid #E7DFD4;border-radius:4px;padding:1px 5px;font-size:13px}</style>
</head><body><div class="c"><h1>${esc(titulo)}</h1><p>${detalle}</p></div></body></html>`;
}
