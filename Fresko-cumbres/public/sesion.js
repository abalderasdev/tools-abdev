/* ============================================================
   Sesión del personal, compartida por /pase, /lista, /puestos,
   /dash y /recordatorio.

   Antes cada pantalla tenía su propia copia y todas fallaban igual:
   guardaban solo el access_token, que Supabase vence a la hora, y en
   sessionStorage, que muere al cerrar la pestaña. En el celular eso
   significaba volver a teclear correo y contraseña a media jornada.

   Aquí se guarda también el refresh_token y se renueva solo antes de
   vencer, en localStorage, para que el teléfono quede dentro por días.

   El refresh_token vive en el teléfono: quien lo tenga desbloqueado
   entra. Por eso "Salir" revoca la sesión del lado del servidor, no
   solo borra la copia local.
   ============================================================ */
(function (global) {
  "use strict";

  var URL_BASE = "https://eykfdnoczpwjccunzfgh.supabase.co";
  var LLAVE_PUB = "sb_publishable_Q_fNBD3xtsMtsNtpp3h0wg_j3dkROng";
  var CAJON = "fresko_sesion";

  // Se renueva un minuto antes de vencer: da margen para una petición
  // lenta sin que el servidor la rechace a medio camino.
  var MARGEN_MS = 60000;

  var enVuelo = null;   // renovación en curso, para no lanzar varias a la vez

  function guardar(s) {
    try { localStorage.setItem(CAJON, JSON.stringify(s)); } catch (e) {}
  }

  function leer() {
    try { return JSON.parse(localStorage.getItem(CAJON) || "null"); }
    catch (e) { return null; }
  }

  function tirar() {
    try { localStorage.removeItem(CAJON); } catch (e) {}
    // Limpia también el cajón viejo, para que nadie quede a medias
    // entre la sesión anterior y esta.
    try { sessionStorage.removeItem(CAJON); } catch (e) {}
  }

  function deLaRespuesta(d) {
    return {
      access_token: d.access_token,
      refresh_token: d.refresh_token || null,
      email: (d.user && d.user.email) || null,
      expira: Date.now() + ((d.expires_in || 3600) * 1000)
    };
  }

  function pedirToken(cuerpo, tipo) {
    return fetch(URL_BASE + "/auth/v1/token?grant_type=" + tipo, {
      method: "POST",
      headers: { apikey: LLAVE_PUB, "Content-Type": "application/json" },
      body: JSON.stringify(cuerpo)
    }).then(function (r) {
      return r.json().then(function (d) {
        if (!r.ok) {
          var e = new Error(d.error_description || d.msg || d.message ||
                            "No se pudo iniciar sesión");
          e.status = r.status;
          throw e;
        }
        return d;
      });
    });
  }

  function entrar(email, password) {
    return pedirToken({ email: email, password: password }, "password")
      .then(function (d) {
        var s = deLaRespuesta(d);
        guardar(s);
        return s;
      });
  }

  function renovar(s) {
    if (enVuelo) return enVuelo;
    enVuelo = pedirToken({ refresh_token: s.refresh_token }, "refresh_token")
      .then(function (d) {
        var nueva = deLaRespuesta(d);
        // Supabase puede devolver el mismo refresh_token; si no lo manda,
        // conservamos el que ya teníamos para no quedarnos sin él.
        if (!nueva.refresh_token) nueva.refresh_token = s.refresh_token;
        if (!nueva.email) nueva.email = s.email;
        guardar(nueva);
        return nueva;
      })
      .catch(function (e) {
        // Refresh vencido o revocado: hay que volver a entrar.
        tirar();
        var err = new Error("SESION_VENCIDA");
        err.vencida = true;
        throw err;
      })
      .then(function (v) { enVuelo = null; return v; },
            function (e) { enVuelo = null; throw e; });
    return enVuelo;
  }

  // Devuelve un access_token utilizable, renovando si hace falta.
  function token() {
    var s = leer();
    if (!s || !s.access_token) return Promise.reject(vencida());
    if (s.expira > Date.now() + MARGEN_MS) return Promise.resolve(s.access_token);
    if (!s.refresh_token) { tirar(); return Promise.reject(vencida()); }
    return renovar(s).then(function (n) { return n.access_token; });
  }

  function vencida() {
    var e = new Error("SESION_VENCIDA");
    e.vencida = true;
    return e;
  }

  function hay() {
    var s = leer();
    return !!(s && s.access_token && (s.refresh_token || s.expira > Date.now()));
  }

  function correo() {
    var s = leer();
    return s && s.email;
  }

  function salir() {
    var s = leer();
    tirar();
    if (!s || !s.access_token) return Promise.resolve();
    // Revoca del lado del servidor; si falla, la copia local ya se fue.
    return fetch(URL_BASE + "/auth/v1/logout", {
      method: "POST",
      headers: { apikey: LLAVE_PUB, Authorization: "Bearer " + s.access_token }
    }).catch(function () {}).then(function () {});
  }

  function cabeceras(tk, extra) {
    var h = { apikey: LLAVE_PUB, Authorization: "Bearer " + tk };
    if (extra) for (var k in extra) h[k] = extra[k];
    return h;
  }

  // Llama un RPC con la sesión vigente. Si el token se venció justo
  // ahora, lo renueva y reintenta una vez.
  function rpc(fn, cuerpo, reintento) {
    return token().then(function (tk) {
      return fetch(URL_BASE + "/rest/v1/rpc/" + fn, {
        method: "POST",
        headers: cabeceras(tk, { "Content-Type": "application/json" }),
        body: JSON.stringify(cuerpo || {})
      }).then(function (r) {
        if (r.status === 401 && !reintento) {
          var s = leer();
          if (s && s.refresh_token) {
            return renovar(s).then(function () { return rpc(fn, cuerpo, true); });
          }
        }
        return r.json().then(function (d) {
          if (!r.ok) throw new Error(d.message || d.msg || ("error " + r.status));
          return d;
        });
      });
    });
  }

  // Lectura directa a PostgREST (tablas y vistas).
  function traer(consulta, reintento) {
    return token().then(function (tk) {
      return fetch(URL_BASE + "/rest/v1/" + consulta, { headers: cabeceras(tk) })
        .then(function (r) {
          if (r.status === 401 && !reintento) {
            var s = leer();
            if (s && s.refresh_token) {
              return renovar(s).then(function () { return traer(consulta, true); });
            }
          }
          if (!r.ok) throw new Error("No se pudo leer (" + r.status + ")");
          return r.json();
        });
    });
  }

  global.Sesion = {
    URL: URL_BASE,
    LLAVE: LLAVE_PUB,
    entrar: entrar,
    token: token,
    hay: hay,
    correo: correo,
    salir: salir,
    rpc: rpc,
    traer: traer,
    cabeceras: cabeceras
  };
})(window);
