-- ============================================================
-- Fresko Cumbres · 06 · Confirmación de la cita por enlace
-- ============================================================
-- Cada persona recibe https://fresko-cumbres.abdev.click/confirmo?f=SU_FOLIO
-- Al abrirlo queda confirmada. Sin sesión, sin escribir nada.
-- ============================================================

alter table candidatos add column if not exists confirmo_en timestamptz;

update candidatos set confirmo_en = coalesce(confirmo_en, created_at)
 where estatus = 'confirmado' and confirmo_en is null;

create or replace function public.confirmar_cita(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $fn$
declare v_f text := normalizar_folio(p->>'folio');
        v_c record; v_ya boolean;
        v_prueba text[] := array['030','031'];
begin
  if v_f is null then return jsonb_build_object('ok', false, 'motivo','FOLIO_INVALIDO'); end if;
  select * into v_c from candidatos where folio = v_f;
  if v_c.folio is null then return jsonb_build_object('ok', false, 'motivo','NO_EXISTE'); end if;
  if v_c.estatus = 'baja' then return jsonb_build_object('ok', false, 'motivo','DADO_DE_BAJA'); end if;

  v_ya := v_c.confirmo_en is not null;
  if not v_ya then
    update candidatos
       set estatus = case when estatus = 'registrado' then 'confirmado' else estatus end,
           confirmo_en = now()
     where folio = v_f;
    perform public.anotar('cita_confirmada', v_f,
      jsonb_build_object('persona', v_c.nombre, 'origen', coalesce(p->>'origen','enlace')));
  end if;

  return jsonb_build_object(
    'ok', true, 'ya_estaba', v_ya,
    'folio', v_f,
    'nombre', split_part(v_c.nombre, ' ', 1),
    'nombre_completo', v_c.nombre,
    'talla', v_c.talla_playera,
    'confirmados', (select count(*) from candidatos
                     where confirmo_en is not null and estatus <> 'baja'
                       and not (folio = any(v_prueba))),
    'registrados', (select count(*) from candidatos
                     where estatus <> 'baja' and not (folio = any(v_prueba))));
end; $fn$;

grant execute on function public.confirmar_cita(jsonb) to anon, authenticated;

create or replace view v_confirmacion as
  select folio, nombre, telefono, talla_playera, estatus,
         confirmo_en is not null as confirmo,
         confirmo_en at time zone 'America/Monterrey' as confirmo_hora,
         referido_por_folio
    from candidatos
   where estatus <> 'baja';

alter view v_confirmacion set (security_invoker = on);
