-- ============================================================
-- 09 · Expediente del trabajador (pestaña "Expediente" del dashboard)
--
-- Todo lo de una sola persona en una llamada: sus datos, su INE,
-- los días que trabajó con hora de entrada y salida, lo que se le
-- debe y a quién trajo.
--
-- Solo administrador: aquí sale dinero, notas internas y la ruta
-- de la foto de la credencial. El nivel `equipo` no lo ve.
-- ============================================================

create or replace function public.expediente(p_folio text) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $fn$
declare v_f text := normalizar_folio(p_folio); v_c record; v jsonb;
begin
  if not public.es_admin() then raise exception 'SIN_PERMISO'; end if;
  if v_f is null then return jsonb_build_object('no_existe', true); end if;

  select * into v_c from candidatos where folio = v_f;
  if v_c is null then
    return jsonb_build_object('no_existe', true, 'folio', v_f);
  end if;

  select jsonb_build_object(
    'folio', v_c.folio,
    'persona', jsonb_build_object(
      'nombre', v_c.nombre, 'telefono', v_c.telefono, 'correo', v_c.correo,
      'edad', v_c.edad, 'genero', v_c.genero,
      'colonia', v_c.colonia, 'municipio', v_c.municipio,
      'talla', v_c.talla_playera, 'experiencia', v_c.experiencia,
      'disponible_completa', v_c.disponible_completa,
      'transporte', v_c.transporte, 'comentarios', v_c.comentarios,
      'canal', v_c.canal, 'como_se_entero', v_c.como_se_entero,
      'estatus', v_c.estatus, 'calificacion', v_c.calificacion,
      'notas', v_c.notas_internas,
      'futuras', v_c.futuras_activaciones, 'acepta_aviso', v_c.acepta_aviso,
      'alta_en', v_c.created_at,
      'punto', v_c.punto_asignado,
      'equipo_id', v_c.equipo_id,
      'equipo', (select nombre from equipos where id = v_c.equipo_id),
      'equipo_color', (select color from equipos where id = v_c.equipo_id)),

    'cita', jsonb_build_object(
      'confirmo_en', v_c.confirmo_en,
      'asistio_capacitacion', coalesce(v_c.asistio_capacitacion, false),
      'hora_registro', v_c.hora_registro_cita),

    'ine', jsonb_build_object(
      'declara_tener', v_c.tiene_ine,
      'tiene_foto', v_c.foto_ine_path is not null,
      'path', v_c.foto_ine_path,
      'capturada_en', v_c.foto_ine_en),

    -- Un renglón por día trabajado, con entrada, salida y horas.
    'turnos', (
      select coalesce(jsonb_agg(x order by x->>'dia' desc), '[]'::jsonb) from (
        select jsonb_build_object(
                 'dia', t.dia,
                 'entrada', to_char(t.ent at time zone 'America/Monterrey', 'HH12:MI am'),
                 'salida',  to_char(t.sal at time zone 'America/Monterrey', 'HH12:MI am'),
                 'horas', case when t.sal is not null
                               then round(extract(epoch from (t.sal - t.ent))/3600.0, 1) end,
                 'origen', t.origen) as x
        from (
          select a.dia,
                 min(a.momento) filter (where a.tipo = 'entrada') as ent,
                 max(a.momento) filter (where a.tipo = 'salida')  as sal,
                 min(a.origen)  filter (where a.tipo = 'entrada') as origen
          from asistencia a
          where a.folio = v_f and a.tipo in ('entrada','salida')
          group by a.dia
          having count(*) filter (where a.tipo = 'entrada') > 0
        ) t
      ) s),

    -- El dinero sale de la misma vista que usa "Estado de cuenta",
    -- para que nunca se contradigan las dos pantallas.
    'cuenta', (
      select to_jsonb(ec) - 'folio' - 'nombre' - 'telefono' - 'estatus'
      from v_estado_cuenta ec where ec.folio = v_f),

    'bonos', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'tipo', b.tipo, 'monto', b.monto, 'concepto', b.concepto,
               'estatus', b.estatus, 'fecha_pago', b.fecha_pago,
               'relacionado', b.folio_relacionado) order by b.created_at), '[]'::jsonb)
      from bonos b where b.folio = v_f),

    'lo_invito', (
      select jsonb_build_object('folio', q.folio, 'nombre', q.nombre)
      from candidatos q where q.folio = v_c.referido_por_folio),

    'invitados', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'folio', r.folio, 'nombre', r.nombre,
               'llego', coalesce(r.asistio_capacitacion, false)) order by r.folio), '[]'::jsonb)
      from candidatos r where r.referido_por_folio = v_f and r.estatus <> 'baja')
  ) into v;

  return v;
end; $fn$;

revoke all on function public.expediente(text) from public, anon;
grant execute on function public.expediente(text) to authenticated;
