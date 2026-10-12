# Dogo · snacks de un solo ingrediente para perros

Sitio estático (HTML/CSS/JS, sin build) publicado con GitHub Pages. Deploy = push a `main`.

- `index.html` · tienda: catálogo, combos por tamaño de perro y pedido que termina en WhatsApp.
- `panel.html` · panel del dueño (ventas, precios y márgenes, marketing, clientes). No se indexa.
- `config.js` · **único lugar** con nombre, WhatsApp, horario, envío, precios y costos.
- `assets/` · fotos (JPG optimizados, < 200 KB cada una). Para cambiar una foto, reemplaza el archivo con el mismo nombre.

## Importante
Hoy los pedidos se guardan en el navegador de quien compra. El panel muestra datos de ejemplo y los pedidos hechos desde ese mismo navegador; **no recibe todavía los pedidos de los clientes reales** (los recibes por WhatsApp). Para que el panel reciba cada pedido hay que conectarlo a Supabase (plan Pro).
