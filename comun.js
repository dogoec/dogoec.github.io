/* Compartido entre la tienda y el panel.
   DEMO: los pedidos y eventos se guardan en el navegador (localStorage).
   Producción: se reemplaza por funciones SQL en Supabase (ver README.md). */
(() => {
  const T = window.TIENDA;
  const LS = {
    get(k, d) { try { const v = JSON.parse(localStorage.getItem(k)); return v == null ? d : v; } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} }
  };
  const CANALES = { instagram: 'Instagram', tiktok: 'TikTok', whatsapp: 'WhatsApp directo', referido: 'Referido', google: 'Google', directo: 'Directo' };

  // Precios editados en el panel tienen prioridad sobre config.js
  function productos() {
    const o = LS.get('dogo_precios', {});
    return T.productos.map(p => Object.assign({}, p, o[p.id] || {}));
  }
  function canal() {
    let c = null;
    try {
      const q = new URLSearchParams(location.search);
      c = (q.get('utm_source') || q.get('ref') || '').toLowerCase() || null;
      if (c) sessionStorage.setItem('dogo_canal', c); else c = sessionStorage.getItem('dogo_canal');
    } catch (e) {}
    return CANALES[c] ? c : 'directo';
  }
  function track(ev, extra) {
    const t = LS.get('dogo_eventos', []);
    t.push(Object.assign({ ev, t: Date.now(), canal: canal() }, extra || {}));
    LS.set('dogo_eventos', t.slice(-5000));
  }
  const usd = n => '$' + (Math.round(n * 100) / 100).toFixed(2).replace('.', ',');
  const tel = s => { let d = String(s || '').replace(/\D/g, ''); if (d.startsWith('0')) d = '593' + d.slice(1); if (d.length === 9) d = '593' + d; return d; };
  window.SP = { T, LS, CANALES, productos, canal, track, usd, tel };
})();
