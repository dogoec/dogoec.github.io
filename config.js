/* Datos del negocio · lo único que se cambia por cliente.
   Los números de WhatsApp viven solo aquí. [CONFIRMAR] = dato pendiente con el cliente. */
window.TIENDA = {
  nombre: 'Dogo',
  lema: 'Snacks de un solo ingrediente para perros',
  ciudad: 'Quito',                   // [CONFIRMAR]
  wa: '593998000495',                // WhatsApp de Dogo: aquí llegan todos los pedidos
  horario: 'Lun a sáb · 9:00 a 19:00', // [CONFIRMAR]
  envio: { domicilio: 2.00, gratisDesde: 20 }, // [CONFIRMAR] costo de envío y monto de envío gratis
  // Precio y costo por pack (tabla de precios del dueño). El panel puede editarlos.
  productos: [
    { id: 'patitas', foto: 'assets/prod-patitas.jpg', ingrediente: '100 % pata de pollo', textura: 'Crocante', mastica: 1,
        nombre: 'Patitas de pollo',        pack: '10 unidades', precio: 2.50, costo: 1.10, icono: 'pata',
      desc: 'Crujientes y fáciles de dar. El premio del día a día.', tag: 'El más pedido',
      bench: 'Con Patitas (Quito): 12 u a $3,75–5,00', conf: 'alta', confNota: 'Ecuador, en USD' },
    { id: 'pulmon', foto: 'assets/prod-pulmon.jpg', ingrediente: '100 % pulmón de res', textura: 'Liviana y porosa', mastica: 1,
         nombre: 'Pulmón de res',           pack: '100 g',       precio: 4.50, costo: 1.75, icono: 'hoja',
      desc: 'Liviano y suave. Se parte en trocitos para entrenar.', tag: 'Para entrenar',
      bench: 'Dogelthy (México): 100 g a ~$11,84', conf: 'media', confNota: 'Regional, no Ecuador' },
    { id: 'orejas', foto: 'assets/prod-orejas.jpg', ingrediente: '100 % oreja de res', textura: 'Firme', mastica: 3,
         nombre: 'Orejas de res',           pack: '5 unidades',  precio: 8.00, costo: 4.00, icono: 'oreja',
      desc: 'Masticación larga para que se entretenga un buen rato.', tag: '',
      bench: 'Éxito (Colombia): 2 u a ~$1,60/u', conf: 'media', confNota: 'Regional, no Ecuador' },
    { id: 'aros', foto: 'assets/prod-aros.jpg', ingrediente: '100 % tráquea de res', textura: 'Crocante', mastica: 2,
           nombre: 'Aros de tráquea',         pack: '250 g',       precio: 6.90, costo: 4.13, icono: 'aro',
      desc: 'Aros crocantes de tráquea deshidratada.', tag: '',
      bench: 'Sin competidor identificado (margen interno)', conf: 'baja', confNota: 'Dato de mercado ausente' },
    { id: 'traquea-m', foto: 'assets/prod-traquea.jpg', ingrediente: '100 % tráquea de res', textura: 'Crocante', mastica: 2,
      nombre: 'Tráquea entera · mediana', pack: '1 pieza',    precio: 3.50, costo: 1.86, icono: 'tubo',
      desc: 'Pieza entera para perros pequeños y medianos.', tag: '',
      bench: 'Éxito (Colombia): pieza individual', conf: 'riesgo', confNota: 'Costo varía por tamaño' },
    { id: 'traquea-g', foto: 'assets/prod-traquea.jpg', ingrediente: '100 % tráquea de res', textura: 'Crocante', mastica: 3,
      nombre: 'Tráquea entera · grande',  pack: '1 pieza',    precio: 5.50, costo: 3.10, icono: 'tubo',
      desc: 'Pieza grande para perros de raza grande.', tag: '',
      bench: 'Éxito (Colombia): pieza individual', conf: 'riesgo', confNota: 'Costo varía por tamaño' }
  ],
  // Guía rápida por tamaño de perro (ids de productos)
  guia: {
    pequeno: { foto: 'assets/perro-1.jpg', alt: 'Cachorro golden mordiendo una patita de pollo en el piso de madera', titulo: 'Cachorros y perros pequeños', txt: 'Perro pequeño (hasta 10 kg)', ids: ['patitas', 'pulmon', 'traquea-m'] },
    mediano: { foto: 'assets/perro-2.jpg', alt: 'Perro mestizo atigrado sentado en el páramo esperando un premio', titulo: 'Medianos y de paseo largo', txt: 'Perro mediano (10 a 25 kg)',  ids: ['patitas', 'aros', 'traquea-m'] },
    grande:  { foto: 'assets/perro-3.jpg', alt: 'Labrador chocolate sentado sobre una manta verde', titulo: 'Grandes y de mordida fuerte', txt: 'Perro grande (más de 25 kg)', ids: ['orejas', 'aros', 'traquea-g'] }
  }
};
