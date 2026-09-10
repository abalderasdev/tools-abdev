-- ============================================================
-- 10 · Pagos de jornada
--
-- La regla del negocio, en palabras de Alberto: "en el momento de
-- pasar lista en la mañana les pago". Es decir, el día trabajado se
-- paga a la mañana SIGUIENTE, cuando la persona vuelve a llegar.
--
-- Por eso `pase_lista` contesta las tres preguntas que él hace de
-- frente a cada quien: ¿vino ayer?, ¿cuánto le debo?, ¿ya le pagué?
--
-- Los $200 de la capacitación NO entran aquí a propósito: se pagaron
-- en efectivo el mismo martes y no quedaron registrados. Meterlos
-- haría que la pantalla pidiera pagarlos otra vez.
-- ============================================================

create table if not exists public.pagos (
  id         bigserial primary key,
  folio      text not null references public.candidatos(folio) on delete cascade,
  dia        date not null,                 -- el día trabajado que se está pagando
  concepto   text not null default 'jornada'
               check (concepto in ('jornada','capacitacion','puntualidad','referido','otro')),
  monto      numeric(10,2) not null,
  nota       text,
  pagado_en  timestamptz not null default now(),
  pagado_por uuid,
  unique (folio, dia, concepto)
);

create index if not exists idx_pagos_folio on public.pagos (folio);
create index if not exists idx_pagos_dia   on public.pagos (dia);

alter table public.pagos enable row level security;

-- Quien pasa lista necesita verlos: paga en la mañana al mismo tiempo
-- que pasa lista. La escritura va solo por los RPCs de abajo.
drop policy if exists pagos_lee on public.pagos;
create policy pagos_lee on public.pagos for select to authenticated
  using (public.puede_lista());

-- ------------------------------------------------------------
-- Registrar el pago. Sin `dias` paga todo lo pendiente hasta ayer.
-- ------------------------------------------------------------
create or replace function public.marcar_pagado(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_folio text; v_hoy date; v_tarifa numeric; v_uid uuid := auth.uid();
  v_dias date[]; v_n int := 0; v_total numeric := 0; v_nom text; v_d date;
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

  v_hoy := coalesce(nullif(p->>'hoy','')::date,
                    (now() at time zone 'America/Monterrey')::date);
  select pago_por_dia into v_tarifa from parametros limit 1;
  v_tarifa := coalesce(v_tarifa, 400);

  if p ? 'dias' and jsonb_typeof(p->'dias') = 'array' then
    select array_agg(x::date) into v_dias
      from jsonb_array_elements_text(p->'dias') x;
  else
    -- Todo lo trabajado ANTES de hoy que no tenga ya un renglón de pago.
    select array_agg(a.dia) into v_dias
      from (select distinct dia from asistencia
             where folio = v_folio and tipo = 'entrada' and dia < v_hoy) a
     where not exists (select 1 from pagos g
                        where g.folio = v_folio and g.dia = a.dia and g.concepto = 'jornada');
  end if;

  if v_dias is null or array_length(v_dias, 1) is null then
    return jsonb_build_object('ok', false, 'motivo', 'NADA_QUE_PAGAR',
      'folio', v_folio, 'nombre', v_nom);
  end if;

  foreach v_d in array v_dias loop
    insert into pagos (folio, dia, concepto, monto, pagado_por)
    values (v_folio, v_d, 'jornada', v_tarifa, v_uid)
    on conflict (folio, dia, concepto) do nothing;
    if found then
      v_n := v_n + 1; v_total := v_total + v_tarifa;
    end if;
  end loop;

  if v_n > 0 then
    perform public.anotar('pago_jornada', v_folio,
      jsonb_build_object('persona', v_nom, 'dias', to_jsonb(v_dias), 'total', v_total));
  end if;

  return jsonb_build_object('ok', true, 'folio', v_folio, 'nombre', v_nom,
    'dias_pagados', v_n, 'total', v_total);
end; $fn$;

-- ------------------------------------------------------------
-- Deshacer. Sin `dia` quita los pagos de las últimas 12 horas,
-- que es el caso real: "le di clic sin querer".
-- ------------------------------------------------------------
create or replace function public.deshacer_pago(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $fn$
declare v_folio text; v_dia date; v_n int; v_nom text;
begin
  if not public.puede_lista() then raise exception 'SIN_PERMISO'; end if;
  v_folio := normalizar_folio(p->>'folio');
  if v_folio is null then
    return jsonb_build_object('ok', false, 'motivo', 'FOLIO_INVALIDO');
  end if;
  select nombre into v_nom from candidatos where folio = v_folio;
  v_dia := nullif(p->>'dia','')::date;

  if v_dia is null then
    delete from pagos where folio = v_folio and concepto = 'jornada'
       and pagado_en > now() - interval '12 hours';
  else
    delete from pagos where folio = v_folio and dia = v_dia and concepto = 'jornada';
  end if;
  get diagnostics v_n = row_count;

  if v_n > 0 then
    perform public.anotar('pago_deshecho', v_folio,
      jsonb_build_object('persona', v_nom, 'dia', v_dia, 'renglones', v_n));
  end if;

  return jsonb_build_object('ok', v_n > 0, 'folio', v_folio, 'nombre', v_nom, 'quitados', v_n);
end; $fn$;

revoke all on function public.marcar_pagado(jsonb) from public, anon;
revoke all on function public.deshacer_pago(jsonb) from public, anon;
grant execute on function public.marcar_pagado(jsonb) to authenticated;
grant execute on function public.deshacer_pago(jsonb) to authenticated;

-- NOTA: `pase_lista`, `pase_lista_dia` y `expediente` se actualizaron
-- para devolver `ayer`, `por_pagar` / `total_por_pagar` y `pagado`.
-- Sus definiciones vigentes están en 08_pase_de_lista.sql y
-- 09_expediente.sql, aplicadas por migración.
