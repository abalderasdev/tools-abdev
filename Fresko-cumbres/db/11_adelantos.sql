-- ============================================================
-- 11 · Adelantos de dinero
--
-- Alguien pide dinero antes de que su jornada sea pagable ("me
-- adelantas $200 para el pasaje"). Se le entrega y queda como saldo
-- en contra: cuando se le pague la jornada, se le descuenta.
--
-- Tabla aparte de `pagos` a propósito: un adelanto puede ocurrir
-- varias veces y no está amarrado a un día trabajado, así que no
-- cabe en la llave (folio, día, concepto) de `pagos`.
-- ============================================================

create table if not exists public.adelantos (
  id            bigserial primary key,
  folio         text not null references public.candidatos(folio) on delete cascade,
  monto         numeric(10,2) not null check (monto > 0),
  motivo        text,
  entregado_en  timestamptz not null default now(),
  entregado_por uuid,
  saldado_en    timestamptz            -- null = todavía se le descuenta
);

create index if not exists idx_adelantos_folio   on public.adelantos (folio);
create index if not exists idx_adelantos_abierto on public.adelantos (folio) where saldado_en is null;

alter table public.adelantos enable row level security;

drop policy if exists adelantos_lee on public.adelantos;
create policy adelantos_lee on public.adelantos for select to authenticated
  using (public.puede_lista());

-- ------------------------------------------------------------
-- Dos cuentas que se repiten en varios lugares; mejor en un solo sitio.
-- ------------------------------------------------------------
create or replace function public.adelanto_abierto(p_folio text) returns numeric
language sql stable security definer set search_path to 'public' as $$
  select coalesce(sum(monto), 0)
  from adelantos where folio = p_folio and saldado_en is null;
$$;

create or replace function public.jornadas_sin_pagar(p_folio text, p_dia date, p_tarifa numeric)
returns numeric
language sql stable security definer set search_path to 'public' as $$
  select coalesce(count(*), 0) * coalesce(p_tarifa, 400)
  from (select distinct dia from asistencia
         where folio = p_folio and tipo = 'entrada' and dia < p_dia) d
  where not exists (select 1 from pagos g
                     where g.folio = p_folio and g.dia = d.dia and g.concepto = 'jornada');
$$;

-- ------------------------------------------------------------
-- Entregar un adelanto.
-- ------------------------------------------------------------
create or replace function public.dar_adelanto(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $fn$
declare v_folio text; v_monto numeric; v_nom text; v_id bigint; v_abierto numeric;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;

  v_folio := normalizar_folio(p->>'folio');
  if v_folio is null then
    return jsonb_build_object('ok', false, 'motivo', 'FOLIO_INVALIDO');
  end if;
  select nombre into v_nom from candidatos where folio = v_folio;
  if v_nom is null then
    return jsonb_build_object('ok', false, 'motivo', 'NO_EXISTE', 'folio', v_folio);
  end if;

  v_monto := round(nullif(p->>'monto','')::numeric, 2);
  if v_monto is null or v_monto <= 0 then
    return jsonb_build_object('ok', false, 'motivo', 'MONTO_INVALIDO');
  end if;

  insert into adelantos (folio, monto, motivo, entregado_por)
  values (v_folio, v_monto, nullif(btrim(coalesce(p->>'motivo','')),''), auth.uid())
  returning id into v_id;

  perform public.anotar('adelanto', v_folio,
    jsonb_build_object('persona', v_nom, 'monto', v_monto, 'motivo', p->>'motivo'));

  select coalesce(sum(monto), 0) into v_abierto
    from adelantos where folio = v_folio and saldado_en is null;

  return jsonb_build_object('ok', true, 'id', v_id, 'folio', v_folio,
    'nombre', v_nom, 'monto', v_monto, 'adelantado', v_abierto);
end; $fn$;

-- ------------------------------------------------------------
-- Quitar un adelanto mal capturado. Sin `id`, quita el último abierto.
-- Uno ya saldado no se toca: ese dinero ya se descontó de una jornada.
-- ------------------------------------------------------------
create or replace function public.deshacer_adelanto(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $fn$
declare v_folio text; v_id bigint; v_n int; v_nom text;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;
  v_folio := normalizar_folio(p->>'folio');
  v_id    := nullif(p->>'id','')::bigint;
  select nombre into v_nom from candidatos where folio = v_folio;

  if v_id is not null then
    delete from adelantos where id = v_id and saldado_en is null;
  else
    delete from adelantos where id = (
      select id from adelantos
       where folio = v_folio and saldado_en is null
       order by entregado_en desc limit 1);
  end if;
  get diagnostics v_n = row_count;

  if v_n > 0 then
    perform public.anotar('adelanto_deshecho', v_folio,
      jsonb_build_object('persona', v_nom, 'id', v_id));
  end if;

  return jsonb_build_object('ok', v_n > 0, 'folio', v_folio, 'nombre', v_nom, 'quitados', v_n);
end; $fn$;

revoke all on function public.adelanto_abierto(text)                from public, anon;
revoke all on function public.jornadas_sin_pagar(text,date,numeric) from public, anon;
revoke all on function public.dar_adelanto(jsonb)                   from public, anon;
revoke all on function public.deshacer_adelanto(jsonb)              from public, anon;
grant execute on function public.adelanto_abierto(text)                to authenticated;
grant execute on function public.jornadas_sin_pagar(text,date,numeric) to authenticated;
grant execute on function public.dar_adelanto(jsonb)                   to authenticated;
grant execute on function public.deshacer_adelanto(jsonb)              to authenticated;

-- NOTA: `pase_lista` y `pase_lista_dia` devuelven ahora `adelantado` y
-- `neto`, y `marcar_pagado` salda los adelantos abiertos contra la
-- jornada que se paga (del más viejo al más nuevo, partiendo el
-- renglón si solo alcanza para una parte). Ver 10_pagos.sql.
