-- =====================================================================
--  CARGA DE LOS FOLIOS QUE YA ENTREGASTE A MANO (010 al 029)
--  Pega esto en Supabase > SQL Editor, llena los datos y córrelo.
--  Ponle el folio explícito a cada uno para que respete tu numeración.
-- =====================================================================

insert into public.candidatos
  (folio, nombre, telefono, edad, colonia, talla_playera, experiencia,
   disponible_completa, tiene_ine, referido_por_folio, como_se_entero, acepta_aviso)
values
  ('010','NOMBRE COMPLETO','8110000000',25,'Cumbres','M','ninguna',true,true,null,'facebook',true),
  ('011','NOMBRE COMPLETO','8110000001',22,'Cumbres','CH','algo',  true,true,null,'facebook',true),
  ('012','NOMBRE COMPLETO','8110000002',30,'Cumbres','G','ninguna',true,true,'010','amigo',   true)
  -- … sigue hasta el 029
on conflict (folio) do nothing;

-- Si alguno fue invitado por otro, pon su folio en la columna
-- referido_por_folio y el bono de $50 se genera solo.

-- Después de cargarlos, verifica que el siguiente folio sea el 030:
select last_value from public.folio_seq;
-- Si quedó en otro número, corrígelo así:
-- select setval('public.folio_seq', 30, false);

-- Cuántos llevas y cuántos faltan:
select * from public.v_avance;
