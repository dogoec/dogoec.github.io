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
