# Manual de operación

**Proyecto Supabase:** `activaciones-personal`
**Panel:** https://supabase.com/dashboard/project/eykfdnoczpwjccunzfgh
**Campaña:** `FRESKO-CUMBRES-SEP26` · meta 70 folios · siguiente folio: **030**

Todas las consultas van en **SQL Editor** del panel.

---

## Lo único que falta antes de publicar

1. **Definir el bono de capacitación.** Quedó en $0 porque no me dijiste el monto:
   ```sql
   update parametros set bono_capacitacion = 150 where campana = 'FRESKO-CUMBRES-SEP26';
   ```
2. **Cargar los folios de WhatsApp** con `db/02_carga_folios_whatsapp.sql` (rango 006–027).
3. **Publicar el sitio.** Ya está en Vercel desde el repo `abalderasdev/tools-abdev`;
   cada push a `main` redespliega solo. El archivo es `public/index.html` y ya
   trae las llaves del proyecto, no hay que tocarle nada.

---

## Cómo funcionan los dos bonos

**Bono de capacitación.** En cuanto marcas que alguien asistió, se le genera su bono
en estado `por_pagar` y su estatus pasa a `asistio_cita`. Si te equivocas y lo
desmarcas, el bono se cancela solo.

**Bono de referido ($50).** Cuando alguien se registra poniendo el folio de quien lo
invitó, se crea el bono en estado `pendiente`. Pasa a `por_pagar` **solo cuando la
persona invitada asiste a la capacitación**. Así nadie cobra por invitar gente que
no llega. Si prefieres pagarlo con el simple registro, dime y lo cambio.

---

## El martes 8 en Fresko Cumbres

Lista para pasar asistencia:
```sql
select folio, nombre, telefono, invitado_por, talla_playera from v_lista_cita;
```

Conforme van llegando (uno o varios folios a la vez):
```sql
update candidatos set asistio_capacitacion = true
where folio in ('030','031','045');
```

Cuánto tienes que pagar ese día:
```sql
select * from v_bonos_por_pagar;
```

Al entregar el dinero:
```sql
update bonos set estatus = 'pagado', fecha_pago = current_date
where estatus = 'por_pagar' and folio = '030';
```

---

## Seguimiento del reclutamiento

```sql
select * from v_avance;              -- registrados, faltantes, cuántos por referido
select * from v_ranking_referidores; -- quién está trayendo más gente
select * from v_referidos;           -- quién invitó a quién y si ya se ganó el bono
```

Al llegar a 70, los nuevos entran automáticamente como `lista_espera` (no se
rechazan, quedan en la base). Para cerrar el formulario por completo:
```sql
update parametros set registro_abierto = false where campana = 'FRESKO-CUMBRES-SEP26';
```

---

## Después de la activación

Califica a cada quien; esto es lo que hace valiosa la base para la próxima:
```sql
update candidatos set calificacion = 5, notas_internas = 'Puntual, buena actitud'
where folio = '030';
```

Lista de primeros invitados para la siguiente activación:
```sql
select folio, nombre, telefono, colonia from candidatos
where futuras_activaciones and calificacion >= 4 order by calificacion desc;
```

Para reusar todo en otra campaña, sin perder el historial:
```sql
insert into parametros (campana, nombre_evento, pago_por_dia, bono_referido, meta_folios)
values ('SIGUIENTE-ACTIVACION', 'Nombre del evento', 450, 50, 40);
```
Y en `public/index.html` cambias la constante `CAMPANA`.

---

## Seguridad

La llave que trae el formulario es pública a propósito, pero **solo puede
registrar**: no puede leer, editar ni borrar nada. Ya lo probé conectándome con
esa llave. Los datos únicamente se ven desde tu panel de Supabase.
