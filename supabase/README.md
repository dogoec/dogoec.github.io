# Dogo · base de datos (Supabase)

Schema propio `dogo`. Ninguna tabla se lee ni se escribe directo: todo pasa por funciones SQL con validación y límites (CLAUDE.md §4).

| Quién | Funciones |
|---|---|
| Cliente en la tienda (anon) | `catalogo()` · `crear_pedido(...)` · `evento(...)` |
| Dueño (`admin`) | todo lo del equipo + `producto_guardar` · `envio_guardar` · `inversion_guardar` · `producto_compra_config` · `equipo_lista` · `invitacion_crear/cancelar` · `equipo_rol` · `equipo_quitar` |
| Equipo (`ventas`) | `yo()` · `panel(desde)` (sin costos ni inversión) · `pedido_estado` · `inventario()` · `compra_registrar` (sin costo) · `inventario_contar` |
| Persona invitada (con sesión, aún sin rol) | `invitacion_activar(codigo)`: el correo de su cuenta debe ser el de la invitación; 5 fallos → 30 min de bloqueo |

Qué asegura:
- **Precios:** salen de la base. Los que manda el navegador se ignoran, y el costo nunca se expone al público.
- **Límites:** máximo 4 pedidos por teléfono por hora y 60 pedidos por hora en total. Los eventos del embudo también tienen tope por sesión y por hora.
- **Historial que no se borra:** pedidos, ítems e historial de estados no se editan ni se borran. Para anular un pedido se le agrega el estado "anulado".
- **Precio del momento:** cada pedido guarda el precio y el costo con que se vendió, así un cambio de precio no altera las ventas pasadas.

## Activar (una sola vez)
1. **SQL Editor** → pegar `instalar-todo.sql` completo → Run.
2. **Project Settings → Data API → Exposed schemas**: agregar `dogo` y guardar.
3. **Authentication → Users → Add user**: correo y clave del dueño, con *Auto Confirm User*. Después, en SQL Editor:
   ```sql
   insert into dogo.staff (user_id, nombre)
   select id, 'Dueño' from auth.users where email = 'CORREO-DEL-DUEÑO';
   ```
4. **Authentication → Sign In / Providers**: desactivar *Allow new users to sign up* (§4.10).
5. En `config.js` de la web: `supabase: { url: 'https://<proyecto>.supabase.co', anonKey: '<clave anon public>', schema: 'dogo' }`. Solo la clave **anon**, nunca `service_role`.

Con el paso 5 publicado:
- La tienda guarda cada pedido en la base antes de abrir WhatsApp.
- El panel pide correo y clave y muestra los pedidos reales.
- Los precios y el envío se editan desde el panel.

Si la base no responde, el pedido igual sale por WhatsApp con todo el detalle.

## Actualizar una instalación existente a 006 (equipo y compras)
Si ya estaban 001…005 (producción de Dogo desde el 13 oct 2026): en **SQL Editor** pegar solo `migrations/006_equipo_y_compras.sql` y **Run una vez**. Comprobar:
```sql
select (select count(*) from information_schema.tables where table_schema = 'dogo') tablas,
       (select count(*) from pg_proc where pronamespace = 'dogo'::regnamespace) funciones;   -- 13 y 28
```
No toca pedidos ni precios: agrega columnas de compra a productos, el libro de inventario, invitaciones, y reemplaza 4 funciones de 003 para distinguir dueño y equipo.

## Equipo e inventario
- El dueño invita desde la pestaña **Equipo**: nombre, correo y rol. Recibe un código de 8 letras (vence en 72 h) y lo manda por WhatsApp. La persona entra al panel, toca "¿Te invitaron al equipo?", escribe su correo, crea su clave y el código. No hace falta entrar a Supabase.
- **Stock** = conteos + compras − packs vendidos en pedidos no anulados, desde el primer movimiento del producto. El libro de movimientos no se edita: un conteo físico guarda la diferencia como ajuste.
- **Proyección** (en el panel): promedio ponderado de 4 semanas completas (40/30/20/10 %), tendencia limitada a ±15 %, stock de seguridad al 95 % (`1,65 × σ × √((entrega + cobertura) / 7)`), compra = venta diaria × (entrega + cobertura) + seguridad − stock, redondeada al múltiplo. La precisión se prueba con las 4 semanas anteriores.

## Probar
```bash
PGURI=postgresql://postgres@localhost:5432/postgres python3 clientes/dogo/supabase/probar.py   # 103 pruebas
```
Crea una base temporal, aplica 001…006 y revisa permisos, límites, precios en SQL e inmutabilidad.

## Migraciones
`migrations/001_esquema.sql` · `002_funciones_tienda.sql` · `003_funciones_panel.sql` · `004_permisos.sql` · `005_datos_base.sql` · `006_equipo_y_compras.sql`. `instalar-todo.sql` es la unión de las seis, para pegar de una vez. Un cambio posterior va en una migración nueva numerada (007…), nunca editando una ya aplicada.
