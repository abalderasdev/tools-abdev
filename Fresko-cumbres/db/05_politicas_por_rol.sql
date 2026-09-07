-- ============================================================
-- Fresko Cumbres · 05 · Políticas de lectura según el rol
-- ============================================================
-- Regla: "equipo" ve gente, "admin" ve además el dinero.
-- Las pantallas de equipo (/lista, /puestos) y las públicas
-- (/, /checar) no leen estas tablas directamente: usan funciones
-- security definer, así que restringirlas no las rompe.
-- ============================================================

-- Gente: la ve cualquiera con acceso (equipo o admin).
drop policy if exists dashboard_lee_candidatos on candidatos;
create policy dashboard_lee_candidatos on candidatos for select to authenticated
  using (public.puede_lista());

-- Dinero, tarifas e historial de asistencia: solo administrador.
-- (Las vistas v_estado_cuenta / v_bonos_por_pagar heredan esto
--  porque están marcadas con security_invoker = on.)
drop policy if exists dashboard_lee_bonos on bonos;
create policy dashboard_lee_bonos on bonos for select to authenticated
  using (public.es_admin());

drop policy if exists dashboard_lee_parametros on parametros;
create policy dashboard_lee_parametros on parametros for select to authenticated
  using (public.es_admin());

drop policy if exists dashboard_lee_asistencia on asistencia;
create policy dashboard_lee_asistencia on asistencia for select to authenticated
  using (public.es_admin());

-- Equipos, suplencias y puntos: quien tiene acceso.
drop policy if exists equipos_lectura on equipos;
create policy equipos_lectura on equipos for select to authenticated
  using (public.puede_lista());

drop policy if exists suplencias_lectura on suplencias;
create policy suplencias_lectura on suplencias for select to authenticated
  using (public.puede_lista());

drop policy if exists dashboard_lee_puntos on puntos;
create policy dashboard_lee_puntos on puntos for select to authenticated
  using (public.puede_lista());

-- Quién tiene acceso: cada quien ve su fila; el admin las ve todas.
drop policy if exists ve_su_propio_acceso on dashboard_acceso;
create policy ve_su_propio_acceso on dashboard_acceso for select to authenticated
  using (user_id = auth.uid());

drop policy if exists admin_ve_accesos on dashboard_acceso;
create policy admin_ve_accesos on dashboard_acceso for select to authenticated
  using (public.es_admin());

drop policy if exists admin_ve_invitaciones on invitaciones;
create policy admin_ve_invitaciones on invitaciones for select to authenticated
  using (public.es_admin());

-- bitacora: RLS activo y CERO políticas a propósito.
-- No se puede leer por la API con ninguna sesión; solo desde el
-- editor SQL de Supabase o con la service_role key.
