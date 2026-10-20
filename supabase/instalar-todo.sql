-- Dogo · instalación completa en Supabase (pegar entero en SQL Editor y ejecutar una sola vez).
-- Generado de supabase/migrations/001…006. No editar aquí: editar las migraciones.

-- ===== 001_esquema.sql =====
-- Dogo · 001 esquema (schema propio: dogo).
-- CLAUDE.md §4: RLS en todas las tablas y SIN políticas. anon y authenticated nunca leen ni escriben tablas:
-- todo pasa por funciones security definer (002 tienda, 003 panel) con validación y límites.
create schema if not exists dogo;

create table dogo.config (
  id int primary key default 1 check (id = 1),
  envio_domicilio numeric(8,2) not null default 2.00 check (envio_domicilio >= 0),
  gratis_desde numeric(8,2) not null default 20.00 check (gratis_desde >= 0),
  max_pedidos_tel_hora int not null default 4 check (max_pedidos_tel_hora between 1 and 50),     -- por teléfono
  max_pedidos_hora int not null default 60 check (max_pedidos_hora between 1 and 2000),         -- global, contra abuso
  max_eventos_sesion_hora int not null default 300 check (max_eventos_sesion_hora between 10 and 5000),
  max_eventos_hora int not null default 20000 check (max_eventos_hora between 100 and 500000)
);
insert into dogo.config default values;

-- Personal con acceso al panel. Se da de alta por SQL (ver README): el registro público de Supabase va desactivado (§4.10).
create table dogo.staff (
  user_id uuid primary key references auth.users (id) on delete cascade,
  nombre text not null,
  rol text not null default 'admin' check (rol in ('admin', 'ventas'))
);

create table dogo.productos (
  id text primary key check (id ~ '^[a-z0-9-]{2,30}$'),
  nombre text not null check (length(trim(nombre)) >= 2),
  pack text not null,
  precio numeric(8,2) not null check (precio > 0),
  costo numeric(8,2) not null check (costo >= 0),
  activo boolean not null default true,
  orden int not null default 0
);

-- Historial de cambios de precio y costo (quién y cuándo).
create table dogo.precio_cambios (
  id bigint generated always as identity primary key,
  producto_id text not null references dogo.productos (id),
  precio numeric(8,2) not null,
  costo numeric(8,2) not null,
  activo boolean not null,
  staff_id uuid references auth.users (id),
  creado timestamptz not null default now()
);

create table dogo.clientes (
  id bigint generated always as identity primary key,
  telefono text not null unique check (telefono ~ '^593[0-9]{9}$'),   -- normalizado 593XXXXXXXXX (§4.12)
  nombre text not null,
  sector text,
  creado timestamptz not null default now()
);

-- Pedidos e ítems: inmutables una vez creados (§4.9). El estado vive en pedido_estados (solo se agregan filas).
create table dogo.pedidos (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  cliente_id bigint not null references dogo.clientes (id),
  nombre text not null,
  sector text,
  entrega text not null check (entrega in ('domicilio', 'retiro')),
  canal text not null default 'directo',
  campana text,
  nota text,
  subtotal numeric(10,2) not null check (subtotal > 0),
  costo numeric(10,2) not null check (costo >= 0),
  envio numeric(8,2) not null check (envio >= 0),
  total numeric(10,2) not null,
  creado timestamptz not null default now()
);
create index pedidos_creado_idx on dogo.pedidos (creado);
create index pedidos_cliente_idx on dogo.pedidos (cliente_id, creado);

create table dogo.pedido_items (
  pedido_id bigint not null references dogo.pedidos (id),
  producto_id text not null references dogo.productos (id),
  cant int not null check (cant between 1 and 30),
  precio numeric(8,2) not null,     -- precio y costo del momento de la compra
  costo numeric(8,2) not null,
  primary key (pedido_id, producto_id)
);

create table dogo.pedido_estados (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references dogo.pedidos (id),
  estado text not null check (estado in ('nuevo', 'confirmado', 'entregado', 'anulado')),
  staff_id uuid references auth.users (id),
  creado timestamptz not null default now()
);
create index pedido_estados_idx on dogo.pedido_estados (pedido_id, id desc);

-- Embudo de la tienda: visitas, catálogo, carrito, WhatsApp. Se cuentan sesiones distintas por día.
create table dogo.eventos (
  id bigint generated always as identity primary key,
  ev text not null check (ev in ('visita', 'catalogo', 'carrito', 'whatsapp', 'guia', 'wa_info')),
  canal text not null,
  campana text,
  sesion text not null,
  creado timestamptz not null default now()
);
create index eventos_creado_idx on dogo.eventos (creado);
create index eventos_sesion_idx on dogo.eventos (sesion, creado);

create table dogo.inversion (
  canal text primary key,
  monto_mensual numeric(10,2) not null default 0 check (monto_mensual >= 0)
);

-- Inmutabilidad (§4.9): pedidos, ítems y el historial de estados no se editan ni se borran.
create function dogo._inmutable() returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'Registro inmutable: los pedidos se corrigen agregando un estado (anulado), no editando ni borrando.';
end $$;
create trigger pedidos_inmutable before update or delete on dogo.pedidos for each row execute function dogo._inmutable();
create trigger items_inmutable before update or delete on dogo.pedido_items for each row execute function dogo._inmutable();
create trigger estados_inmutable before update or delete on dogo.pedido_estados for each row execute function dogo._inmutable();
create trigger cambios_inmutable before update or delete on dogo.precio_cambios for each row execute function dogo._inmutable();

alter table dogo.config enable row level security;
alter table dogo.staff enable row level security;
alter table dogo.productos enable row level security;
alter table dogo.precio_cambios enable row level security;
alter table dogo.clientes enable row level security;
alter table dogo.pedidos enable row level security;
alter table dogo.pedido_items enable row level security;
alter table dogo.pedido_estados enable row level security;
alter table dogo.eventos enable row level security;
alter table dogo.inversion enable row level security;
revoke all on all tables in schema dogo from public, anon, authenticated;
revoke all on all sequences in schema dogo from public, anon, authenticated;

-- ===== 002_funciones_tienda.sql =====
-- Dogo · 002 funciones de la tienda (las llama el cliente final, rol anon). Todo se valida aquí, nunca en el navegador (§4.5).

create function dogo.tel(p text) returns text language plpgsql immutable set search_path = '' as $$
declare d text := regexp_replace(coalesce(p, ''), '\D', '', 'g');
begin
  if d ~ '^0[0-9]{9}$' then d := '593' || substr(d, 2);
  elsif d ~ '^[0-9]{9}$' then d := '593' || d; end if;
  if d !~ '^5939[0-9]{8}$' then return null; end if;    -- celular ecuatoriano
  return d;
end $$;

create function dogo.limpio(p text, maximo int) returns text language sql immutable set search_path = '' as $$
  select nullif(left(regexp_replace(trim(coalesce(p, '')), '\s+', ' ', 'g'), maximo), '') $$;

create function dogo.canal_ok(p text) returns text language sql immutable set search_path = '' as $$
  select case when lower(coalesce(p, '')) in ('instagram', 'tiktok', 'whatsapp', 'referido', 'google', 'facebook', 'directo')
              then lower(p) else 'directo' end $$;

create function dogo.nuevo_codigo() returns text language plpgsql volatile set search_path = '' as $$
declare c text; abc text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  loop
    c := 'D';
    for i in 1..5 loop c := c || substr(abc, 1 + floor(random() * length(abc))::int, 1); end loop;
    exit when not exists (select 1 from dogo.pedidos where codigo = c);
  end loop;
  return c;
end $$;

create function dogo.es_staff() returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from dogo.staff where user_id = auth.uid()) $$;

-- Catálogo público: sin costos.
create function dogo.catalogo() returns json language sql stable security definer set search_path = '' as $$
  select json_build_object(
    'productos', coalesce((select json_agg(json_build_object('id', id, 'nombre', nombre, 'pack', pack, 'precio', precio) order by orden, id)
                           from dogo.productos where activo), '[]'::json),
    'envio', (select json_build_object('domicilio', envio_domicilio, 'gratisDesde', gratis_desde) from dogo.config where id = 1)) $$;

-- Crea el pedido con precios de la base (los del navegador se ignoran) y devuelve el resumen para el mensaje de WhatsApp.
create function dogo.crear_pedido(p_nombre text, p_tel text, p_entrega text, p_sector text, p_nota text,
                                  p_items jsonb, p_canal text default null, p_campana text default null)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare
  cfg dogo.config; t text := dogo.tel(p_tel); nom text := dogo.limpio(p_nombre, 60);
  sec text := dogo.limpio(p_sector, 80); nota text := dogo.limpio(p_nota, 200);
  cli bigint; ped bigint; cod text; sub numeric := 0; cos numeric := 0; env numeric := 0;
  it jsonb; pr dogo.productos; n int; lineas json;
begin
  select * into cfg from dogo.config where id = 1;
  if nom is null or length(nom) < 2 then raise exception 'Escribe tu nombre.'; end if;
  if t is null then raise exception 'Revisa tu WhatsApp: 10 dígitos, empieza con 09.'; end if;
  if p_entrega not in ('domicilio', 'retiro') then raise exception 'Elige domicilio o retiro.'; end if;
  if p_entrega = 'domicilio' and (sec is null or length(sec) < 3) then raise exception 'Escribe tu sector para el envío.'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Tu pedido está vacío.'; end if;
  if jsonb_array_length(p_items) > 12 then raise exception 'Demasiados productos en un pedido.'; end if;

  -- límites de frecuencia (§4.4 y §4.8)
  if (select count(*) from dogo.pedidos p join dogo.clientes c on c.id = p.cliente_id
      where c.telefono = t and p.creado > now() - interval '1 hour') >= cfg.max_pedidos_tel_hora then
    raise exception 'Ya recibimos varios pedidos de este número. Escríbenos por WhatsApp y te ayudamos.';
  end if;
  if (select count(*) from dogo.pedidos where creado > now() - interval '1 hour') >= cfg.max_pedidos_hora then
    raise exception 'Estamos recibiendo muchos pedidos. Intenta en unos minutos o escríbenos por WhatsApp.';
  end if;

  -- validar ítems antes de escribir nada
  for it in select * from jsonb_array_elements(p_items) loop
    if jsonb_typeof(it->'cant') <> 'number' then raise exception 'Cantidad no válida.'; end if;
    n := (it->>'cant')::numeric;
    if n <> (it->>'cant')::numeric or n < 1 or n > 30 then raise exception 'Cantidad no válida.'; end if;
    select * into pr from dogo.productos where id = it->>'id' and activo;
    if not found then raise exception 'Un producto ya no está disponible. Recarga la página.'; end if;
    sub := sub + pr.precio * n; cos := cos + pr.costo * n;
  end loop;
  if (select count(distinct e->>'id') from jsonb_array_elements(p_items) e) <> jsonb_array_length(p_items) then
    raise exception 'Producto repetido en el pedido.';
  end if;
  env := case when p_entrega = 'domicilio' and sub < cfg.gratis_desde then cfg.envio_domicilio else 0 end;

  insert into dogo.clientes (telefono, nombre, sector) values (t, nom, sec)
    on conflict (telefono) do update set nombre = excluded.nombre, sector = coalesce(excluded.sector, dogo.clientes.sector)
    returning id into cli;
  cod := dogo.nuevo_codigo();
  insert into dogo.pedidos (codigo, cliente_id, nombre, sector, entrega, canal, campana, nota, subtotal, costo, envio, total)
    values (cod, cli, nom, case when p_entrega = 'domicilio' then sec end, p_entrega, dogo.canal_ok(p_canal),
            dogo.limpio(p_campana, 40), nota, sub, cos, env, sub + env)
    returning id into ped;
  insert into dogo.pedido_items (pedido_id, producto_id, cant, precio, costo)
    select ped, pr2.id, (e->>'cant')::int, pr2.precio, pr2.costo
    from jsonb_array_elements(p_items) e join dogo.productos pr2 on pr2.id = e->>'id';
  insert into dogo.pedido_estados (pedido_id, estado) values (ped, 'nuevo');

  select json_agg(json_build_object('id', i.producto_id, 'nombre', p.nombre, 'pack', p.pack, 'cant', i.cant, 'precio', i.precio) order by p.orden)
    into lineas from dogo.pedido_items i join dogo.productos p on p.id = i.producto_id where i.pedido_id = ped;
  return json_build_object('codigo', cod, 'subtotal', sub, 'envio', env, 'total', sub + env, 'items', lineas);
end $$;

-- Evento del embudo. Si una sesión o el total por hora pasan el tope, se ignora sin error.
create function dogo.evento(p_ev text, p_sesion text, p_canal text default null, p_campana text default null)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare cfg dogo.config;
begin
  if p_ev not in ('visita', 'catalogo', 'carrito', 'whatsapp', 'guia', 'wa_info') or coalesce(p_sesion, '') !~ '^[a-z0-9]{8,40}$' then return; end if;
  select * into cfg from dogo.config where id = 1;
  if (select count(*) from dogo.eventos where sesion = p_sesion and creado > now() - interval '1 hour') >= cfg.max_eventos_sesion_hora then return; end if;
  if (select count(*) from dogo.eventos where creado > now() - interval '1 hour') >= cfg.max_eventos_hora then return; end if;
  insert into dogo.eventos (ev, canal, campana, sesion) values (p_ev, dogo.canal_ok(p_canal), dogo.limpio(p_campana, 40), p_sesion);
end $$;

-- ===== 003_funciones_panel.sql =====
-- Dogo · 003 funciones del panel del dueño (solo authenticated). Cada una verifica es_staff() por dentro.

create function dogo.yo() returns json language sql stable security definer set search_path = '' as $$
  select json_build_object('nombre', nombre, 'rol', rol) from dogo.staff where user_id = auth.uid() $$;

-- Todo lo que el panel necesita desde una fecha (pedidos con ítems y estado actual, embudo por día y canal, inversión y productos con costo).
create function dogo.panel(p_desde date) returns json language plpgsql stable security definer set search_path = '' as $$
declare desde timestamptz := p_desde::timestamp at time zone 'America/Guayaquil'; r json;
begin
  if not dogo.es_staff() then raise exception 'No autorizado'; end if;
  select json_build_object(
    'pedidos', coalesce((
      select json_agg(json_build_object(
        'id', p.codigo, 'fecha', p.creado, 'entrega', p.entrega, 'canal', p.canal, 'campana', p.campana, 'nota', p.nota,
        'envio', p.envio, 'estado', (select e.estado from dogo.pedido_estados e where e.pedido_id = p.id order by e.id desc limit 1),
        'cliente', json_build_object('nombre', p.nombre, 'tel', c.telefono, 'sector', p.sector),
        'items', (select json_agg(json_build_object('id', i.producto_id, 'cant', i.cant, 'precio', i.precio, 'costo', i.costo))
                  from dogo.pedido_items i where i.pedido_id = p.id)
      ) order by p.creado desc)
      from dogo.pedidos p join dogo.clientes c on c.id = p.cliente_id where p.creado >= desde), '[]'::json),
    'eventos', coalesce((
      select json_agg(json_build_object('dia', dia, 'canal', canal, 'ev', ev, 'n', n))
      from (select to_char(creado at time zone 'America/Guayaquil', 'YYYY-MM-DD') dia, canal, ev, count(distinct sesion) n
            from dogo.eventos where creado >= desde group by 1, 2, 3) x), '[]'::json),
    'inversion', coalesce((select json_object_agg(canal, monto_mensual) from dogo.inversion), '{}'::json),
    'productos', coalesce((select json_agg(json_build_object('id', id, 'nombre', nombre, 'pack', pack, 'precio', precio, 'costo', costo, 'activo', activo) order by orden, id)
                           from dogo.productos), '[]'::json)
  ) into r;
  return r;
end $$;

create function dogo.pedido_estado(p_codigo text, p_estado text) returns json language plpgsql volatile security definer set search_path = '' as $$
declare ped bigint; actual text;
begin
  if not dogo.es_staff() then raise exception 'No autorizado'; end if;
  if p_estado not in ('nuevo', 'confirmado', 'entregado', 'anulado') then raise exception 'Estado no válido'; end if;
  select id into ped from dogo.pedidos where codigo = p_codigo;
  if ped is null then raise exception 'Pedido no encontrado'; end if;
  select estado into actual from dogo.pedido_estados where pedido_id = ped order by id desc limit 1;
  if actual is distinct from p_estado then
    insert into dogo.pedido_estados (pedido_id, estado, staff_id) values (ped, p_estado, auth.uid());
  end if;
  return json_build_object('codigo', p_codigo, 'estado', p_estado);
end $$;

create function dogo.producto_guardar(p_id text, p_precio numeric, p_costo numeric, p_activo boolean default true)
returns json language plpgsql volatile security definer set search_path = '' as $$
begin
  if not dogo.es_staff() then raise exception 'No autorizado'; end if;
  if p_precio is null or p_precio <= 0 or p_precio > 1000 then raise exception 'Precio no válido'; end if;
  if p_costo is null or p_costo < 0 or p_costo > 1000 then raise exception 'Costo no válido'; end if;
  update dogo.productos set precio = round(p_precio, 2), costo = round(p_costo, 2), activo = coalesce(p_activo, true) where id = p_id;
  if not found then raise exception 'Producto no encontrado'; end if;
  insert into dogo.precio_cambios (producto_id, precio, costo, activo, staff_id) values (p_id, round(p_precio, 2), round(p_costo, 2), coalesce(p_activo, true), auth.uid());
  return json_build_object('id', p_id, 'precio', round(p_precio, 2), 'costo', round(p_costo, 2), 'activo', coalesce(p_activo, true));
end $$;

create function dogo.inversion_guardar(p_canal text, p_monto numeric) returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if not dogo.es_staff() then raise exception 'No autorizado'; end if;
  if dogo.canal_ok(p_canal) <> lower(p_canal) then raise exception 'Canal no válido'; end if;
  if p_monto is null or p_monto < 0 or p_monto > 100000 then raise exception 'Monto no válido'; end if;
  insert into dogo.inversion (canal, monto_mensual) values (lower(p_canal), round(p_monto, 2))
    on conflict (canal) do update set monto_mensual = excluded.monto_mensual;
end $$;

create function dogo.envio_guardar(p_domicilio numeric, p_gratis_desde numeric) returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if not dogo.es_staff() then raise exception 'No autorizado'; end if;
  if p_domicilio is null or p_domicilio < 0 or p_domicilio > 50 or p_gratis_desde is null or p_gratis_desde < 0 or p_gratis_desde > 1000 then
    raise exception 'Valores no válidos';
  end if;
  update dogo.config set envio_domicilio = round(p_domicilio, 2), gratis_desde = round(p_gratis_desde, 2) where id = 1;
end $$;

-- ===== 004_permisos.sql =====
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

-- ===== 005_datos_base.sql =====
-- Dogo · 005 datos base: catálogo con precio y costo por pack, e inversión inicial por canal (se edita desde el panel).
insert into dogo.productos (id, nombre, pack, precio, costo, orden) values
  ('patitas',   'Patitas de pollo',         '10 unidades', 2.50, 1.10, 1),
  ('pulmon',    'Pulmón de res',            '100 g',       4.50, 1.75, 2),
  ('orejas',    'Orejas de res',            '5 unidades',  8.00, 4.00, 3),
  ('aros',      'Aros de tráquea',          '250 g',       6.90, 4.13, 4),
  ('traquea-m', 'Tráquea entera · mediana', '1 pieza',     3.50, 1.86, 5),
  ('traquea-g', 'Tráquea entera · grande',  '1 pieza',     5.50, 3.10, 6)
on conflict (id) do nothing;

insert into dogo.inversion (canal, monto_mensual) values
  ('instagram', 0), ('tiktok', 0), ('whatsapp', 0), ('referido', 0), ('google', 0), ('facebook', 0), ('directo', 0)
on conflict (canal) do nothing;

-- ===== 006_equipo_y_compras.sql =====
-- Dogo · 006 equipo e inventario/compras.
-- Reemplazo numerado y explícito de dogo.panel, dogo.producto_guardar, dogo.inversion_guardar y dogo.envio_guardar (003):
-- ahora distinguen al dueño (admin) del equipo (ventas). El equipo ve ventas, pedidos y compras, pero no costos ni márgenes,
-- y no cambia precios, envío ni inversión. Todo dentro del schema dogo (proyecto compartido: no toca a otros negocios).

-- ---------- productos: datos de compra ----------
alter table dogo.productos
  add column proveedor text,
  add column dias_entrega int not null default 2 check (dias_entrega between 0 and 30),     -- lo que tarda el proveedor
  add column cobertura_dias int not null default 7 check (cobertura_dias between 1 and 30),  -- cuántos días debe cubrir cada compra
  add column multiplo int not null default 1 check (multiplo between 1 and 500);           -- se compra en múltiplos de

-- ---------- inventario: libro de movimientos inmutable (§4.9) ----------
-- Stock = compras + ajustes − packs vendidos (pedidos no anulados) desde el primer movimiento del producto.
create table dogo.inventario_mov (
  id bigint generated always as identity primary key,
  producto_id text not null references dogo.productos (id),
  tipo text not null check (tipo in ('compra', 'ajuste')),
  cantidad int not null check (cantidad between -100000 and 100000 and (cantidad <> 0 or tipo = 'ajuste')),  -- un conteo sin diferencia queda registrado
  costo_unit numeric(8,2) check (costo_unit is null or costo_unit >= 0),
  nota text,
  staff_id uuid references auth.users (id),
  creado timestamptz not null default now()
);
create index inventario_mov_idx on dogo.inventario_mov (producto_id, creado);
create trigger inventario_inmutable before update or delete on dogo.inventario_mov for each row execute function dogo._inmutable();

-- ---------- equipo: invitaciones con código ----------
-- El dueño invita (correo + código). La persona crea su cuenta o entra con la que ya tiene y escribe el código.
create table dogo.invitaciones (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  correo text not null check (correo ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  nombre text not null,
  rol text not null check (rol in ('admin', 'ventas')),
  creado_por uuid references auth.users (id),
  creado timestamptz not null default now(),
  expira timestamptz not null default now() + interval '72 hours',
  usada_por uuid references auth.users (id),
  usada_en timestamptz,
  cancelada boolean not null default false
);
create table dogo.intentos (               -- intentos fallidos de código (§4.8)
  user_id uuid primary key,
  n int not null default 0,
  desde timestamptz not null default now(),
  bloqueado_hasta timestamptz
);

alter table dogo.inventario_mov enable row level security;
alter table dogo.invitaciones enable row level security;
alter table dogo.intentos enable row level security;
revoke all on dogo.inventario_mov, dogo.invitaciones, dogo.intentos from public, anon, authenticated;
revoke all on all sequences in schema dogo from public, anon, authenticated;

-- ---------- ayudas ----------
create function dogo.es_admin() returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from dogo.staff where user_id = auth.uid() and rol = 'admin') $$;

-- Packs vendidos de un producto desde una fecha (pedidos cuyo último estado no es 'anulado').
create function dogo.vendidos(p_id text, p_desde timestamptz) returns bigint language sql stable security definer set search_path = '' as $$
  select coalesce(sum(i.cant), 0) from dogo.pedido_items i join dogo.pedidos p on p.id = i.pedido_id
  where i.producto_id = p_id and p.creado >= p_desde
    and (select e.estado from dogo.pedido_estados e where e.pedido_id = p.id order by e.id desc limit 1) <> 'anulado' $$;

create function dogo.stock(p_id text) returns bigint language plpgsql stable security definer set search_path = '' as $$
declare inicio timestamptz := (select min(creado) from dogo.inventario_mov where producto_id = p_id);
begin
  if inicio is null then return null; end if;    -- sin inventario cargado todavía
  return (select coalesce(sum(cantidad), 0) from dogo.inventario_mov where producto_id = p_id) - dogo.vendidos(p_id, inicio);
end $$;

-- ---------- reemplazos de 003 ----------
create or replace function dogo.yo() returns json language sql stable security definer set search_path = '' as $$
  select json_build_object('nombre', s.nombre, 'rol', s.rol, 'correo', u.email)
  from dogo.staff s join auth.users u on u.id = s.user_id where s.user_id = auth.uid() $$;

create or replace function dogo.panel(p_desde date) returns json language plpgsql stable security definer set search_path = '' as $$
declare desde timestamptz := p_desde::timestamp at time zone 'America/Guayaquil'; adm boolean := dogo.es_admin(); r json;
begin
  if not dogo.es_staff() then raise exception 'No autorizado'; end if;
  select json_build_object(
    'rol', case when adm then 'admin' else 'ventas' end,
    'pedidos', coalesce((
      select json_agg(json_build_object(
        'id', p.codigo, 'fecha', p.creado, 'entrega', p.entrega, 'canal', p.canal, 'campana', p.campana, 'nota', p.nota,
        'envio', p.envio, 'estado', (select e.estado from dogo.pedido_estados e where e.pedido_id = p.id order by e.id desc limit 1),
        'cliente', json_build_object('nombre', p.nombre, 'tel', c.telefono, 'sector', p.sector),
        'items', (select json_agg(json_build_object('id', i.producto_id, 'cant', i.cant, 'precio', i.precio,
                                                     'costo', case when adm then i.costo end))
                  from dogo.pedido_items i where i.pedido_id = p.id)
      ) order by p.creado desc)
      from dogo.pedidos p join dogo.clientes c on c.id = p.cliente_id where p.creado >= desde), '[]'::json),
    'eventos', coalesce((
      select json_agg(json_build_object('dia', dia, 'canal', canal, 'ev', ev, 'n', n))
      from (select to_char(creado at time zone 'America/Guayaquil', 'YYYY-MM-DD') dia, canal, ev, count(distinct sesion) n
            from dogo.eventos where creado >= desde group by 1, 2, 3) x), '[]'::json),
    'inversion', case when adm then coalesce((select json_object_agg(canal, monto_mensual) from dogo.inversion), '{}'::json) else '{}'::json end,
    'productos', coalesce((select json_agg(json_build_object('id', id, 'nombre', nombre, 'pack', pack, 'precio', precio,
                                  'costo', case when adm then costo end, 'activo', activo) order by orden, id)
                           from dogo.productos), '[]'::json)
  ) into r;
  return r;
end $$;

create or replace function dogo.producto_guardar(p_id text, p_precio numeric, p_costo numeric, p_activo boolean default true)
returns json language plpgsql volatile security definer set search_path = '' as $$
begin
  if not dogo.es_admin() then raise exception 'Solo el dueño puede cambiar precios'; end if;
  if p_precio is null or p_precio <= 0 or p_precio > 1000 then raise exception 'Precio no válido'; end if;
  if p_costo is null or p_costo < 0 or p_costo > 1000 then raise exception 'Costo no válido'; end if;
  update dogo.productos set precio = round(p_precio, 2), costo = round(p_costo, 2), activo = coalesce(p_activo, true) where id = p_id;
  if not found then raise exception 'Producto no encontrado'; end if;
  insert into dogo.precio_cambios (producto_id, precio, costo, activo, staff_id) values (p_id, round(p_precio, 2), round(p_costo, 2), coalesce(p_activo, true), auth.uid());
  return json_build_object('id', p_id, 'precio', round(p_precio, 2), 'costo', round(p_costo, 2), 'activo', coalesce(p_activo, true));
end $$;

create or replace function dogo.inversion_guardar(p_canal text, p_monto numeric) returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if not dogo.es_admin() then raise exception 'Solo el dueño puede cambiar la inversión'; end if;
  if dogo.canal_ok(p_canal) <> lower(p_canal) then raise exception 'Canal no válido'; end if;
  if p_monto is null or p_monto < 0 or p_monto > 100000 then raise exception 'Monto no válido'; end if;
  insert into dogo.inversion (canal, monto_mensual) values (lower(p_canal), round(p_monto, 2))
    on conflict (canal) do update set monto_mensual = excluded.monto_mensual;
end $$;

create or replace function dogo.envio_guardar(p_domicilio numeric, p_gratis_desde numeric) returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if not dogo.es_admin() then raise exception 'Solo el dueño puede cambiar el envío'; end if;
  if p_domicilio is null or p_domicilio < 0 or p_domicilio > 50 or p_gratis_desde is null or p_gratis_desde < 0 or p_gratis_desde > 1000 then
    raise exception 'Valores no válidos';
  end if;
  update dogo.config set envio_domicilio = round(p_domicilio, 2), gratis_desde = round(p_gratis_desde, 2) where id = 1;
end $$;

-- ---------- inventario y compras ----------
create function dogo.inventario() returns json language plpgsql stable security definer set search_path = '' as $$
declare adm boolean := dogo.es_admin();
begin
  if not dogo.es_staff() then raise exception 'No autorizado'; end if;
  return coalesce((select json_agg(json_build_object(
      'id', p.id, 'stock', dogo.stock(p.id), 'proveedor', p.proveedor, 'dias_entrega', p.dias_entrega,
      'cobertura_dias', p.cobertura_dias, 'multiplo', p.multiplo,
      'ultima_compra', (select max(creado) from dogo.inventario_mov m where m.producto_id = p.id and m.tipo = 'compra'),
      'ultimo_conteo', (select max(creado) from dogo.inventario_mov m where m.producto_id = p.id and m.tipo = 'ajuste'),
      'costo_ultima_compra', case when adm then (select costo_unit from dogo.inventario_mov m where m.producto_id = p.id and m.tipo = 'compra'
                                                  and costo_unit is not null order by creado desc limit 1) end
    ) order by p.orden, p.id) from dogo.productos p where p.activo), '[]'::json);
end $$;

-- Compra recibida: suma stock. El costo solo lo registra el dueño (el equipo no ve costos).
create function dogo.compra_registrar(p_items jsonb, p_nota text default null) returns json language plpgsql volatile security definer set search_path = '' as $$
declare it jsonb; n int; adm boolean := dogo.es_admin(); total int := 0;
begin
  if not dogo.es_staff() then raise exception 'No autorizado'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 50 then
    raise exception 'Compra vacía';
  end if;
  for it in select * from jsonb_array_elements(p_items) loop
    if jsonb_typeof(it->'cant') <> 'number' then raise exception 'Cantidad no válida'; end if;
    n := (it->>'cant')::numeric;
    if n <> (it->>'cant')::numeric or n < 1 or n > 10000 then raise exception 'Cantidad no válida'; end if;
    if not exists (select 1 from dogo.productos where id = it->>'id') then raise exception 'Producto no encontrado'; end if;
    if adm and it ? 'costo' and jsonb_typeof(it->'costo') = 'number' and ((it->>'costo')::numeric < 0 or (it->>'costo')::numeric > 1000) then
      raise exception 'Costo no válido';
    end if;
  end loop;
  insert into dogo.inventario_mov (producto_id, tipo, cantidad, costo_unit, nota, staff_id)
    select e->>'id', 'compra', (e->>'cant')::int,
           case when adm and jsonb_typeof(e->'costo') = 'number' then round((e->>'costo')::numeric, 2) end,
           dogo.limpio(p_nota, 200), auth.uid()
    from jsonb_array_elements(p_items) e;
  select coalesce(sum((e->>'cant')::int), 0) into total from jsonb_array_elements(p_items) e;
  return json_build_object('productos', jsonb_array_length(p_items), 'packs', total);
end $$;

-- Conteo físico: guarda la diferencia como ajuste (el libro no se edita).
create function dogo.inventario_contar(p_id text, p_real int, p_nota text default null) returns json language plpgsql volatile security definer set search_path = '' as $$
declare actual bigint; dif bigint;
begin
  if not dogo.es_staff() then raise exception 'No autorizado'; end if;
  if p_real is null or p_real < 0 or p_real > 100000 then raise exception 'Cantidad no válida'; end if;
  if not exists (select 1 from dogo.productos where id = p_id) then raise exception 'Producto no encontrado'; end if;
  actual := coalesce(dogo.stock(p_id), 0);
  dif := p_real - actual;
  insert into dogo.inventario_mov (producto_id, tipo, cantidad, nota, staff_id)
    values (p_id, 'ajuste', dif, coalesce(dogo.limpio(p_nota, 200), 'Conteo físico'), auth.uid());
  return json_build_object('id', p_id, 'stock', p_real, 'diferencia', dif);
end $$;

create function dogo.producto_compra_config(p_id text, p_proveedor text, p_dias_entrega int, p_cobertura_dias int, p_multiplo int)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if not dogo.es_admin() then raise exception 'Solo el dueño cambia los datos de compra'; end if;
  update dogo.productos set proveedor = dogo.limpio(p_proveedor, 60), dias_entrega = p_dias_entrega,
    cobertura_dias = p_cobertura_dias, multiplo = p_multiplo where id = p_id;
  if not found then raise exception 'Producto no encontrado'; end if;
end $$;

-- ---------- equipo ----------
create function dogo.equipo_lista() returns json language plpgsql stable security definer set search_path = '' as $$
begin
  if not dogo.es_admin() then raise exception 'No autorizado'; end if;
  return json_build_object(
    'miembros', coalesce((select json_agg(json_build_object('user_id', s.user_id, 'nombre', s.nombre, 'rol', s.rol, 'correo', u.email,
                                                            'yo', s.user_id = auth.uid()) order by s.rol, s.nombre)
                          from dogo.staff s join auth.users u on u.id = s.user_id), '[]'::json),
    'invitaciones', coalesce((select json_agg(json_build_object('id', id, 'correo', correo, 'nombre', nombre, 'rol', rol,
                                                                'codigo', codigo, 'expira', expira) order by creado desc)
                              from dogo.invitaciones where usada_por is null and not cancelada and expira > now()), '[]'::json));
end $$;

create function dogo.invitacion_crear(p_correo text, p_nombre text, p_rol text default 'ventas') returns json language plpgsql volatile security definer set search_path = '' as $$
declare c text; abc text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; v_correo text := lower(trim(coalesce(p_correo, ''))); nom text := dogo.limpio(p_nombre, 60);
begin
  if not dogo.es_admin() then raise exception 'No autorizado'; end if;
  if v_correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Correo no válido'; end if;
  if nom is null or length(nom) < 2 then raise exception 'Escribe el nombre'; end if;
  if p_rol not in ('admin', 'ventas') then raise exception 'Rol no válido'; end if;
  if exists (select 1 from dogo.staff s join auth.users u on u.id = s.user_id where lower(u.email) = v_correo) then raise exception 'Esa persona ya es parte del equipo'; end if;
  if (select count(*) from dogo.invitaciones where creado > now() - interval '1 day') >= 20 then raise exception 'Demasiadas invitaciones hoy'; end if;
  update dogo.invitaciones i set cancelada = true where lower(i.correo) = v_correo and i.usada_por is null and not i.cancelada;
  loop
    c := ''; for i in 1..8 loop c := c || substr(abc, 1 + floor(random() * length(abc))::int, 1); end loop;
    exit when not exists (select 1 from dogo.invitaciones where codigo = c);
  end loop;
  insert into dogo.invitaciones (codigo, correo, nombre, rol, creado_por) values (c, v_correo, nom, p_rol, auth.uid());
  return json_build_object('codigo', c, 'correo', v_correo, 'expira', now() + interval '72 hours');
end $$;

create function dogo.invitacion_cancelar(p_id bigint) returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if not dogo.es_admin() then raise exception 'No autorizado'; end if;
  update dogo.invitaciones set cancelada = true where id = p_id and usada_por is null;
end $$;

-- La persona invitada (ya con sesión) activa su acceso. El correo de su cuenta debe ser el de la invitación. 5 fallos → 30 min de bloqueo.
create function dogo.invitacion_activar(p_codigo text) returns json language plpgsql volatile security definer set search_path = '' as $$
declare u uuid := auth.uid(); mail text; inv dogo.invitaciones; it dogo.intentos;
begin
  -- Los errores se devuelven (no se lanzan): un raise desharía el registro del intento fallido.
  if u is null then return json_build_object('ok', false, 'error', 'Inicia sesión primero'); end if;
  select * into it from dogo.intentos where user_id = u;
  if it.bloqueado_hasta is not null and it.bloqueado_hasta > now() then return json_build_object('ok', false, 'error', 'Demasiados intentos. Prueba en 30 minutos.'); end if;
  select lower(email) into mail from auth.users where id = u;
  select * into inv from dogo.invitaciones
    where codigo = upper(trim(coalesce(p_codigo, ''))) and usada_por is null and not cancelada and expira > now() and lower(correo) = mail;
  if not found then
    insert into dogo.intentos (user_id, n, desde) values (u, 1, now())
      on conflict (user_id) do update set
        n = case when dogo.intentos.desde < now() - interval '30 minutes' then 1 else dogo.intentos.n + 1 end,
        desde = case when dogo.intentos.desde < now() - interval '30 minutes' then now() else dogo.intentos.desde end,
        bloqueado_hasta = case when dogo.intentos.desde >= now() - interval '30 minutes' and dogo.intentos.n + 1 >= 5 then now() + interval '30 minutes' end;
    return json_build_object('ok', false, 'error', 'Código no válido para este correo, vencido o ya usado.');
  end if;
  insert into dogo.staff (user_id, nombre, rol) values (u, inv.nombre, inv.rol)
    on conflict (user_id) do update set nombre = excluded.nombre, rol = excluded.rol;
  update dogo.invitaciones set usada_por = u, usada_en = now() where id = inv.id;
  delete from dogo.intentos where user_id = u;
  return json_build_object('ok', true, 'nombre', inv.nombre, 'rol', inv.rol);
end $$;

create function dogo.equipo_rol(p_user uuid, p_rol text) returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if not dogo.es_admin() then raise exception 'No autorizado'; end if;
  if p_rol not in ('admin', 'ventas') then raise exception 'Rol no válido'; end if;
  if p_user = auth.uid() and p_rol <> 'admin' then raise exception 'No puedes quitarte el rol de dueño a ti mismo'; end if;
  update dogo.staff set rol = p_rol where user_id = p_user;
end $$;

create function dogo.equipo_quitar(p_user uuid) returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if not dogo.es_admin() then raise exception 'No autorizado'; end if;
  if p_user = auth.uid() then raise exception 'No puedes quitarte a ti mismo'; end if;
  delete from dogo.staff where user_id = p_user;
end $$;

-- ---------- permisos (§4.3) ----------
revoke all on all functions in schema dogo from public, anon, authenticated;
grant execute on function
  dogo.catalogo(),
  dogo.crear_pedido(text, text, text, text, text, jsonb, text, text),
  dogo.evento(text, text, text, text)
to anon, authenticated;
grant execute on function
  dogo.yo(), dogo.panel(date), dogo.pedido_estado(text, text), dogo.producto_guardar(text, numeric, numeric, boolean),
  dogo.inversion_guardar(text, numeric), dogo.envio_guardar(numeric, numeric),
  dogo.inventario(), dogo.compra_registrar(jsonb, text), dogo.inventario_contar(text, int, text),
  dogo.producto_compra_config(text, text, int, int, int),
  dogo.equipo_lista(), dogo.invitacion_crear(text, text, text), dogo.invitacion_cancelar(bigint),
  dogo.invitacion_activar(text), dogo.equipo_rol(uuid, text), dogo.equipo_quitar(uuid)
to authenticated;
-- Ayudas internas (tel, limpio, canal_ok, nuevo_codigo, es_staff, es_admin, vendidos, stock, _inmutable): sin permiso para nadie.
