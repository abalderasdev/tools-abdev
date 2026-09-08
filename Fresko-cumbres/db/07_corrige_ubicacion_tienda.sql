-- ============================================================
-- Fresko Cumbres · 07 · CORRECCIÓN de la ubicación de la tienda
-- ============================================================
-- La tienda correcta es FRESKO VALLE DE CUMBRES, en Mitras Poniente
-- (C.P. 66035), no la de Av. Paseo de los Leones 1261 / Cumbres
-- Mediterráneo que se venía usando. El geocerco estaba a 4.8 km del
-- lugar real: /checar habría rechazado a todo el personal.
--
-- Mapa: https://maps.app.goo.gl/BKYH7zbtHEbzUeHd7
-- Cómo llegar en camión: Ruta Cumbres C29, bajar en Plaza Puerta de
-- Hierro y caminar 500 m sobre Av. Paseo de los Leones.
-- ============================================================

update puntos
set nombre = 'Fresko Valle de Cumbres · Mitras Poniente',
    lat = 25.7551505,
    lon = -100.4405221,
    radio_m = 400
where clave = 'tienda';
