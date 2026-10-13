# Dogo · base de datos (Supabase)

Schema propio `dogo`. Ninguna tabla se lee ni se escribe directo: todo pasa por funciones SQL con validación y límites (CLAUDE.md §4).

| Quién | Funciones |
|---|---|
| Cliente en la tienda (anon) | `catalogo()` · `crear_pedido(...)` · `evento(...)` |
| Dueño en el panel (con sesión y en `dogo.staff`) | `yo()` · `panel(desde)` · `pedido_estado(codigo, estado)` · `producto_guardar(...)` · `inversion_guardar(...)` · `envio_guardar(...)` |

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

## Probar
```bash
PGURI=postgresql://postgres@localhost:5432/postgres python3 clientes/dogo/supabase/probar.py   # 64 pruebas
```
Crea una base temporal, aplica 001…005 y revisa permisos, límites, precios en SQL e inmutabilidad.

## Migraciones
`migrations/001_esquema.sql` · `002_funciones_tienda.sql` · `003_funciones_panel.sql` · `004_permisos.sql` · `005_datos_base.sql`. `instalar-todo.sql` es la unión de las cinco, para pegar de una vez. Un cambio posterior va en una migración nueva numerada (006…), nunca editando una ya aplicada.
