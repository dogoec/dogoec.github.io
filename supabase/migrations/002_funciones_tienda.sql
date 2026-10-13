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
