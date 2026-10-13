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
