-- ============================================================
-- 16 · Pase de lista vigente + regla de negocio (2026-09-20)
--
-- Este archivo reemplaza en la práctica a 08_pase_de_lista.sql, que
-- se quedó desactualizado (esa versión vieja escribía en la tabla
-- `asistencia`, de la campaña SEP26; hace tiempo se migró a escribir
-- en `presencia`, la de la campaña vigente, directo en Supabase sin
-- pasar por un archivo de este repo). Aquí queda documentada tal
-- cual está hoy en producción, para que no se pierda el rastro.
--
-- REGLA DE NEGOCIO (confirmada por Alberto, 2026-09-20):
--
--   1) pase_lista() -- lo teclea Alberto o el equipo, A MANO, viendo
--      a la persona -- sirve para confirmar el turno y que se pague
--      la jornada de $400. NUNCA da el bono de puntualidad: a_tiempo
--      se guarda siempre en false.
--
--   2) registrar_presencia() (público/checar.html, ver 14 y 15) --
--      lo marca cada promotor DESDE SU CELULAR, con GPS -- es lo
--      único que puede dar el bono de $50 de puntualidad, y solo si
--      marca dentro de la ventana configurada (entrada 8am-2pm,
--      salida 7-9pm en la etapa actual).
--
--   3) Juntos sirven de DOBLE CHECK: comparar la hora que la persona
--      marcó sola (presencia.origen='gps') contra la hora en que
--      Alberto la vio y le pasó lista a mano
--      (presencia.origen='pase_lista') para confirmar que de verdad
--      llegó temprano y no se fue antes.
--
--   Nota: jornadas_sin_pagar()/marcar_pagado() cuentan como
--   "trabajado ese día" cualquier entrada en v_jornadas, sin importar
--   el origen (gps o pase_lista) -- hoy el pago de $400 NO exige
--   específicamente el pase de lista de Alberto, con cualquiera de
--   los dos registros basta. Si se quiere que el pago dependa
--   exclusivamente del pase de lista manual, hay que agregar
--   "and origen = 'pase_lista'" en esas dos funciones.
-- ============================================================

create or replace function public.pase_lista(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_folio text; v_tipo text; v_dia date;
  v_c record; v_eq text; v_ya timestamptz; v_hora text;
  v_repetido boolean := false;
  v_esperados int; v_presentes int;
  v_par record; v_tarifa numeric; v_ayer date; v_vino_ayer boolean;
  v_pendientes jsonb; v_total numeric;
  v_adelanto numeric; v_lista_ade jsonb; v_neto numeric;
  v_inscrito boolean; v_a_tiempo boolean;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;

  select pa.* into v_par from parametros pa where pa.registro_abierto
   order by pa.fecha_inicio desc limit 1;
  if v_par.campana is null then
    select pa.* into v_par from parametros pa order by pa.fecha_inicio desc limit 1;
  end if;

  v_folio := normalizar_folio(p->>'folio');
  v_tipo  := lower(coalesce(nullif(p->>'tipo',''), 'entrada'));
  v_dia   := coalesce(nullif(p->>'dia','')::date,
                      (now() at time zone 'America/Monterrey')::date);

  if v_folio is null then
    return jsonb_build_object('ok', false, 'motivo', 'FOLIO_INVALIDO');
  end if;
  if v_tipo not in ('entrada','salida') then
    return jsonb_build_object('ok', false, 'motivo', 'TIPO_INVALIDO');
  end if;

  select * into v_c from candidatos where folio = v_folio;
  if v_c is null then
    return jsonb_build_object('ok', false, 'motivo', 'NO_EXISTE', 'folio', v_folio);
  end if;
  if v_c.estatus = 'baja' then
    return jsonb_build_object('ok', false, 'motivo', 'DADO_DE_BAJA',
      'folio', v_folio, 'nombre', v_c.nombre);
  end if;

  v_inscrito := exists (select 1 from participaciones
                        where folio = v_folio and campana = v_par.campana);

  select nombre into v_eq from equipos where id = v_c.equipo_id;

  select momento into v_ya from v_jornadas
   where folio = v_folio and dia = v_dia and tipo = v_tipo
     and campana = v_par.campana;

  if v_ya is null then
    -- Una marca a mano nunca da puntualidad: esa la gana la persona
    -- marcando ella misma, en el punto y en hora.
    v_a_tiempo := false;
    insert into presencia (folio, campana, dia, tipo, momento, punto,
                           dentro, a_tiempo, origen)
    values (v_folio, v_par.campana, v_dia, v_tipo, now(),
            coalesce(v_c.punto_asignado, 'cumbres-e2'), true, v_a_tiempo, 'pase_lista')
    on conflict (folio, dia, tipo) do nothing;
    v_ya := now();
    perform public.anotar('pase_lista_' || v_tipo, v_folio,
      jsonb_build_object('persona', v_c.nombre, 'dia', v_dia, 'campana', v_par.campana));
  else
    v_repetido := true;
  end if;

  v_hora := to_char(v_ya at time zone 'America/Monterrey', 'HH12:MI am');

  select count(*) into v_esperados
    from participaciones pp join candidatos cc on cc.folio = pp.folio
   where pp.campana = v_par.campana and cc.estatus <> 'baja';
  select count(distinct j.folio) into v_presentes
    from v_jornadas j join participaciones pp
      on pp.folio = j.folio and pp.campana = j.campana
   where j.dia = v_dia and j.tipo = 'entrada' and j.campana = v_par.campana;

  v_tarifa := coalesce(v_par.pago_por_dia, 400);

  v_ayer := v_dia - 1;
  v_vino_ayer := exists (select 1 from v_jornadas
                          where folio = v_folio and dia = v_ayer and tipo = 'entrada');

  select coalesce(jsonb_agg(jsonb_build_object('dia', d.dia, 'monto', v_tarifa)
                            order by d.dia), '[]'::jsonb),
         coalesce(count(*) * v_tarifa, 0)
    into v_pendientes, v_total
  from (select distinct dia from v_jornadas
         where folio = v_folio and tipo = 'entrada' and dia < v_dia) d
  where not exists (select 1 from pagos g
                     where g.folio = v_folio and g.dia = d.dia and g.concepto = 'jornada');

  select coalesce(sum(monto), 0),
         coalesce(jsonb_agg(jsonb_build_object(
           'id', id, 'monto', monto, 'motivo', motivo,
           'cuando', to_char(entregado_en at time zone 'America/Monterrey', 'DD/MM HH12:MI am'))
           order by entregado_en), '[]'::jsonb)
    into v_adelanto, v_lista_ade
  from adelantos where folio = v_folio and saldado_en is null;

  v_neto := greatest(v_total - v_adelanto, 0);

  return jsonb_build_object(
    'ok', true, 'repetido', v_repetido,
    'folio', v_folio, 'nombre', v_c.nombre, 'tipo', v_tipo,
    'hora', v_hora, 'dia', v_dia,
    'campana', v_par.campana, 'inscrito', v_inscrito,
    'equipo', v_eq, 'equipo_id', v_c.equipo_id,
    'talla', v_c.talla_playera, 'telefono', v_c.telefono,
    'punto', v_c.punto_asignado,
    'fue_capacitacion', coalesce(v_c.asistio_capacitacion, false),
    'esperados', v_esperados, 'presentes', v_presentes,
    'ayer', jsonb_build_object('dia', v_ayer, 'vino', v_vino_ayer),
    'por_pagar', v_pendientes, 'total_por_pagar', v_total,
    'adelantado', v_adelanto, 'adelantos', v_lista_ade, 'neto', v_neto,
    'tarifa', v_tarifa);
end; $fn$;

create or replace function public.pase_lista_dia(p_dia date default null) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $fn$
declare v_dia date; v_ayer date; v_par record; v_tarifa numeric; v jsonb;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;

  select pa.* into v_par from parametros pa where pa.registro_abierto
   order by pa.fecha_inicio desc limit 1;
  if v_par.campana is null then
    select pa.* into v_par from parametros pa order by pa.fecha_inicio desc limit 1;
  end if;

  v_dia  := coalesce(p_dia, (now() at time zone 'America/Monterrey')::date);
  v_ayer := v_dia - 1;
  v_tarifa := coalesce(v_par.pago_por_dia, 400);

  select jsonb_build_object(
    'dia', v_dia, 'ayer', v_ayer, 'tarifa', v_tarifa,
    'campana', v_par.campana, 'evento', v_par.nombre_evento,
    'presentes', (
      select coalesce(jsonb_agg(x order by x->>'momento' desc), '[]'::jsonb) from (
        select jsonb_build_object(
                 'folio', c.folio, 'nombre', c.nombre, 'equipo', e.nombre,
                 'talla', c.talla_playera, 'telefono', c.telefono,
                 'origen', j.origen, 'momento', j.momento,
                 'hora', to_char(j.momento at time zone 'America/Monterrey', 'HH12:MI am'),
                 'a_tiempo', j.a_tiempo,
                 'salida', (select to_char(s.momento at time zone 'America/Monterrey', 'HH12:MI am')
                              from v_jornadas s
                             where s.folio = c.folio and s.dia = v_dia and s.tipo = 'salida'
                               and s.campana = v_par.campana),
                 'vino_ayer', exists (select 1 from v_jornadas y
                                       where y.folio = c.folio and y.dia = v_ayer and y.tipo = 'entrada'),
                 'adelantado', public.adelanto_abierto(c.folio),
                 'por_pagar', greatest(public.jornadas_sin_pagar(c.folio, v_dia, v_tarifa)
                                       - public.adelanto_abierto(c.folio), 0)
               ) as x
        from v_jornadas j
        join candidatos c on c.folio = j.folio
        left join equipos e on e.id = c.equipo_id
        where j.dia = v_dia and j.tipo = 'entrada' and j.campana = v_par.campana
      ) t),
    'faltantes', (
      select coalesce(jsonb_agg(x order by x->>'folio'), '[]'::jsonb) from (
        select jsonb_build_object(
                 'folio', c.folio, 'nombre', c.nombre, 'equipo', e.nombre,
                 'telefono', c.telefono,
                 'vino_ayer', exists (select 1 from v_jornadas y
                                       where y.folio = c.folio and y.dia = v_ayer and y.tipo = 'entrada'),
                 'adelantado', public.adelanto_abierto(c.folio),
                 'por_pagar', greatest(public.jornadas_sin_pagar(c.folio, v_dia, v_tarifa)
                                       - public.adelanto_abierto(c.folio), 0)
               ) as x
        from participaciones pp
        join candidatos c on c.folio = pp.folio
        left join equipos e on e.id = c.equipo_id
        where pp.campana = v_par.campana and c.estatus <> 'baja'
          and not exists (select 1 from v_jornadas j
                           where j.folio = c.folio and j.dia = v_dia
                             and j.tipo = 'entrada' and j.campana = v_par.campana)
      ) t)
  ) into v;
  return v;
end; $fn$;

create or replace function public.jornadas_sin_pagar(p_folio text, p_dia date, p_tarifa numeric)
returns numeric
language sql stable security definer set search_path to 'public' as $fn$
  select coalesce(sum(public.tarifa_de(p_folio, d.dia, p_tarifa)), 0)
  from (select distinct dia from v_jornadas
         where folio = p_folio and tipo = 'entrada' and dia < p_dia) d
  where not exists (select 1 from pagos g
                     where g.folio = p_folio and g.dia = d.dia and g.concepto = 'jornada');
$fn$;

create or replace function public.marcar_pagado(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_folio text; v_hoy date; v_base numeric; v_uid uuid := auth.uid();
  v_dias date[]; v_n int := 0; v_bruto numeric := 0; v_nom text; v_d date; v_t numeric;
  v_resta numeric; v_desc numeric := 0; v_a record;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;
  v_folio := normalizar_folio(p->>'folio');
  if v_folio is null then return jsonb_build_object('ok', false, 'motivo', 'FOLIO_INVALIDO'); end if;
  select nombre into v_nom from candidatos where folio = v_folio;
  if v_nom is null then return jsonb_build_object('ok', false, 'motivo', 'NO_EXISTE', 'folio', v_folio); end if;

  v_hoy := coalesce(nullif(p->>'hoy','')::date, (now() at time zone 'America/Monterrey')::date);
  select pago_por_dia into v_base from parametros where registro_abierto
   order by fecha_inicio desc limit 1;
  v_base := coalesce(v_base, 400);

  if p ? 'dias' and jsonb_typeof(p->'dias') = 'array' then
    select array_agg(x::date) into v_dias from jsonb_array_elements_text(p->'dias') x;
  else
    select array_agg(a.dia) into v_dias
      from (select distinct dia from v_jornadas
             where folio = v_folio and tipo = 'entrada' and dia < v_hoy) a
     where not exists (select 1 from pagos g
                        where g.folio = v_folio and g.dia = a.dia and g.concepto = 'jornada');
  end if;

  if v_dias is null or array_length(v_dias,1) is null then
    return jsonb_build_object('ok', false, 'motivo', 'NADA_QUE_PAGAR',
      'folio', v_folio, 'nombre', v_nom);
  end if;

  foreach v_d in array v_dias loop
    v_t := public.tarifa_de(v_folio, v_d, v_base);
    insert into pagos (folio, dia, concepto, monto, pagado_por)
    values (v_folio, v_d, 'jornada', v_t, v_uid)
    on conflict (folio, dia, concepto) do nothing;
    if found then v_n := v_n + 1; v_bruto := v_bruto + v_t; end if;
  end loop;

  v_resta := v_bruto;
  for v_a in select id, monto from adelantos
              where folio = v_folio and saldado_en is null order by entregado_en loop
    exit when v_resta <= 0;
    if v_a.monto <= v_resta then
      update adelantos set saldado_en = now() where id = v_a.id;
      v_resta := v_resta - v_a.monto; v_desc := v_desc + v_a.monto;
    else
      update adelantos set monto = monto - v_resta where id = v_a.id;
      insert into adelantos (folio, monto, motivo, entregado_por, saldado_en)
      values (v_folio, v_resta, 'parte saldada', v_uid, now());
      v_desc := v_desc + v_resta; v_resta := 0;
    end if;
  end loop;

  if v_n > 0 then
    perform public.anotar('pago_jornada', v_folio,
      jsonb_build_object('persona', v_nom, 'dias', to_jsonb(v_dias),
                         'bruto', v_bruto, 'adelanto_descontado', v_desc,
                         'neto', v_bruto - v_desc));
  end if;

  return jsonb_build_object('ok', true, 'folio', v_folio, 'nombre', v_nom,
    'dias_pagados', v_n, 'bruto', v_bruto, 'descontado', v_desc,
    'neto', v_bruto - v_desc, 'total', v_bruto - v_desc);
end; $fn$;

comment on function public.registrar_presencia(jsonb) is
  'Auto-registro del promotor desde su celular (GPS). Único origen que puede dar el bono de puntualidad de $50 (a_tiempo se calcula contra la ventana de parametros). Ver pase_lista() para el registro manual, que nunca da bono.';

comment on function public.pase_lista(jsonb) is
  'Pase de lista manual (Alberto/equipo). Confirma el turno para el pago de $400 y sirve de doble check contra el auto-registro GPS del promotor. a_tiempo se guarda siempre en false: una marca a mano nunca da el bono de puntualidad, eso solo lo gana la persona marcando ella misma a tiempo.';

comment on view public.v_jornadas is
  'Une asistencia (campaña vieja) y presencia (campaña actual). jornadas_sin_pagar()/marcar_pagado() usan esta vista para decidir qué días se pagan a $400: cuentan cualquier entrada, sea origen gps o pase_lista.';
