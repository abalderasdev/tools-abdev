-- Los equipos existen por campaña (misma clave "A" se reusa en cada
-- etapa, ver unique(campana, clave)), pero equipos_lista() y
-- estado_puestos() listaban TODOS los equipos activos de TODAS las
-- campañas, así que al terminar SEP26 y abrir ETAPA2 se veían los
-- 4 equipos viejos junto a los 4 nuevos, con el mismo nombre --
-- parecían duplicados. Ahora ambas funciones filtran por la campaña
-- con registro_abierto = true.
--
-- De paso: crear_equipo() no ponía la campaña al insertar, así que
-- se iba con el default de la columna (la campaña vieja, SEP26) --
-- cualquier equipo nuevo se habría creado pegado a la etapa
-- equivocada. Y asignar_equipo() no validaba que el equipo fuera de
-- la campaña activa. Ambas quedan corregidas.

create or replace function public.equipos_lista() returns jsonb
language plpgsql stable security definer set search_path to 'public' as $fn$
declare v jsonb; v_campana text;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;
  select campana into v_campana from parametros where registro_abierto
   order by fecha_inicio desc limit 1;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', e.id, 'clave', e.clave, 'nombre', e.nombre, 'color', e.color,
           'punto', e.punto_clave, 'activo', e.activo,
           'integrantes', (select count(*) from candidatos c
                            where c.equipo_id = e.id and c.estatus <> 'baja')
         ) order by e.clave), '[]'::jsonb)
    into v from equipos e where e.activo and e.campana = v_campana;
  return v;
end; $fn$;

create or replace function public.crear_equipo(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $fn$
declare v_clave text := upper(btrim(coalesce(p->>'clave','')));
        v_nombre text := btrim(coalesce(p->>'nombre',''));
        v_id smallint; v_campana text;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;
  select campana into v_campana from parametros where registro_abierto
   order by fecha_inicio desc limit 1;
  if v_campana is null then
    return jsonb_build_object('ok', false, 'motivo', 'SIN_CAMPANA_ABIERTA');
  end if;
  if v_clave = '' then
    select chr(65 + count(*)) into v_clave from equipos where campana = v_campana;
  end if;
  if v_nombre = '' then v_nombre := 'Equipo ' || v_clave; end if;
  insert into equipos (campana, clave, nombre) values (v_campana, v_clave, v_nombre)
  on conflict (campana, clave) do update set activo = true
  returning id into v_id;
  perform public.anotar('equipo_creado', null,
    jsonb_build_object('equipo_id', v_id, 'campana', v_campana, 'clave', v_clave, 'nombre', v_nombre));
  return jsonb_build_object('ok', true, 'id', v_id, 'clave', v_clave, 'nombre', v_nombre);
end; $fn$;

create or replace function public.asignar_equipo(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $fn$
declare v_folio text := normalizar_folio(p->>'folio');
        v_nuevo smallint := nullif(p->>'equipo_id','')::smallint;
        v_antes smallint; v_nombre text;
        v_nom_antes text; v_nom_nuevo text; v_campana text;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;
  if v_folio is null then return jsonb_build_object('ok', false, 'motivo','FOLIO_INVALIDO'); end if;
  select equipo_id, nombre into v_antes, v_nombre from candidatos where folio = v_folio;
  if v_nombre is null then return jsonb_build_object('ok', false, 'motivo','NO_EXISTE'); end if;

  select campana into v_campana from parametros where registro_abierto
   order by fecha_inicio desc limit 1;
  if v_nuevo is not null and not exists (
    select 1 from equipos where id = v_nuevo and activo and campana = v_campana
  ) then
    return jsonb_build_object('ok', false, 'motivo','EQUIPO_NO_EXISTE');
  end if;

  update candidatos set equipo_id = v_nuevo where folio = v_folio;
  select nombre into v_nom_antes from equipos where id = v_antes;
  select nombre into v_nom_nuevo from equipos where id = v_nuevo;
  perform public.anotar('equipo_asignado', v_folio, jsonb_build_object(
    'persona', v_nombre, 'de_id', v_antes, 'de', v_nom_antes,
    'a_id', v_nuevo, 'a', v_nom_nuevo));
  return jsonb_build_object('ok', true, 'folio', v_folio, 'nombre', v_nombre,
    'equipo_id', v_nuevo, 'equipo', v_nom_nuevo, 'antes', v_nom_antes);
end; $fn$;

create or replace function public.estado_puestos(p_dia date default null) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $fn$
declare v_dia date := coalesce(p_dia, (now() at time zone 'America/Monterrey')::date);
        v_campana text; v jsonb;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;
  select campana into v_campana from parametros where registro_abierto
   order by fecha_inicio desc limit 1;

  with gente as (
    select c.folio, c.nombre, c.telefono, c.equipo_id, c.punto_asignado,
           a_ent.momento as entrada, a_sal.momento as salida,
           s.folio_suplente, cs.nombre as suplente_nombre,
           s2.folio_ausente, ca.nombre as ausente_nombre
      from candidatos c
      left join asistencia a_ent
        on a_ent.folio = c.folio and a_ent.dia = v_dia and a_ent.tipo = 'entrada'
      left join asistencia a_sal
        on a_sal.folio = c.folio and a_sal.dia = v_dia and a_sal.tipo = 'salida'
      left join suplencias s  on s.dia = v_dia and s.folio_ausente  = c.folio
      left join candidatos  cs on cs.folio = s.folio_suplente
      left join suplencias s2 on s2.dia = v_dia and s2.folio_suplente = c.folio
      left join candidatos  ca on ca.folio = s2.folio_ausente
     where c.estatus <> 'baja' and c.asistio_capacitacion
  )
  select jsonb_build_object(
    'dia', v_dia,
    'totales', jsonb_build_object(
      'plantilla', (select count(*) from gente),
      'presentes', (select count(*) from gente where entrada is not null),
      'faltantes', (select count(*) from gente where entrada is null),
      'cubiertos', (select count(*) from gente where entrada is null and folio_suplente is not null)),
    'equipos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'clave', e.clave, 'nombre', e.nombre, 'color', e.color,
        'presentes', (select count(*) from gente g where g.equipo_id = e.id and g.entrada is not null),
        'faltantes', (select count(*) from gente g where g.equipo_id = e.id and g.entrada is null),
        'integrantes', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'folio', g.folio, 'nombre', g.nombre, 'telefono', g.telefono,
                   'entrada', g.entrada, 'salida', g.salida, 'punto', g.punto_asignado,
                   'presente', g.entrada is not null,
                   'suplido_por', g.folio_suplente, 'suplente', g.suplente_nombre,
                   'cubre_a', g.folio_ausente, 'cubre_a_nombre', g.ausente_nombre)
                 order by (g.entrada is not null) desc, g.nombre)
          from gente g where g.equipo_id = e.id), '[]'::jsonb)
      ) order by e.clave)
      from equipos e where e.activo and e.campana = v_campana), '[]'::jsonb),
    'sin_equipo', coalesce((
      select jsonb_agg(jsonb_build_object(
               'folio', g.folio, 'nombre', g.nombre, 'telefono', g.telefono,
               'entrada', g.entrada, 'presente', g.entrada is not null)
             order by g.nombre)
      from gente g where g.equipo_id is null), '[]'::jsonb)
  ) into v;
  return v;
end; $fn$;
