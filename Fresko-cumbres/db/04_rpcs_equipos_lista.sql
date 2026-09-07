-- ============================================================
-- Fresko Cumbres · 04 · RPCs de equipos, datos, INE y puestos
-- ============================================================
-- Todo lo que usan /lista y /puestos. Cada operación que cambia
-- algo deja rastro en la bitácora (ver 03).
-- ============================================================

-- ---------- equipos ----------
create or replace function public.equipos_lista() returns jsonb
language plpgsql stable security definer set search_path to 'public' as $fn$
declare v jsonb;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', e.id, 'clave', e.clave, 'nombre', e.nombre, 'color', e.color,
           'punto', e.punto_clave, 'activo', e.activo,
           'integrantes', (select count(*) from candidatos c
                            where c.equipo_id = e.id and c.estatus <> 'baja')
         ) order by e.clave), '[]'::jsonb)
    into v from equipos e where e.activo;
  return v;
end; $fn$;

create or replace function public.renombrar_equipo(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $fn$
declare v_id smallint := (p->>'id')::smallint;
        v_nuevo text := btrim(coalesce(p->>'nombre',''));
        v_antes text;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;
  if length(v_nuevo) < 2 or length(v_nuevo) > 28 then
    return jsonb_build_object('ok', false, 'motivo','NOMBRE_INVALIDO');
  end if;
  select nombre into v_antes from equipos where id = v_id;
  if v_antes is null then return jsonb_build_object('ok', false, 'motivo','NO_EXISTE'); end if;
  update equipos set nombre = v_nuevo where id = v_id;
  perform public.anotar('equipo_renombrado', null,
    jsonb_build_object('equipo_id', v_id, 'antes', v_antes, 'ahora', v_nuevo));
  return jsonb_build_object('ok', true, 'id', v_id, 'nombre', v_nuevo);
end; $fn$;

create or replace function public.crear_equipo(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $fn$
declare v_clave text := upper(btrim(coalesce(p->>'clave','')));
        v_nombre text := btrim(coalesce(p->>'nombre',''));
        v_id smallint;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;
  if v_clave = '' then
    select chr(65 + count(*)) into v_clave from equipos;
  end if;
  if v_nombre = '' then v_nombre := 'Equipo ' || v_clave; end if;
  insert into equipos (clave, nombre) values (v_clave, v_nombre)
  on conflict (campana, clave) do update set activo = true
  returning id into v_id;
  perform public.anotar('equipo_creado', null,
    jsonb_build_object('equipo_id', v_id, 'clave', v_clave, 'nombre', v_nombre));
  return jsonb_build_object('ok', true, 'id', v_id, 'clave', v_clave, 'nombre', v_nombre);
end; $fn$;

create or replace function public.asignar_equipo(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $fn$
declare v_folio text := normalizar_folio(p->>'folio');
        v_nuevo smallint := nullif(p->>'equipo_id','')::smallint;
        v_antes smallint; v_nombre text;
        v_nom_antes text; v_nom_nuevo text;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;
  if v_folio is null then return jsonb_build_object('ok', false, 'motivo','FOLIO_INVALIDO'); end if;
  select equipo_id, nombre into v_antes, v_nombre from candidatos where folio = v_folio;
  if v_nombre is null then return jsonb_build_object('ok', false, 'motivo','NO_EXISTE'); end if;
  if v_nuevo is not null and not exists (select 1 from equipos where id = v_nuevo and activo) then
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

-- ---------- completar datos faltantes ----------
-- Sobrescribe el valor viejo cuando se manda uno nuevo (sirve también para
-- corregir un teléfono mal capturado). La bitácora guarda el "antes" completo.
create or replace function public.completar_datos(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $fn$
declare v_folio text := normalizar_folio(p->>'folio');
        v_antes jsonb; v_cambios jsonb := '{}'::jsonb; v_c record;
        v_edad int; v_tel text;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;
  if v_folio is null then return jsonb_build_object('ok', false, 'motivo','FOLIO_INVALIDO'); end if;
  select * into v_c from candidatos where folio = v_folio;
  if v_c.folio is null then return jsonb_build_object('ok', false, 'motivo','NO_EXISTE'); end if;

  v_antes := jsonb_build_object('edad', v_c.edad, 'telefono', v_c.telefono,
    'correo', v_c.correo, 'genero', v_c.genero, 'colonia', v_c.colonia,
    'talla_playera', v_c.talla_playera, 'tiene_ine', v_c.tiene_ine,
    'comentarios', v_c.comentarios, 'punto_asignado', v_c.punto_asignado);

  v_edad := nullif(btrim(coalesce(p->>'edad','')),'')::int;
  if v_edad is not null and (v_edad < 15 or v_edad > 80) then
    return jsonb_build_object('ok', false, 'motivo','EDAD_INVALIDA');
  end if;
  v_tel := nullif(regexp_replace(coalesce(p->>'telefono',''), '\D', '', 'g'), '');
  if v_tel is not null then v_tel := right(v_tel, 10); end if;
  if v_tel is not null and length(v_tel) <> 10 then
    return jsonb_build_object('ok', false, 'motivo','TELEFONO_INVALIDO');
  end if;

  update candidatos set
    edad          = coalesce(v_edad, edad),
    telefono      = coalesce(v_tel, telefono),
    correo        = coalesce(nullif(btrim(coalesce(p->>'correo','')),''), correo),
    genero        = coalesce(nullif(btrim(coalesce(p->>'genero','')),''), genero),
    colonia       = coalesce(nullif(btrim(coalesce(p->>'colonia','')),''), colonia),
    talla_playera = coalesce(nullif(btrim(coalesce(p->>'talla','')),''), talla_playera),
    tiene_ine     = coalesce((p->>'tiene_ine')::boolean, tiene_ine),
    punto_asignado= coalesce(nullif(btrim(coalesce(p->>'punto','')),''), punto_asignado),
    comentarios   = case when nullif(btrim(coalesce(p->>'comentarios','')),'') is null
                         then comentarios
                         else coalesce(comentarios || ' · ', '') || btrim(p->>'comentarios') end
  where folio = v_folio;

  select jsonb_strip_nulls(jsonb_build_object(
    'edad', case when c.edad is distinct from v_c.edad then c.edad end,
    'telefono', case when c.telefono is distinct from v_c.telefono then c.telefono end,
    'correo', case when c.correo is distinct from v_c.correo then c.correo end,
    'genero', case when c.genero is distinct from v_c.genero then c.genero end,
    'colonia', case when c.colonia is distinct from v_c.colonia then c.colonia end,
    'talla_playera', case when c.talla_playera is distinct from v_c.talla_playera then c.talla_playera end,
    'tiene_ine', case when c.tiene_ine is distinct from v_c.tiene_ine then c.tiene_ine end,
    'punto_asignado', case when c.punto_asignado is distinct from v_c.punto_asignado then c.punto_asignado end,
    'comentarios', case when c.comentarios is distinct from v_c.comentarios then c.comentarios end))
    into v_cambios from candidatos c where c.folio = v_folio;

  if v_cambios <> '{}'::jsonb then
    perform public.anotar('datos_completados', v_folio,
      jsonb_build_object('persona', v_c.nombre, 'antes', v_antes, 'cambios', v_cambios));
  end if;
  return jsonb_build_object('ok', true, 'folio', v_folio, 'nombre', v_c.nombre,
    'cambios', v_cambios);
end; $fn$;

-- ---------- foto de INE (solo de quien asistió a la capacitación) ----------
create or replace function public.registrar_ine(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $fn$
declare v_folio text := normalizar_folio(p->>'folio');
        v_path text := nullif(btrim(coalesce(p->>'path','')),'');
        v_asistio boolean; v_nombre text;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;
  if v_folio is null or v_path is null then
    return jsonb_build_object('ok', false, 'motivo','DATOS_INCOMPLETOS');
  end if;
  select asistio_capacitacion, nombre into v_asistio, v_nombre
    from candidatos where folio = v_folio;
  if v_nombre is null then return jsonb_build_object('ok', false, 'motivo','NO_EXISTE'); end if;
  if not v_asistio then return jsonb_build_object('ok', false, 'motivo','NO_ASISTIO'); end if;

  update candidatos set foto_ine_path = v_path, foto_ine_en = now(), tiene_ine = true
   where folio = v_folio;
  perform public.anotar('ine_capturada', v_folio,
    jsonb_build_object('persona', v_nombre, 'path', v_path));
  return jsonb_build_object('ok', true, 'folio', v_folio, 'nombre', v_nombre);
end; $fn$;

-- ---------- quién está en su puesto hoy / quién faltó ----------
create or replace function public.estado_puestos(p_dia date default null) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $fn$
declare v_dia date := coalesce(p_dia, (now() at time zone 'America/Monterrey')::date);
        v jsonb;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;

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
      from equipos e where e.activo), '[]'::jsonb),
    'sin_equipo', coalesce((
      select jsonb_agg(jsonb_build_object(
               'folio', g.folio, 'nombre', g.nombre, 'telefono', g.telefono,
               'entrada', g.entrada, 'presente', g.entrada is not null)
             order by g.nombre)
      from gente g where g.equipo_id is null), '[]'::jsonb)
  ) into v;
  return v;
end; $fn$;

-- ---------- suplir a alguien que faltó ----------
create or replace function public.suplir_puesto(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $fn$
declare v_dia date := coalesce(nullif(p->>'dia','')::date, (now() at time zone 'America/Monterrey')::date);
        v_aus text := normalizar_folio(p->>'folio_ausente');
        v_sup text := normalizar_folio(p->>'folio_suplente');
        v_eq smallint; v_nom_aus text; v_nom_sup text; v_punto text;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;
  if v_aus is null or v_sup is null then
    return jsonb_build_object('ok', false, 'motivo','FOLIO_INVALIDO');
  end if;
  if v_aus = v_sup then return jsonb_build_object('ok', false, 'motivo','MISMO_FOLIO'); end if;

  select nombre, equipo_id, punto_asignado into v_nom_aus, v_eq, v_punto
    from candidatos where folio = v_aus and estatus <> 'baja';
  select nombre into v_nom_sup from candidatos where folio = v_sup and estatus <> 'baja';
  if v_nom_aus is null or v_nom_sup is null then
    return jsonb_build_object('ok', false, 'motivo','NO_EXISTE');
  end if;
  if exists (select 1 from asistencia where folio = v_aus and dia = v_dia and tipo = 'entrada') then
    return jsonb_build_object('ok', false, 'motivo','YA_LLEGO', 'nombre', v_nom_aus);
  end if;

  insert into suplencias (dia, folio_ausente, folio_suplente, equipo_id, motivo, creado_por)
  values (v_dia, v_aus, v_sup, v_eq, nullif(btrim(coalesce(p->>'motivo','')),''), auth.uid())
  on conflict (campana, dia, folio_ausente) do update
    set folio_suplente = excluded.folio_suplente, equipo_id = excluded.equipo_id,
        motivo = excluded.motivo, creado_por = excluded.creado_por, creado_en = now();

  update candidatos set equipo_id = coalesce(v_eq, equipo_id),
                        punto_asignado = coalesce(v_punto, punto_asignado)
   where folio = v_sup;

  perform public.anotar('suplencia', v_aus, jsonb_build_object(
    'dia', v_dia, 'ausente', v_nom_aus, 'suplente_folio', v_sup,
    'suplente', v_nom_sup, 'equipo_id', v_eq, 'motivo', p->>'motivo'));
  return jsonb_build_object('ok', true, 'ausente', v_nom_aus, 'suplente', v_nom_sup,
    'folio_suplente', v_sup, 'equipo_id', v_eq);
end; $fn$;

-- ---------- búsqueda y ficha (ahora con equipo y qué datos faltan) ----------
create or replace function public.buscar_candidato(p_texto text) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $fn$
declare
  v_txt text := btrim(coalesce(p_texto, ''));
  v_dig text := regexp_replace(v_txt, '\D', '', 'g');
  v_folio text := normalizar_folio(v_txt);
  v_res jsonb;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;
  if length(v_txt) < 2 then return '[]'::jsonb; end if;

  select coalesce(jsonb_agg(t order by rango, nombre), '[]'::jsonb) into v_res
  from (
    select
      case
        when c.folio = v_folio                        then 1
        when v_dig <> '' and c.telefono = v_dig       then 2
        when c.nombre ilike v_txt || '%'              then 3
        when c.nombre ilike '% ' || v_txt || '%'      then 4
        when v_dig <> '' and c.telefono like '%'||v_dig||'%' then 5
        else 6
      end as rango,
      c.nombre,
      jsonb_build_object(
        'folio', c.folio, 'nombre', c.nombre, 'telefono', c.telefono,
        'talla', c.talla_playera, 'tiene_ine', c.tiene_ine, 'edad', c.edad,
        'colonia', c.colonia, 'genero', c.genero, 'correo', c.correo,
        'estatus', c.estatus, 'asistio', c.asistio_capacitacion,
        'invitado_por', c.referido_por_folio,
        'equipo_id', c.equipo_id, 'equipo', e.nombre, 'equipo_color', e.color,
        'punto', c.punto_asignado, 'tiene_foto_ine', c.foto_ine_path is not null,
        'faltan', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
                     select 'edad' as x where c.edad is null
                     union all select 'talla' where c.talla_playera is null
                     union all select 'colonia' where c.colonia is null
                     union all select 'equipo' where c.equipo_id is null
                     union all select 'foto_ine' where c.foto_ine_path is null
                                                   and c.asistio_capacitacion
                   ) f)
      ) as t
    from candidatos c
    left join equipos e on e.id = c.equipo_id
    where c.estatus <> 'baja'
      and (
        c.folio = v_folio
        or c.nombre ilike '%' || v_txt || '%'
        or (v_dig <> '' and c.telefono like '%' || v_dig || '%')
      )
    order by 1, 2
    limit 15
  ) s;
  return v_res;
end; $fn$;

create or replace function public.ficha_folio(p_folio text) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $fn$
declare v jsonb; v_f text := normalizar_folio(p_folio);
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;
  select jsonb_build_object(
    'folio', c.folio, 'nombre', c.nombre, 'telefono', c.telefono,
    'talla', c.talla_playera, 'tiene_ine', c.tiene_ine, 'edad', c.edad,
    'colonia', c.colonia, 'genero', c.genero, 'correo', c.correo,
    'estatus', c.estatus, 'asistio', c.asistio_capacitacion,
    'invitado_por', c.referido_por_folio,
    'equipo_id', c.equipo_id, 'equipo', e.nombre, 'equipo_color', e.color,
    'punto', c.punto_asignado, 'tiene_foto_ine', c.foto_ine_path is not null,
    'faltan', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
                 select 'edad' as x where c.edad is null
                 union all select 'talla' where c.talla_playera is null
                 union all select 'colonia' where c.colonia is null
                 union all select 'equipo' where c.equipo_id is null
                 union all select 'foto_ine' where c.foto_ine_path is null
                                               and c.asistio_capacitacion
               ) f))
    into v
  from candidatos c left join equipos e on e.id = c.equipo_id
  where c.folio = v_f;
  return coalesce(v, jsonb_build_object('no_existe', true, 'folio', v_f));
end; $fn$;

-- ---------- pasar lista y alta en sitio (ahora con equipo y bitácora) ----------
create or replace function public.marcar_asistencia(p_folio text, p_asistio boolean default true)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_folio text; v_antes boolean; v_c record; v_eq text; v_faltan jsonb;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;

  v_folio := normalizar_folio(p_folio);
  if v_folio is null then
    return jsonb_build_object('ok', false, 'motivo', 'FOLIO_INVALIDO');
  end if;

  select asistio_capacitacion into v_antes from candidatos where folio = v_folio;
  if v_antes is null then
    return jsonb_build_object('ok', false, 'motivo', 'NO_EXISTE', 'folio', v_folio);
  end if;

  update candidatos
     set asistio_capacitacion = coalesce(p_asistio, true),
         hora_registro_cita   = case when coalesce(p_asistio,true) then now() else null end
   where folio = v_folio;

  select * into v_c from candidatos where folio = v_folio;
  select nombre into v_eq from equipos where id = v_c.equipo_id;

  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_faltan from (
    select 'edad' as x where v_c.edad is null
    union all select 'talla'    where v_c.talla_playera is null
    union all select 'colonia'  where v_c.colonia is null
    union all select 'equipo'   where v_c.equipo_id is null
    union all select 'foto_ine' where v_c.foto_ine_path is null and coalesce(p_asistio,true)
  ) f;

  if v_antes is distinct from coalesce(p_asistio, true) then
    perform public.anotar(
      case when coalesce(p_asistio,true) then 'asistencia_marcada' else 'asistencia_deshecha' end,
      v_folio, jsonb_build_object('persona', v_c.nombre, 'antes', v_antes));
  end if;

  return jsonb_build_object(
    'ok', true, 'folio', v_folio, 'nombre', v_c.nombre,
    'talla', v_c.talla_playera, 'tiene_ine', v_c.tiene_ine, 'estatus', v_c.estatus,
    'edad', v_c.edad, 'colonia', v_c.colonia, 'telefono', v_c.telefono,
    'equipo_id', v_c.equipo_id, 'equipo', v_eq,
    'invitado_por', v_c.referido_por_folio,
    'tiene_foto_ine', v_c.foto_ine_path is not null,
    'faltan', v_faltan,
    'asistio', coalesce(p_asistio, true));
end; $fn$;

create or replace function public.alta_en_sitio(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $fn$
declare v_res jsonb; v_eq smallint := nullif(p->>'equipo_id','')::smallint;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;
  v_res := registrar_candidato(
    p || jsonb_build_object('acepta_aviso', true,
                            'como_se_entero', coalesce(p->>'como_se_entero','me invitaron'),
                            'canal', coalesce(p->>'canal', 'presencial')));
  if coalesce((v_res->>'ok')::boolean, false) and v_eq is not null then
    update candidatos set equipo_id = v_eq where folio = v_res->>'folio';
  end if;
  if coalesce((v_res->>'ok')::boolean, false) then
    perform public.anotar('alta_en_sitio', v_res->>'folio', jsonb_build_object(
      'persona', p->>'nombre', 'telefono', p->>'telefono', 'equipo_id', v_eq,
      'invitado_por', p->>'referido_por_folio'));
  end if;
  return v_res;
end; $fn$;

-- ---------- bucket privado para las fotos de INE ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ine', 'ine', false, 6291456, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false,
  file_size_limit = 6291456,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists ine_sube on storage.objects;
create policy ine_sube on storage.objects for insert to authenticated
  with check (bucket_id = 'ine' and public.puede_lista());

drop policy if exists ine_lee on storage.objects;
create policy ine_lee on storage.objects for select to authenticated
  using (bucket_id = 'ine' and public.puede_lista());

drop policy if exists ine_actualiza on storage.objects;
create policy ine_actualiza on storage.objects for update to authenticated
  using (bucket_id = 'ine' and public.puede_lista())
  with check (bucket_id = 'ine' and public.puede_lista());
