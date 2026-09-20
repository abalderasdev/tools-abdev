-- Permite marcar entrada desde temprano (por defecto 8:00 am), sin perder
-- el bono de puntualidad mientras se marque antes de la hora límite
-- (hora_inicio + tolerancia_entrada_min). Antes solo dejaba marcar entrada
-- a partir de hora_inicio exacta, bloqueando a quien llegaba antes.
-- También corrige que una entrada tarde (después del límite del bono)
-- se rechazaba por completo en vez de registrarse sin bono, como decía
-- el propio mensaje de error.

alter table public.parametros
  add column if not exists apertura_entrada time;

update public.parametros
  set apertura_entrada = '08:00:00'
  where apertura_entrada is null;

create or replace function public.registrar_presencia(p jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_f text; v_campana text; v_dia date; v_tipo text;
  v_lat double precision; v_lon double precision; v_prec double precision;
  v_punto record; v_par record; v_dist double precision;
  v_ahora timestamptz := now(); v_hora time;
  v_nombre text; v_equipo text; v_abre time; v_cierra time; v_a_tiempo boolean;
begin
  v_f := identificar(p->>'folio', p->>'tel4');
  if v_f is null then
    return jsonb_build_object('ok', false, 'motivo', 'IDENTIDAD',
      'mensaje', 'Folio o teléfono incorrectos. Revisa tus datos.');
  end if;

  v_tipo := coalesce(p->>'tipo','entrada');
  if v_tipo not in ('entrada','salida') then v_tipo := 'entrada'; end if;

  select pa.* into v_par from parametros pa where pa.registro_abierto
   order by pa.fecha_inicio desc limit 1;
  v_campana := v_par.campana;
  v_dia  := (v_ahora at time zone 'America/Monterrey')::date;
  v_hora := (v_ahora at time zone 'America/Monterrey')::time;

  if v_dia < v_par.fecha_inicio or v_dia > v_par.fecha_fin then
    return jsonb_build_object('ok', false, 'motivo', 'FUERA_DE_FECHAS',
      'mensaje', 'Hoy no hay activación.');
  end if;

  if v_dia = any(coalesce(v_par.descansos, '{}')) then
    return jsonb_build_object('ok', false, 'motivo', 'DIA_DE_DESCANSO',
      'mensaje', 'Hoy no se trabaja, es día de descanso. Nos vemos mañana.');
  end if;

  v_a_tiempo := true;

  if v_tipo = 'entrada' then
    v_abre   := coalesce(v_par.apertura_entrada, v_par.hora_inicio);
    v_cierra := v_par.hora_inicio + (v_par.tolerancia_entrada_min || ' minutes')::interval;
    if v_hora < v_abre then
      return jsonb_build_object('ok', false, 'motivo', 'AUN_NO_ABRE',
        'mensaje', 'Todavía no puedes marcar entrada. Se abre a la ' ||
                   to_char(v_abre, 'HH12:MI am') || '.');
    end if;
    v_a_tiempo := v_hora <= v_cierra;
  else
    v_abre := v_par.hora_fin - (coalesce(v_par.tolerancia_salida_min,0) || ' minutes')::interval;
    if v_hora < v_abre then
      return jsonb_build_object('ok', false, 'motivo', 'AUN_NO_SALE',
        'mensaje', 'Todavía no es hora de salida. Puedes marcar a partir de las ' ||
                   to_char(v_abre, 'HH12:MI am') || '.');
    end if;
  end if;

  select pt.* into v_punto from puntos pt
  where pt.clave = coalesce(
    (select e.punto_clave from equipos e join candidatos c on c.equipo_id = e.id
      where c.folio = v_f limit 1),
    (select clave from puntos where coalesce(campana, v_campana) = v_campana limit 1))
  limit 1;

  if v_punto.clave is null or v_punto.lat is null then
    return jsonb_build_object('ok', false, 'motivo', 'SIN_PUNTO',
      'mensaje', 'Todavía no hay punto configurado. Avísale a tu coordinador.');
  end if;

  v_lat := (p->>'lat')::double precision;
  v_lon := (p->>'lon')::double precision;
  v_prec := nullif(p->>'precision','')::double precision;
  if v_lat is null or v_lon is null then
    return jsonb_build_object('ok', false, 'motivo', 'SIN_UBICACION',
      'mensaje', 'Necesitamos tu ubicación. Activa el GPS y da permiso.');
  end if;

  v_dist := distancia_m(v_lat, v_lon, v_punto.lat, v_punto.lon);
  if v_dist > (coalesce(v_punto.radio_m, v_par.radio_default_m) + coalesce(v_prec,0)) then
    return jsonb_build_object('ok', false, 'motivo', 'FUERA_DEL_PUNTO',
      'distancia', round(v_dist)::int, 'punto', v_punto.nombre,
      'mensaje', 'Estás a ' || round(v_dist)::int || ' metros de ' || v_punto.nombre ||
                 '. Acércate al punto y vuelve a intentar.');
  end if;

  insert into presencia (folio, campana, dia, tipo, momento, lat, lon, precision_m,
                         punto, distancia_m, dentro, a_tiempo, origen)
  values (v_f, v_campana, v_dia, v_tipo, v_ahora, v_lat, v_lon, v_prec,
          v_punto.clave, v_dist, true, v_a_tiempo, 'gps')
  on conflict (folio, dia, tipo) do nothing;

  select split_part(nombre,' ',1) into v_nombre from candidatos where folio = v_f;
  select e.nombre into v_equipo from equipos e
    join candidatos c on c.equipo_id = e.id where c.folio = v_f limit 1;

  return jsonb_build_object('ok', true, 'folio', v_f, 'nombre', v_nombre, 'tipo', v_tipo,
    'punto', v_punto.nombre, 'equipo', coalesce(v_equipo,'Sin equipo'),
    'distancia', round(v_dist)::int, 'a_tiempo', v_a_tiempo,
    'hora', to_char(v_ahora at time zone 'America/Monterrey', 'HH12:MI am'),
    'mensaje', case
      when v_tipo = 'entrada' and not v_a_tiempo then
        'Quedó registrada tu entrada, pero después de la hora límite del bono de puntualidad.'
      else
        'Listo, quedó registrada tu ' || v_tipo || '. Cuenta para tu bono.'
      end);
end; $function$;

create or replace function public.estado_presencia(p_folio text, p_tel4 text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_f text; v_dia date; v_par record; v_nombre text; v_equipo text; v_dias int;
begin
  v_f := identificar(p_folio, p_tel4);
  if v_f is null then return jsonb_build_object('ok', false); end if;
  v_dia := (now() at time zone 'America/Monterrey')::date;
  select * into v_par from parametros where registro_abierto order by fecha_inicio desc limit 1;
  select split_part(nombre,' ',1) into v_nombre from candidatos where folio = v_f;
  select e.nombre into v_equipo from equipos e
    join candidatos c on c.equipo_id = e.id where c.folio = v_f limit 1;

  -- Días con bono: los ganados marcando entrada y salida, más los
  -- que el coordinador acreditó a mano.
  select count(*) into v_dias from (
    select dia from presencia
     where folio = v_f and campana = v_par.campana and a_tiempo
     group by dia
    having count(*) filter (where tipo='entrada') > 0
       and count(*) filter (where tipo='salida')  > 0
    union
    select dia from bono_dia where folio = v_f and campana = v_par.campana
  ) x;

  return jsonb_build_object(
    'ok', true, 'folio', v_f, 'nombre', v_nombre,
    'equipo', coalesce(v_equipo, 'Sin equipo asignado'),
    'horario', to_char(v_par.hora_inicio,'HH24:MI') || ' a ' || to_char(v_par.hora_fin,'HH24:MI'),
    'abre_entrada', to_char(coalesce(v_par.apertura_entrada, v_par.hora_inicio), 'HH12:MI am'),
    'cierra_entrada', to_char(v_par.hora_inicio + (v_par.tolerancia_entrada_min || ' minutes')::interval, 'HH12:MI am'),
    'abre_salida',  to_char(v_par.hora_fin - (coalesce(v_par.tolerancia_salida_min,0) || ' minutes')::interval, 'HH12:MI am'),
    'entrada', (select to_char(momento at time zone 'America/Monterrey','HH12:MI am')
                from presencia where folio=v_f and dia=v_dia and tipo='entrada'),
    'salida',  (select to_char(momento at time zone 'America/Monterrey','HH12:MI am')
                from presencia where folio=v_f and dia=v_dia and tipo='salida'),
    'bono_hoy', exists (select 1 from bono_dia where folio=v_f and campana=v_par.campana and dia=v_dia),
    'dias_con_bono', v_dias,
    'bono_por_dia', v_par.bono_puntualidad);
end; $function$;
