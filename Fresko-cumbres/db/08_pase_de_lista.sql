-- ============================================================
-- 08 · Pase de lista por folio (operado por el personal de equipo)
--
-- /checar lo marca la persona desde su celular y valida el geocerco.
-- Esto es lo contrario: la persona dice su folio, el operador lo
-- teclea en /pase y queda el registro. Sin GPS, sin depender de que
-- cada quien traiga datos o batería.
--
-- Escribe en la misma tabla `asistencia` que /checar, con
-- origen = 'pase_lista', para que /puestos y el dashboard no
-- distingan de dónde vino el registro.
-- ============================================================

create or replace function public.pase_lista(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_folio text; v_tipo text; v_dia date;
  v_c record; v_eq text; v_ya timestamptz; v_hora text;
  v_repetido boolean := false;
  v_esperados int; v_presentes int;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;

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

  select nombre into v_eq from equipos where id = v_c.equipo_id;

  select momento into v_ya from asistencia
   where folio = v_folio and dia = v_dia and tipo = v_tipo;

  -- Idempotente: pasar dos veces el mismo folio no duplica ni pisa la hora.
  if v_ya is null then
    insert into asistencia (folio, dia, tipo, punto, origen)
    values (v_folio, v_dia, v_tipo, coalesce(v_c.punto_asignado,'tienda'), 'pase_lista');
    v_ya := now();
    perform public.anotar('pase_lista_' || v_tipo, v_folio,
      jsonb_build_object('persona', v_c.nombre, 'dia', v_dia));
  else
    v_repetido := true;
  end if;

  v_hora := to_char(v_ya at time zone 'America/Monterrey', 'HH12:MI am');

  select count(*) into v_esperados
    from candidatos where asistio_capacitacion and estatus <> 'baja';
  select count(*) into v_presentes
    from asistencia a join candidatos c on c.folio = a.folio
   where a.dia = v_dia and a.tipo = 'entrada'
     and c.asistio_capacitacion and c.estatus <> 'baja';

  return jsonb_build_object(
    'ok', true, 'repetido', v_repetido,
    'folio', v_folio, 'nombre', v_c.nombre, 'tipo', v_tipo,
    'hora', v_hora, 'dia', v_dia,
    'equipo', v_eq, 'equipo_id', v_c.equipo_id,
    'talla', v_c.talla_playera, 'telefono', v_c.telefono,
    'punto', v_c.punto_asignado,
    'fue_capacitacion', coalesce(v_c.asistio_capacitacion, false),
    'esperados', v_esperados, 'presentes', v_presentes);
end; $fn$;

-- ------------------------------------------------------------
-- Estado del día: quién ya llegó (con su hora) y quién falta.
-- La plantilla esperada son los que asistieron a la capacitación
-- y no están dados de baja.
-- ------------------------------------------------------------
create or replace function public.pase_lista_dia(p_dia date default null) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $fn$
declare v_dia date; v jsonb;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;
  v_dia := coalesce(p_dia, (now() at time zone 'America/Monterrey')::date);

  select jsonb_build_object(
    'dia', v_dia,
    'presentes', (
      select coalesce(jsonb_agg(x order by x->>'momento' desc), '[]'::jsonb) from (
        select jsonb_build_object(
                 'folio', c.folio, 'nombre', c.nombre, 'equipo', e.nombre,
                 'talla', c.talla_playera, 'telefono', c.telefono,
                 'origen', a.origen, 'momento', a.momento,
                 'hora', to_char(a.momento at time zone 'America/Monterrey', 'HH12:MI am'),
                 'salida', (select to_char(s.momento at time zone 'America/Monterrey', 'HH12:MI am')
                              from asistencia s
                             where s.folio = c.folio and s.dia = v_dia and s.tipo = 'salida')
               ) as x
        from asistencia a
        join candidatos c on c.folio = a.folio
        left join equipos e on e.id = c.equipo_id
        where a.dia = v_dia and a.tipo = 'entrada'
      ) t),
    'faltantes', (
      select coalesce(jsonb_agg(x order by x->>'folio'), '[]'::jsonb) from (
        select jsonb_build_object(
                 'folio', c.folio, 'nombre', c.nombre, 'equipo', e.nombre,
                 'telefono', c.telefono) as x
        from candidatos c
        left join equipos e on e.id = c.equipo_id
        where c.asistio_capacitacion and c.estatus <> 'baja'
          and not exists (select 1 from asistencia a
                           where a.folio = c.folio and a.dia = v_dia and a.tipo = 'entrada')
      ) t)
  ) into v;
  return v;
end; $fn$;

-- ------------------------------------------------------------
-- Deshacer: se tecleó el folio equivocado.
-- ------------------------------------------------------------
create or replace function public.deshacer_pase(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $fn$
declare v_folio text; v_tipo text; v_dia date; v_n int; v_nom text;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;
  v_folio := normalizar_folio(p->>'folio');
  v_tipo  := lower(coalesce(nullif(p->>'tipo',''), 'entrada'));
  v_dia   := coalesce(nullif(p->>'dia','')::date,
                      (now() at time zone 'America/Monterrey')::date);
  if v_folio is null then
    return jsonb_build_object('ok', false, 'motivo', 'FOLIO_INVALIDO');
  end if;

  select nombre into v_nom from candidatos where folio = v_folio;

  delete from asistencia
   where folio = v_folio and dia = v_dia and tipo = v_tipo;
  get diagnostics v_n = row_count;

  if v_n > 0 then
    perform public.anotar('pase_lista_deshecho', v_folio,
      jsonb_build_object('persona', v_nom, 'dia', v_dia, 'tipo', v_tipo));
  end if;

  return jsonb_build_object('ok', v_n > 0, 'folio', v_folio,
    'nombre', v_nom, 'tipo', v_tipo, 'dia', v_dia);
end; $fn$;

revoke all on function public.pase_lista(jsonb)      from public, anon;
revoke all on function public.pase_lista_dia(date)   from public, anon;
revoke all on function public.deshacer_pase(jsonb)   from public, anon;
grant execute on function public.pase_lista(jsonb)      to authenticated;
grant execute on function public.pase_lista_dia(date)   to authenticated;
grant execute on function public.deshacer_pase(jsonb)   to authenticated;
