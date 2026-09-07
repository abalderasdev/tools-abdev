# Concurso de fotos — mecánica

Premio diario por equipo durante la activación (9 al 13 de septiembre).
Todavía **no está construido**: esto es el diseño para armarlo cuando ya
existan los equipos con nombre, después de la capacitación del martes.

## La idea en una frase

Cada equipo sube **una foto al día**. Un jurado vota esa misma tarde y el
equipo ganador se lleva **$250 el día siguiente**, junto con el pago normal.

## Reglas del juego

**Quién participa.** El equipo, no la persona. Cada equipo sube una sola foto
por día — la que ellos decidan entre todos. Si suben más de una, cuenta la
última antes del cierre.

**Qué se vale.** Foto tomada ese día, en el punto de trabajo, con al menos dos
personas del equipo visibles y el uniforme puesto (playera, gorra o mandil).
Nada de fotos de días anteriores ni de otro equipo.

**Ventana de subida.** De las 9:00 a las 15:30. Media hora después del cierre
de la jornada para que alcancen a subirla sin prisas.

**Votación.** De 15:30 a 19:00. El resultado se publica a las 19:00 y el pago
entra en el corte del día siguiente.

**Premio.** $250 al equipo. Se reparte entre quienes **estuvieron presentes
ese día** en ese equipo — quien faltó no entra en el reparto de ese día.
Si el equipo tiene 5 presentes, son $50 por cabeza; si tiene 4, $62.50.
El monto exacto por persona lo calcula el sistema y aparece en su estado
de cuenta como "premio de foto".

**Empate.** Gana el equipo que subió primero. Simple y sin discusión.

**Un equipo puede ganar varios días.** No hay tope: si su foto es la mejor
tres días seguidos, se llevan $750.

## El jurado

Un grupo pequeño y fijo de personas con voto, definido antes de que empiece
la activación. Cada jurado da **un voto por día** y no puede votar por su
propio equipo (si es que pertenece a alguno).

Un juez vota desde un enlace personal —igual que las invitaciones al panel:
recibe su liga, entra, ve las fotos del día **sin saber de qué equipo es
cada una** (solo "Foto 1, Foto 2, Foto 3…"), y elige una. El anonimato evita
que el voto se vaya por amistad en vez de por la foto.

Pendiente de que definas:

- **Quiénes son los jueces.** Sugerencia: tú, alguien de Fresko y Diana de MMP.
  Tres es buen número: siempre hay mayoría y nadie carga solo con la decisión.
- **Si el jurado es el mismo los cinco días** o rota.
- **Si el personal también vota.** Se puede abrir un voto popular que valga,
  por decir algo, como un juez más. Sube la participación pero se presta a
  que el equipo más grande gane siempre.

## Qué se construiría

Tres piezas, ninguna complicada, sobre lo que ya existe:

**1. Subir la foto.** Un botón en `/checar`, visible solo entre 9:00 y 15:30
y solo si ya marcaste entrada. Va al mismo bucket privado que las fotos de
INE, en una carpeta aparte. Reusa el encogedor de imagen que ya escribimos.

**2. Votar.** Una pantalla nueva, `/jurado`, con enlace por token igual que
`/equipo`. Muestra las fotos del día barajadas y sin nombre. Un voto por
juez por día, cambiable hasta que cierre la votación.

**3. Anunciar y pagar.** El conteo sale en el dashboard, en la pestaña de
asistencias y dinero: qué equipo ganó cada día, con cuántos votos, y cuánto
se le suma a cada quien. El premio se registra como un bono más, del mismo
tipo que el de puntualidad, para que caiga solo en el estado de cuenta.

En base de datos son dos tablas (`fotos_concurso` y `votos_concurso`) y un
tipo de bono nuevo. Nada que toque lo que ya funciona.

## Lo que hay que cuidar

- **Las fotos son de personas identificables.** Se quedan en el bucket privado
  y se borran al terminar la activación, igual que las fotos de INE.
- **El premio motiva, pero no debe distraer.** La foto se toma en un descanso,
  no dejando el punto solo. Vale la pena decirlo en voz alta el martes.
- **Si un equipo no sube foto, no pasa nada.** No hay castigo; simplemente ese
  día no compite.
