-- =====================================================================
--  ESQUEMA COMPLETO · Base de personal para activaciones
--  Proyecto Supabase: activaciones-personal (eykfdnoczpwjccunzfgh)
--
--  ⚠️  Este archivo YA ESTÁ APLICADO en el proyecto. Se guarda aquí como
--      respaldo y para poder recrear la base desde cero si hiciera falta.
-- =====================================================================

-- ── Parámetros de la campaña ─────────────────────────────────────────
create table public.parametros (
  campana            text primary key,
  nombre_evento      text not null,
  pago_por_dia       numeric(10,2) not null default 400,
  bono_capacitacion  numeric(10,2) not null default 0,
  bono_referido      numeric(10,2) not null default 50,
  bono_puntualidad   numeric(10,2) not null default 0,
  meta_folios        int not null default 70,
  folio_inicial      int not null default 10,
  fecha_capacitacion timestamptz,
  lugar_capacitacion text,
  registro_abierto   boolean not null default true
);

insert into public.parametros (
  campana, nombre_evento, pago_por_dia, bono_referido,
  meta_folios, folio_inicial, fecha_capacitacion, lugar_capacitacion
) values (
  'FRESKO-CUMBRES-SEP26',
  'Activación en calle · Cumbres, Monterrey',
  400, 50, 70, 10,
  '2026-09-08 16:00:00-06',
  'Fresko Cumbres, Monterrey, N.L.'
);

-- Folios de 3 dígitos. Arranca en 30: los 010–029 se entregaron a mano.
create sequence public.folio_seq start 30;

-- ── Candidatos ───────────────────────────────────────────────────────
create table public.candidatos (
  id                   uuid primary key default gen_random_uuid(),
  folio                text unique not null
                         default to_char(nextval('public.folio_seq'), 'FM000'),
  campana              text not null default 'FRESKO-CUMBRES-SEP26'
                         references public.parametros(campana),
  nombre               text not null,
  telefono             text not null,
  correo               text,
  edad                 int,
  genero               text,
  colonia              text,
  municipio            text default 'Monterrey',
  talla_playera        text,
  experiencia          text,
  disponible_completa  boolean default false,
  tiene_ine            boolean default false,
  transporte           text,
  comentarios          text,
  referido_por_folio   text references public.candidatos(folio) on delete set null,
  referido_por_nombre  text,
  como_se_entero       text,
  asistio_capacitacion boolean not null default false,
  hora_registro_cita   timestamptz,
  estatus              text not null default 'registrado',
  futuras_activaciones boolean not null default true,
  acepta_aviso         boolean not null default false,
  calificacion         int check (calificacion between 1 and 5),
  notas_internas       text,
  created_at           timestamptz not null default now(),
  constraint estatus_valido check (estatus in
    ('registrado','lista_espera','confirmado','asistio_cita','contratado','no_asistio','baja'))
);

create index idx_cand_campana   on public.candidatos (campana);
create index idx_cand_estatus   on public.candidatos (estatus);
create index idx_cand_telefono  on public.candidatos (telefono);
create index idx_cand_referidor on public.candidatos (referido_por_folio);
create unique index idx_cand_tel_campana on public.candidatos (campana, telefono);

-- ── Libreta de bonos ─────────────────────────────────────────────────
create table public.bonos (
  id                uuid primary key default gen_random_uuid(),
  folio             text not null references public.candidatos(folio) on delete cascade,
  campana           text not null default 'FRESKO-CUMBRES-SEP26',
  tipo              text not null check (tipo in ('capacitacion','referido','puntualidad','otro')),
  monto             numeric(10,2) not null,
  concepto          text,
  folio_relacionado text,
  estatus           text not null default 'pendiente'
                      check (estatus in ('pendiente','por_pagar','pagado','cancelado')),
  fecha_pago        date,
  created_at        timestamptz not null default now()
);

create index idx_bonos_folio   on public.bonos (folio);
create index idx_bonos_estatus on public.bonos (estatus);
create unique index idx_bono_capacitacion_unico on public.bonos (folio) where tipo = 'capacitacion';
create unique index idx_bono_referido_unico on public.bonos (folio, folio_relacionado) where tipo = 'referido';

alter table public.candidatos enable row level security;
alter table public.bonos      enable row level security;
alter table public.parametros enable row level security;

-- ── Funciones ────────────────────────────────────────────────────────
create or replace function public.normalizar_folio(p_txt text)
returns text language plpgsql immutable as $$
declare d text;
begin
  if p_txt is null then return null; end if;
  d := regexp_replace(p_txt, '\D', '', 'g');
  if d = '' then return null; end if;
  return to_char(d::int, 'FM000');
end; $$;

create or replace function public.trg_bono_referido()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_monto numeric;
begin
  if new.referido_por_folio is null or new.referido_por_folio = new.folio then
    return new;
  end if;
  select bono_referido into v_monto from parametros where campana = new.campana;
  insert into bonos (folio, campana, tipo, monto, concepto, folio_relacionado, estatus)
  values (new.referido_por_folio, new.campana, 'referido', coalesce(v_monto, 50),
          'Invitó a ' || new.nombre || ' (folio ' || new.folio || ')',
          new.folio, 'pendiente')
  on conflict do nothing;
  return new;
end; $$;

create trigger bono_referido_al_registrar
after insert on public.candidatos
for each row execute function public.trg_bono_referido();

create or replace function public.trg_asistencia_capacitacion()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_monto numeric;
begin
  if new.asistio_capacitacion and not coalesce(old.asistio_capacitacion, false) then
    select bono_capacitacion into v_monto from parametros where campana = new.campana;
    insert into bonos (folio, campana, tipo, monto, concepto, estatus)
    values (new.folio, new.campana, 'capacitacion', coalesce(v_monto, 0),
            'Asistió a la capacitación', 'por_pagar')
    on conflict do nothing;
    update bonos set estatus = 'por_pagar'
     where tipo = 'referido' and folio_relacionado = new.folio and estatus = 'pendiente';
    if new.estatus in ('registrado','confirmado','lista_espera') then
      new.estatus := 'asistio_cita';
    end if;
    new.hora_registro_cita := coalesce(new.hora_registro_cita, now());
  elsif not new.asistio_capacitacion and coalesce(old.asistio_capacitacion, false) then
    delete from bonos where folio = new.folio and tipo = 'capacitacion' and estatus <> 'pagado';
    update bonos set estatus = 'pendiente'
     where tipo = 'referido' and folio_relacionado = new.folio and estatus = 'por_pagar';
  end if;
  return new;
end; $$;

create trigger asistencia_capacitacion
before update on public.candidatos
for each row execute function public.trg_asistencia_capacitacion();

create or replace function public.verificar_folio(p_folio text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_f text; v_nom text;
begin
  v_f := normalizar_folio(p_folio);
  if v_f is null then return jsonb_build_object('valido', false); end if;
  select split_part(nombre, ' ', 1) into v_nom from candidatos where folio = v_f;
  if v_nom is null then return jsonb_build_object('valido', false); end if;
  return jsonb_build_object('valido', true, 'nombre', v_nom, 'folio', v_f);
end; $$;

create or replace function public.registrar_candidato(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_tel text; v_nom text; v_folio text; v_ref text; v_ref_nom text;
  v_campana text; v_registrados int; v_meta int; v_abierto boolean;
  v_estatus text := 'registrado';
begin
  v_campana := coalesce(p->>'campana', 'FRESKO-CUMBRES-SEP26');
  select meta_folios, registro_abierto into v_meta, v_abierto
  from parametros where campana = v_campana;
  if not coalesce(v_abierto, true) then raise exception 'REGISTRO_CERRADO'; end if;

  v_tel := regexp_replace(coalesce(p->>'telefono',''), '\D', '', 'g');
  if length(v_tel) > 10 then v_tel := right(v_tel, 10); end if;
  v_nom := btrim(coalesce(p->>'nombre',''));

  if length(v_tel) <> 10 then raise exception 'TELEFONO_INVALIDO'; end if;
  if length(v_nom) < 5   then raise exception 'NOMBRE_INVALIDO';   end if;
  if coalesce((p->>'acepta_aviso')::boolean, false) is not true then
    raise exception 'AVISO_NO_ACEPTADO';
  end if;

  select folio into v_folio from candidatos
  where telefono = v_tel and campana = v_campana;
  if v_folio is not null then
    return jsonb_build_object('folio', v_folio, 'duplicado', true);
  end if;

  v_ref := normalizar_folio(p->>'referido_por_folio');
  if v_ref is not null then
    select split_part(nombre,' ',1) into v_ref_nom from candidatos where folio = v_ref;
    if v_ref_nom is null then v_ref := null; end if;
  end if;

  select count(*) into v_registrados from candidatos
  where campana = v_campana and estatus <> 'baja';
  if v_registrados >= coalesce(v_meta, 70) then v_estatus := 'lista_espera'; end if;

  insert into candidatos (
    campana, nombre, telefono, correo, edad, genero,
    colonia, municipio, talla_playera, experiencia,
    disponible_completa, tiene_ine, transporte, comentarios,
    referido_por_folio, referido_por_nombre, como_se_entero,
    futuras_activaciones, acepta_aviso, estatus
  ) values (
    v_campana, v_nom, v_tel,
    nullif(btrim(coalesce(p->>'correo','')),''),
    nullif(p->>'edad','')::int,
    nullif(p->>'genero',''),
    nullif(btrim(coalesce(p->>'colonia','')),''),
    coalesce(nullif(p->>'municipio',''), 'Monterrey'),
    nullif(p->>'talla_playera',''),
    nullif(p->>'experiencia',''),
    coalesce((p->>'disponible_completa')::boolean, false),
    coalesce((p->>'tiene_ine')::boolean, false),
    nullif(p->>'transporte',''),
    nullif(btrim(coalesce(p->>'comentarios','')),''),
    v_ref,
    nullif(btrim(coalesce(p->>'referido_por_nombre','')),''),
    nullif(p->>'como_se_entero',''),
    coalesce((p->>'futuras_activaciones')::boolean, true),
    true, v_estatus
  ) returning folio into v_folio;

  return jsonb_build_object('folio', v_folio, 'duplicado', false,
                            'estatus', v_estatus, 'invitado_por', v_ref_nom);
end; $$;

revoke all on function public.registrar_candidato(jsonb) from public;
revoke all on function public.verificar_folio(text)      from public;
grant execute on function public.registrar_candidato(jsonb) to anon, authenticated;
grant execute on function public.verificar_folio(text)      to anon, authenticated;

-- ── Vistas ───────────────────────────────────────────────────────────
create or replace view public.v_avance as
select p.meta_folios as meta,
  count(c.*) filter (where c.estatus <> 'baja') as registrados,
  greatest(p.meta_folios - count(c.*) filter (where c.estatus <> 'baja'), 0) as faltan,
  count(c.*) filter (where c.asistio_capacitacion) as asistieron_capacitacion,
  count(c.*) filter (where c.estatus = 'lista_espera') as lista_espera,
  count(c.*) filter (where c.referido_por_folio is not null) as por_referido
from public.parametros p
left join public.candidatos c on c.campana = p.campana
group by p.meta_folios;

create or replace view public.v_lista_cita as
select c.folio, c.nombre, c.telefono, c.edad, c.colonia, c.talla_playera,
  c.experiencia, c.tiene_ine, c.disponible_completa,
  c.referido_por_folio as invitado_por_folio, r.nombre as invitado_por,
  c.asistio_capacitacion, c.estatus,
  to_char(c.created_at at time zone 'America/Monterrey', 'DD/MM HH24:MI') as se_registro
from public.candidatos c
left join public.candidatos r on r.folio = c.referido_por_folio
where c.campana = 'FRESKO-CUMBRES-SEP26'
order by c.folio;

create or replace view public.v_referidos as
select b.folio as folio_invita, r.nombre as invita, r.telefono as tel_invita,
  b.folio_relacionado as folio_invitado, c.nombre as invitado,
  c.asistio_capacitacion as invitado_asistio, b.monto, b.estatus
from public.bonos b
join public.candidatos r on r.folio = b.folio
left join public.candidatos c on c.folio = b.folio_relacionado
where b.tipo = 'referido'
order by b.folio, b.created_at;

create or replace view public.v_bonos_por_pagar as
select c.folio, c.nombre, c.telefono,
  coalesce(sum(b.monto) filter (where b.tipo='capacitacion' and b.estatus='por_pagar'),0) as bono_capacitacion,
  count(b.*) filter (where b.tipo='referido' and b.estatus='por_pagar') as referidos_validos,
  coalesce(sum(b.monto) filter (where b.tipo='referido' and b.estatus='por_pagar'),0) as bono_referidos,
  coalesce(sum(b.monto) filter (where b.estatus='por_pagar'),0) as total_por_pagar,
  coalesce(sum(b.monto) filter (where b.estatus='pendiente'),0) as aun_pendiente,
  coalesce(sum(b.monto) filter (where b.estatus='pagado'),0) as ya_pagado
from public.candidatos c
left join public.bonos b on b.folio = c.folio
where c.campana = 'FRESKO-CUMBRES-SEP26'
group by c.folio, c.nombre, c.telefono
having coalesce(sum(b.monto),0) > 0
order by total_por_pagar desc, c.folio;

create or replace view public.v_ranking_referidores as
select c.folio, c.nombre, c.telefono,
  count(x.*) as invitados,
  count(x.*) filter (where x.asistio_capacitacion) as invitados_que_llegaron,
  count(x.*) filter (where x.asistio_capacitacion) *
    (select bono_referido from public.parametros where campana='FRESKO-CUMBRES-SEP26') as ganado
from public.candidatos c
join public.candidatos x on x.referido_por_folio = c.folio
group by c.folio, c.nombre, c.telefono
order by invitados_que_llegaron desc, invitados desc;

-- ── Cierre de accesos ────────────────────────────────────────────────
alter view public.v_avance              set (security_invoker = on);
alter view public.v_lista_cita          set (security_invoker = on);
alter view public.v_referidos           set (security_invoker = on);
alter view public.v_bonos_por_pagar     set (security_invoker = on);
alter view public.v_ranking_referidores set (security_invoker = on);

revoke all on public.v_avance, public.v_lista_cita, public.v_referidos,
              public.v_bonos_por_pagar, public.v_ranking_referidores
       from anon, authenticated;
revoke all on public.candidatos, public.bonos, public.parametros
       from anon, authenticated;
