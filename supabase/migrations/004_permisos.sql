-- Dogo · 004 permisos (§4.3): se revoca TODO y se concede solo lo necesario.
revoke all on all functions in schema dogo from public, anon, authenticated;
alter default privileges in schema dogo revoke execute on functions from public, anon, authenticated;
grant usage on schema dogo to anon, authenticated;

-- Cliente final (sin sesión)
grant execute on function
  dogo.catalogo(),
  dogo.crear_pedido(text, text, text, text, text, jsonb, text, text),
  dogo.evento(text, text, text, text)
to anon, authenticated;

-- Dueño y personal (con sesión; las funciones verifican es_staff())
grant execute on function
  dogo.yo(), dogo.panel(date), dogo.pedido_estado(text, text), dogo.producto_guardar(text, numeric, numeric, boolean),
  dogo.inversion_guardar(text, numeric), dogo.envio_guardar(numeric, numeric)
to authenticated;
-- Ayudas internas (tel, limpio, canal_ok, nuevo_codigo, es_staff, _inmutable): sin permiso para nadie.
