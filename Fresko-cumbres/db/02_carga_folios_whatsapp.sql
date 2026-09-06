-- =====================================================================
--  CARGA DE LOS FOLIOS ENTREGADOS POR WHATSAPP  ·  006 al 027
--  Extraído de los chats del 3 al 6 de septiembre de 2026.
--  Pega esto en Supabase > SQL Editor y córrelo completo.
--
--  ANTES DE CORRERLO, LEE ESTO:
--
--  1. REASIGNACIÓN DE FOLIOS DUPLICADOS
--     Cuatro folios se habían entregado dos veces. Conserva el número
--     quien lo recibió primero; el segundo se movió al rango libre,
--     bajando desde el 009:
--
--       016 → 009  Giesy del Carmen Martínez Bello   (Carla Medrano conserva el 016)
--       021 → 008  José Armando Ávila Martínez       (Aide Alondra conserva el 021)
--       024 → 007  Mariana Lucero López Vázquez      (Cristofer Luna conserva el 024)
--       027 → 006  Evelin Ortiz Ojeda                (Baldomero Santos conserva el 027)
--
--     Las cuatro personas reasignadas TODAVÍA NO SABEN de su nuevo folio.
--     Hay que avisarles antes del martes.
--
--  2. BONOS DE REFERIDO
--     El trigger genera un bono de $50 en estado 'pendiente' por cada
--     fila con referido_por_folio. Aquí se generan DOS:
--       018 Juan Manuel Banda  → invitado por 017 Simonita Ramona
--       025 Juan José González → invitado por 008 José Armando
--     Leticia Medina (015) la trajo su esposo Cristhian (014), pero se
--     dejó SIN referido_por_folio para no generar un bono que quizá no
--     quieres pagar. Si sí lo quieres, al final del archivo está la línea.
--
--  3. acepta_aviso QUEDA EN false
--     Estas personas mandaron sus datos por WhatsApp, nunca vieron el
--     aviso de privacidad del formulario. Marcarlo true sería afirmar un
--     consentimiento que no dieron. Si les compartes el aviso y aceptan,
--     actualízalo (línea al final).
--
--  4. NO TOCA LA SECUENCIA
--     Los folios van explícitos, así que folio_seq sigue donde está.
--     Tus registros 030 y 031 no se ven afectados.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
--  Cristhian (014) y su esposa Leticia (015) COMPARTEN TELÉFONO: solo
--  tienen un aparato. El índice único (campana, telefono) lo impedía.
--
--  Se relaja a índice normal. No se pierde la protección contra
--  registros duplicados desde el formulario: registrar_candidato() ya
--  busca el teléfono antes de insertar y devuelve {duplicado:true} en
--  vez de crear otra fila.
-- ---------------------------------------------------------------------
drop index if exists public.idx_cand_tel_campana;
create index if not exists idx_cand_tel_campana
  on public.candidatos (campana, telefono);

insert into public.candidatos
  (folio, nombre, telefono, edad, colonia, municipio, talla_playera,
   experiencia, disponible_completa, tiene_ine,
   referido_por_folio, referido_por_nombre, como_se_entero,
   acepta_aviso, estatus, notas_internas)
values
  ('006','Evelin Ortiz Ojeda','9381829675',52,'Terminal','Monterrey','M',
   'algo',true,true,null,null,'facebook',false,'registrado',
   'REASIGNADA del folio 027 (duplicado con Baldomero Santos). Avisarle del cambio.'),

  ('007','Mariana Lucero López Vázquez','8119950858',38,'El Mirador','San Nicolás','M',
   'ninguna',true,true,null,null,'facebook',false,'registrado',
   'REASIGNADA del folio 024 (duplicado con Cristofer Luna). Su INE es del estado de Tamaulipas. Avisarle del cambio.'),

  ('008','José Armando Ávila Martínez','8134159492',54,'Riberas de la Morena','Juárez','G',
   null,true,true,null,null,'me invitaron',false,'registrado',
   'REASIGNADO del folio 021 (duplicado con Aide Alondra). Refirió a Juan José González (025). Avisarle del cambio.'),

  ('009','Giesy del Carmen Martínez Bello','8182603336',40,'Parques Diamante','García','G',
   'algo',true,true,null,null,'facebook',false,'registrado',
   'REASIGNADA del folio 016 (duplicado con Carla Medrano). Preguntó si dan de alta en IMSS. Avisarle del cambio.'),

  ('010','María del Rosario Grimaldo Zapién','8118567010',44,'Fomerrey 1','Monterrey','CH',
   'ninguna',true,true,null,null,'facebook',false,'confirmado',
   'Le dicen Rosy. Confirmó: "ahí estaré presente".'),

  ('011','Ana Laura Rodríguez Herrera','8117178637',42,'Lomas de San Genaro','Escobedo','M',
   'algo',true,true,null,null,'facebook',false,'registrado',
   'La agencia la pasó como "Sofi".'),

  ('012','Karina Guadalupe Montenegro González','8135916484',null,'Portales de Lincoln','García','XG',
   'ninguna',true,true,null,null,'facebook',false,'registrado',
   'Le dicen Kary. No dio edad. Dijo "déjame checo y te aviso" — RECONFIRMAR.'),

  ('013','Jesús Guadalupe Betancourt Reyna','8128798223',46,'Valle de San Francisco','Escobedo','XG',
   'mucha',true,true,null,null,'facebook',false,'registrado',
   'Ya fue promotor. Dijo que va a invitar conocidos.'),

  ('014','Cristhian Sotelo Rodríguez','8130924010',42,'Hidalgo','Monterrey','XL',
   'mucha',true,true,null,null,'facebook',false,'confirmado',
   'Volantero con experiencia. Calle Manuel González 523. COMPARTE TELÉFONO con su esposa Leticia (folio 015): solo tienen un aparato.'),

  ('015','Leticia Medina Saucedo','8130924010',53,'Hidalgo','Monterrey','XL',
   'algo',true,null,null,null,'me invitaron',false,'registrado',
   'Esposa de Cristhian (014), mismo domicilio y MISMO TELÉFONO. Él la propuso. Sin referido_por_folio para no generar bono automático.'),

  ('016','Carla Patricia Medrano Arias','8125895238',43,'Fomerrey 112','Monterrey','XG',
   null,true,null,null,null,'me invitaron',false,'registrado',
   'CONSERVA el 016 por haberlo recibido primero (5 sep, 5:11 p.m.).'),

  ('017','Simonita Ramona de León Sánchez','8123805601',52,'Magnolias','Apodaca','G',
   'ninguna',true,true,null,null,'facebook',false,'confirmado',
   'Invitó a Juan Manuel Banda (018).'),

  ('018','Juan Manuel Banda de León','8130546925',23,'Magnolias','Apodaca','M',
   'algo',true,true,'017','Simonita Ramona de León Sánchez','me invitaron',false,'confirmado',
   'Pidió expresamente que se le abonara el bono a quien lo invitó.'),

  ('019','Eloísa Salazar de la Cruz','8180760049',29,'Salvador Allende y Padre Mier','Monterrey','M',
   null,null,null,null,null,'me invitaron',false,'baja',
   'DECLINÓ: "no me va a alcanzar el sueldo". Se conserva el registro para no reutilizar el folio por error.'),

  ('020','Nora Arcelia García Cázares','8333893146',52,'González','Pánuco, Veracruz','M',
   'mucha',true,true,null,null,'facebook',false,'confirmado',
   'Vive en Pánuco, Veracruz, pero ya ha trabajado en Monterrey. Confirmó: "ahí estaré".'),

  ('021','Aide Alondra Martínez Hernández','8135992477',24,null,'Monterrey','CH',
   'ninguna',true,false,null,null,'facebook',false,'registrado',
   'CONSERVA el 021 por haberlo recibido primero (5 sep, 8:40 p.m.). INE EXTRAVIADA, la está buscando — VERIFICAR EL MARTES.'),

  ('022','María de los Ángeles Robles Esquivel','8187079392',50,'Altavilla','García','G',
   'ninguna',true,true,null,null,'facebook',false,'registrado',
   'La agencia la pasó como "Angy Ezquivel".'),

  ('023','Aurora Guadalupe Díaz Cázares','8116633343',43,'Fomerrey 112','Monterrey',null,
   null,true,true,null,null,'facebook',false,'registrado',
   'FALTA TALLA DE PLAYERA.'),

  ('024','Cristofer Luna Ovalle','8186576270',20,'Independencia','Monterrey','G',
   'ninguna',true,true,null,null,'facebook',false,'registrado',
   'CONSERVA el 024 por haberlo recibido primero (5 sep, 11:30 p.m.).'),

  ('025','Juan José González García','8118642787',35,'Vistas del Río','Juárez','M',
   null,true,true,'008','José Armando Ávila Martínez','me invitaron',false,'confirmado',
   'Lo refirió José Armando (folio 008, antes 021). Confirmó: "nos vemos el martes".'),

  ('026','Gladys Magaly Reyes Velazco','8125702887',null,null,null,null,
   null,null,null,null,null,'me invitaron',false,'registrado',
   'Solo dijo "me interesa". FALTAN TODOS SUS DATOS: edad, colonia, talla, INE, disponibilidad.'),

  ('027','Baldomero Santos Santos','5661857999',34,'Portal de Lincoln','García','M',
   'ninguna',true,true,null,null,'facebook',false,'registrado',
   'CONSERVA el 027 por haberlo recibido primero (6 sep, 9:18 a.m.). En WhatsApp aparece como "lucas".')

on conflict (folio) do nothing;

commit;


-- =====================================================================
--  VERIFICACIÓN
-- =====================================================================

-- Deben salir 22 filas nuevas (006-027) más tus 030 y 031 = 24 en total.
select count(*) as total_candidatos from public.candidatos;

-- Los cuatro reasignados, para tener a la mano a quién avisarle:
select folio, nombre, telefono, notas_internas
from public.candidatos
where notas_internas like 'REASIGNAD%'
order by folio;

-- Los dos bonos de referido que generó el trigger (deben estar en 'pendiente'):
select * from public.v_referidos;

-- La secuencia debe seguir intacta, lista para el 032:
select last_value from public.folio_seq;

-- Avance general:
select * from public.v_avance;


-- =====================================================================
--  OPCIONALES · descoméntalos solo si aplican
-- =====================================================================

-- Si SÍ quieres pagarle a Cristhian el bono por traer a su esposa.
-- Ojo: el trigger solo corre en insert, así que hay que hacer las dos cosas.
-- update public.candidatos
--    set referido_por_folio = '014', referido_por_nombre = 'Cristhian Sotelo Rodríguez'
--  where folio = '015';
-- insert into public.bonos (folio, campana, tipo, monto, concepto, folio_relacionado, estatus)
-- values ('014','FRESKO-CUMBRES-SEP26','referido',
--         (select bono_referido from public.parametros where campana='FRESKO-CUMBRES-SEP26'),
--         'Invitó a Leticia Medina Saucedo (folio 015)','015','pendiente');

-- Cuando les compartas el aviso de privacidad y lo acepten:
-- update public.candidatos set acepta_aviso = true
--  where folio between '006' and '027';
