'use strict';

// Un color por backend (backend1..backend7).
const COLORES = ['#2563eb', '#16a34a', '#ea580c', '#9333ea', '#db2777', '#0891b2', '#ca8a04'];
const POLL_MS = 2000;
const LOG_MAX = 15;

const $ = (id) => document.getElementById(id);
// Peticiones sugeridas por escenario: las mismas de las pruebas del proyecto
// (21 -> 7 c/u, 35 -> 7 c/u, 70 -> 10 c/u).
const PETICIONES = { 3: 21, 5: 35, 7: 70 };
const st = {
  backendCount: 3,
  conteo: {},          // { backend1: n, ... }
  ok: 0, fail: 0, latSuma: 0,
  ocupado: false,
  continuo: false,
  tarjetas: {},        // i -> { el, campos, info }
};

// ---------- Configuración del escenario (inyectada por nginx) ----------
async function cargarConfig() {
  try {
    const r = await fetch('/panel-config.json', { cache: 'no-store' });
    const c = await r.json();
    if ([3, 5, 7].includes(c.backendCount)) st.backendCount = c.backendCount;
    $('cfg-metodo').textContent = c.metodo || '?';
  } catch {
    $('cfg-metodo').textContent = '?';
  }
}

// ---------- Escenario: 3, 5 o 7 backends ----------
// Cada escenario tiene su propio balanceador (balanceador3/5/7), así que
// cambiar de escenario es inmediato y no reinicia ningún contenedor.
function cambiarEscenario(n) {
  if (st.ocupado) return;
  st.continuo = false;
  const bc = $('btn-continuo');
  bc.classList.remove('active');
  bc.textContent = 'Modo continuo';

  st.backendCount = n;
  document.querySelectorAll('.escenario button').forEach((b) => {
    b.classList.toggle('sel', Number(b.dataset.n) === n);
  });
  $('lb-nombre').textContent = `balanceador${n}`;
  $('cantidad').value = String(PETICIONES[n]);

  // Tarjetas: exactamente n.
  $('tarjetas').textContent = '';
  st.tarjetas = {};
  for (let i = 1; i <= n; i++) crearTarjeta(i);

  // Conteos y barras desde cero.
  $('barras').textContent = '';
  reiniciarConteo();
  consultarBalanceador();
}

// ---------- Peticiones a través del balanceador ----------
function urlPeticion() {
  const ruta = $('ruta').value;
  const delay = $('delay').value.trim();
  const q = ruta === '/work' && delay !== '' ? `?delay_ms=${encodeURIComponent(delay)}` : '';
  return `/lb/${st.backendCount}${ruta}${q}`;
}

async function unaPeticion(url) {
  const t0 = performance.now();
  try {
    const r = await fetch(url, { cache: 'no-store' });
    const cuerpo = (await r.text()).trim();
    const ms = performance.now() - t0;
    // Igual que pruebas/procesador.js: primero la cabecera, si no el cuerpo.
    const id = r.headers.get('X-Backend-ID');
    const nombre = id ? `backend${id}` : (cuerpo.match(/^backend\d+$/) || [null])[0];
    if (!r.ok || !nombre) throw new Error(`HTTP ${r.status}`);
    st.ok++; st.latSuma += ms;
    st.conteo[nombre] = (st.conteo[nombre] || 0) + 1;
    registrar(nombre, ms, false);
  } catch (e) {
    st.fail++;
    registrar(e.message || 'error de red', performance.now() - t0, true);
  }
  pintarResumen();
}

async function lote(n, simultaneas) {
  const url = urlPeticion();
  let enviadas = 0;
  const trabajador = async () => {
    while (enviadas < n) { enviadas++; await unaPeticion(url); }
  };
  const t0 = performance.now();
  await Promise.all(Array.from({ length: Math.min(simultaneas, n) }, trabajador));
  $('s-tiempo').textContent = `${n} en ${((performance.now() - t0) / 1000).toFixed(2)} s`;
}

async function continuo() {
  while (st.continuo) {
    await unaPeticion(urlPeticion());
    await new Promise((res) => setTimeout(res, 300));
  }
}

// ---------- Pintado ----------
function registrar(texto, ms, error) {
  const li = document.createElement('li');
  const a = document.createElement('span');
  const b = document.createElement('span');
  a.textContent = texto;
  if (error) a.className = 'err';
  b.className = 'ms';
  b.textContent = `${Math.round(ms)} ms`;
  li.append(a, b);
  const log = $('log');
  log.prepend(li);
  while (log.children.length > LOG_MAX) log.lastChild.remove();
}

function pintarResumen() {
  $('s-ok').textContent = String(st.ok);
  $('s-fail').textContent = String(st.fail);
  $('s-lat').textContent = st.ok ? `${Math.round(st.latSuma / st.ok)} ms` : '–';
  pintarBarras();
}

function pintarBarras() {
  const cont = $('barras');
  const total = Object.values(st.conteo).reduce((a, b) => a + b, 0);
  // Siempre los del escenario; y cualquier otro que haya respondido.
  const nombres = new Set();
  for (let i = 1; i <= st.backendCount; i++) nombres.add(`backend${i}`);
  Object.keys(st.conteo).forEach((n) => nombres.add(n));
  const orden = [...nombres].sort((x, y) => parseInt(x.slice(7)) - parseInt(y.slice(7)));

  orden.forEach((nombre) => {
    let fila = cont.querySelector(`[data-n="${nombre}"]`);
    if (!fila) {
      fila = document.createElement('div');
      fila.className = 'bar';
      fila.dataset.n = nombre;
      const etiqueta = document.createElement('span');
      etiqueta.className = 'name';
      etiqueta.textContent = nombre;
      const pista = document.createElement('div');
      pista.className = 'track';
      const relleno = document.createElement('div');
      relleno.className = 'fill';
      relleno.style.background = COLORES[(parseInt(nombre.slice(7)) - 1) % COLORES.length];
      pista.append(relleno);
      const num = document.createElement('span');
      num.className = 'num';
      fila.append(etiqueta, pista, num);
      cont.append(fila);
    }
    const n = st.conteo[nombre] || 0;
    const pct = total ? (n * 100) / total : 0;
    fila.querySelector('.fill').style.width = `${pct}%`;
    const num = fila.querySelector('.num');
    num.textContent = '';
    const fuerte = document.createElement('strong');
    fuerte.textContent = String(n);
    num.append(fuerte, ` · ${pct.toFixed(0)} %`);
  });
}

// ---------- Tarjetas: consulta directa a cada backend ----------
const CAMPOS = [
  ['hostname', 'Contenedor'], ['ip', 'IP'], ['uptime', 'Activo hace'],
  ['app', 'Peticiones app'], ['activas', 'Activas ahora'], ['pico', 'Pico activas'],
  ['work', '/work medio'], ['cfg', 'delay / cpu'],
];

function crearTarjeta(i) {
  const el = document.createElement('article');
  el.className = 'card down';
  el.style.setProperty('--c', COLORES[i - 1]);
  const cab = document.createElement('header');
  const h = document.createElement('h4');
  h.textContent = `backend${i}`;
  const estado = document.createElement('span');
  estado.className = 'estado';
  const punto = document.createElement('span');
  punto.className = 'dot';
  const txt = document.createElement('span');
  txt.textContent = 'consultando…';
  estado.append(punto, txt);
  cab.append(h, estado);
  const dl = document.createElement('dl');
  const campos = {};
  CAMPOS.forEach(([clave, etiqueta]) => {
    const dt = document.createElement('dt');
    dt.textContent = etiqueta;
    const dd = document.createElement('dd');
    dd.textContent = '–';
    dl.append(dt, dd);
    campos[clave] = dd;
  });
  el.append(cab, dl);
  $('tarjetas').append(el);
  st.tarjetas[i] = { el, campos, punto, txt, info: null };
}

function duracion(s) {
  s = Math.floor(s);
  if (s < 60) return `${s} s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m} min ${s % 60} s`;
  return `${Math.floor(m / 60)} h ${m % 60} min`;
}

async function pedirJSON(url) {
  const r = await fetch(url, { cache: 'no-store' });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json();
}

async function consultarBackend(i) {
  const t = st.tarjetas[i];
  const base = `/directo/${i}`;
  try {
    const h = await fetch(`${base}/health`, { cache: 'no-store' });
    if (h.status !== 200) throw new Error(`health ${h.status}`);
    const [info, m] = await Promise.all([pedirJSON(`${base}/info`), pedirJSON(`${base}/metrics`)]);
    t.el.classList.remove('down');
    t.punto.className = 'dot ok';
    t.txt.textContent = 'sano';
    t.campos.hostname.textContent = info.hostname;
    t.campos.ip.textContent = info.ip;
    t.campos.uptime.textContent = duracion(m.uptime_s);
    t.campos.app.textContent = String(m.app_requests);
    t.campos.activas.textContent = String(m.active);
    t.campos.pico.textContent = String(m.peak_active);
    t.campos.work.textContent = m.work.count ? `${Math.round(m.work.avg_ms)} ms` : '–';
    t.campos.cfg.textContent = `${info.work_config.delay_ms} / ${info.work_config.cpu_ms} ms`;
  } catch {
    t.el.classList.add('down');
    t.punto.className = 'dot bad';
    t.txt.textContent = 'sin respuesta';
    t.campos.activas.textContent = '–';
  }
}

async function consultarBalanceador() {
  const chip = $('chip-lb');
  const n = st.backendCount;
  try {
    const r = await fetch(`/lb/${n}/health`, { cache: 'no-store' });
    chip.querySelector('.dot').className = r.ok ? 'dot ok' : 'dot bad';
    $('lb-text').textContent = r.ok ? `balanceador${n}: en línea` : `balanceador${n}: HTTP ${r.status}`;
  } catch {
    chip.querySelector('.dot').className = 'dot bad';
    $('lb-text').textContent = `balanceador${n}: sin respuesta`;
  }
}

async function ciclo() {
  await Promise.all([
    consultarBalanceador(),
    ...Object.keys(st.tarjetas).map((i) => consultarBackend(Number(i))),
  ]);
  setTimeout(ciclo, POLL_MS);
}

// ---------- Eventos ----------
function bloquear(si) {
  st.ocupado = si;
  $('btn-enviar').disabled = si;
  $('btn-enviar').textContent = si ? 'Enviando…' : 'Enviar';
}

$('form').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  if (st.ocupado) return;
  const n = Math.max(1, Math.min(1000, parseInt($('cantidad').value, 10) || 1));
  const c = parseInt($('concurrencia').value, 10) || 1;
  bloquear(true);
  try { await lote(n, c); } finally { bloquear(false); }
});

$('btn-continuo').addEventListener('click', () => {
  st.continuo = !st.continuo;
  const b = $('btn-continuo');
  b.classList.toggle('active', st.continuo);
  b.textContent = st.continuo ? 'Detener continuo' : 'Modo continuo';
  if (st.continuo) continuo();
});

function reiniciarConteo() {
  st.conteo = {}; st.ok = 0; st.fail = 0; st.latSuma = 0;
  $('log').textContent = '';
  $('s-tiempo').textContent = '–';
  pintarResumen();
}

$('btn-reset').addEventListener('click', reiniciarConteo);

document.querySelectorAll('.escenario button').forEach((b) => {
  b.addEventListener('click', () => cambiarEscenario(Number(b.dataset.n)));
});

// ---------- Inicio ----------
(async () => {
  await cargarConfig();
  cambiarEscenario(st.backendCount);
  ciclo();
})();
