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
