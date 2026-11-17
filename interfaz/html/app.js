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
  // 'principal' = el balanceador del proyecto (:8080), el MISMO que usan
  // Artillery, verificar.ps1 y los demás scripts. 3/5/7 = balanceadores de
  // demostración (solo si se levantó interfaz/compose.interfaz.yml).
  modo: 'principal',
  principalCount: 3,   // BACKEND_COUNT del .env
  demo: false,
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
    if ([3, 5, 7].includes(c.backendCount)) st.principalCount = c.backendCount;
    st.demo = c.demo === 1 || c.demo === true;
    $('cfg-metodo').textContent = c.metodo || '?';
  } catch {
    $('cfg-metodo').textContent = '?';
  }
  // Sin los balanceadores de demostración, solo se ofrece el principal.
  document.querySelectorAll('.escenario button.demo').forEach((b) => { b.hidden = !st.demo; });
}

// Ruta base del balanceador elegido (nginx la reenvía dentro de la red de Docker).
function base() {
  return st.modo === 'principal' ? '/api' : `/lb/${st.backendCount}`;
}
function nombreLb() {
  return st.modo === 'principal' ? 'balanceador principal (:8080)' : `balanceador${st.backendCount} (demo)`;
}

// ---------- Balanceador: principal o demostración 3/5/7 ----------
// Los de demostración tienen exactamente 3, 5 o 7 miembros, así que cambiar
// entre ellos es inmediato y no reinicia ningún contenedor.
function cambiarEscenario(modo) {
  if (st.ocupado) return;
  st.continuo = false;
  const bc = $('btn-continuo');
  bc.classList.remove('active');
  bc.textContent = 'Modo continuo';

  st.modo = modo;
  const n = modo === 'principal' ? st.principalCount : Number(modo);
  st.backendCount = n;
  document.querySelectorAll('.escenario button').forEach((b) => {
    b.classList.toggle('sel', b.dataset.n === String(modo));
  });
  $('lb-nombre').textContent = nombreLb();
  $('cfg-count').textContent = String(n);
  $('cantidad').value = String(PETICIONES[n] || n * 7);

  // Tarjetas: exactamente n.
  $('tarjetas').textContent = '';
  st.tarjetas = {};
  for (let i = 1; i <= n; i++) crearTarjeta(i);

  // Conteos y barras desde cero.
  $('barras').textContent = '';
  reiniciarConteo();
  consultarBalanceador();

  // Resultados: mostrar el mismo número de backends.
  $('r-backends').value = String(n);
  if (RES.filas.length) pintarResultados();
}

// ---------- Peticiones a través del balanceador ----------
function urlPeticion() {
  const ruta = $('ruta').value;
  const delay = $('delay').value.trim();
  const q = ruta === '/work' && delay !== '' ? `?delay_ms=${encodeURIComponent(delay)}` : '';
  return `${base()}${ruta}${q}`;
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
  $('m-fallos').textContent = String(st.fail);
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
  const nombre = nombreLb();
  try {
    const r = await fetch(`${base()}/health`, { cache: 'no-store' });
    chip.querySelector('.dot').className = r.ok ? 'dot ok' : 'dot bad';
    $('lb-text').textContent = r.ok ? `${nombre}: en línea` : `${nombre}: HTTP ${r.status}`;
  } catch {
    chip.querySelector('.dot').className = 'dot bad';
    $('lb-text').textContent = `${nombre}: sin respuesta`;
  }
}

// ---------- Métricas en vivo del balanceador: /server-status?auto ----------
// Formato "Clave: valor" por línea. Peticiones/s "ahora" = diferencia de
// "Total Accesses" entre dos consultas / tiempo transcurrido.
const previo = { n: '', total: 0, t: 0 };

async function consultarEstadoLb() {
  const n = base();   // identifica al balanceador consultado
  $('st-fuente').textContent = `/server-status?auto del ${nombreLb()}`;
  try {
    const r = await fetch(`${n}/server-status?auto`, { cache: 'no-store' });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const m = {};
    (await r.text()).split('\n').forEach((l) => {
      const i = l.indexOf(':');
      if (i > 0) m[l.slice(0, i).trim()] = l.slice(i + 1).trim();
    });
    const total = Number(m['Total Accesses'] || 0);
    const ahora = performance.now();
    if (previo.n === n && previo.t && total >= previo.total) {
      const rps = (total - previo.total) / ((ahora - previo.t) / 1000);
      $('m-rps').textContent = rps.toFixed(1);
    } else {
      $('m-rps').textContent = '…';
    }
    Object.assign(previo, { n, total, t: ahora });
    $('m-total').textContent = String(total);
    $('m-dur').textContent = m.DurationPerReq ? `${Number(m.DurationPerReq).toFixed(1)} ms` : '–';
    $('m-kb').textContent = m['Total kBytes'] ? `${m['Total kBytes']} kB` : '–';
    $('m-workers').textContent = `${m.BusyWorkers ?? '–'} / ${m.IdleWorkers ?? '–'}`;
    $('m-uptime').textContent = m.Uptime ? duracion(Number(m.Uptime)) : '–';
  } catch (e) {
    ['m-total', 'm-rps', 'm-dur', 'm-kb', 'm-workers', 'm-uptime'].forEach((id) => { $(id).textContent = '–'; });
    $('st-fuente').textContent = `/server-status?auto del ${nombreLb()} (sin respuesta: ${e.message})`;
  }
}

// ---------- Resultados de las pruebas (solo lectura) ----------
const RES = { filas: [] };
const SERIES = [['byrequests', '#2563eb'], ['bybusyness', '#ea580c']];

function leerCSV(texto) {
  const lineas = texto.replace(/^﻿/, '').split(/\r?\n/).filter((l) => l.trim());
  const cab = lineas.shift().split(',').map((c) => c.trim());
  return lineas.map((l) => {
    const v = l.split(',');
    const o = {};
    cab.forEach((c, i) => { o[c] = (v[i] || '').trim(); });
    return o;
  });
}

function svg(tag, attrs, texto) {
  const el = document.createElementNS('http://www.w3.org/2000/svg', tag);
  Object.entries(attrs).forEach(([k, v]) => el.setAttribute(k, String(v)));
  if (texto !== undefined) el.textContent = texto;
  return el;
}

function pintarGrafica() {
  const nb = $('r-backends').value;
  const met = $('r-metrica').value;
  const etiqueta = $('r-metrica').selectedOptions[0].textContent;
  const filas = RES.filas.filter((f) => f.backends === nb);
  const cont = $('r-grafica');
  cont.textContent = '';
  if (!filas.length) { cont.textContent = 'Sin datos para este escenario.'; return; }

  const usuarios = [...new Set(filas.map((f) => Number(f.usuarios)))].sort((a, b) => a - b);
  const valor = (alg, u) => {
    const f = filas.find((x) => x.algoritmo === alg && Number(x.usuarios) === u);
    return f ? Number(f[met]) : null;
  };
  const max = Math.max(1, ...filas.map((f) => Number(f[met]) || 0)) * 1.15;

  const ley = document.createElement('div');
  ley.className = 'leyenda';
  SERIES.forEach(([alg, color]) => {
    const s = document.createElement('span');
    s.style.setProperty('--c', color);
    s.textContent = alg;
    ley.append(s);
  });
  const t = document.createElement('span');
  t.textContent = `${etiqueta} · ${nb} backends`;
  ley.append(t);
  cont.append(ley);

  const W = 640, H = 260, M = { l: 50, r: 10, t: 10, b: 40 };
  const g = svg('svg', { viewBox: `0 0 ${W} ${H}`, role: 'img', 'aria-label': `${etiqueta} por usuarios` });
  const ancho = (W - M.l - M.r) / usuarios.length;
  const y = (v) => M.t + (H - M.t - M.b) * (1 - v / max);
  for (let k = 0; k <= 4; k++) {
    const v = (max / 4) * k;
    g.append(svg('line', { x1: M.l, x2: W - M.r, y1: y(v), y2: y(v), class: 'eje' }));
    g.append(svg('text', { x: M.l - 6, y: y(v) + 4, 'text-anchor': 'end' }, v.toFixed(v < 10 ? 1 : 0)));
  }
  usuarios.forEach((u, i) => {
    const x0 = M.l + i * ancho;
    const bw = ancho * 0.32;
    SERIES.forEach(([alg, color], j) => {
      const v = valor(alg, u);
      if (v === null || Number.isNaN(v)) return;
      const x = x0 + ancho * 0.16 + j * (bw + 4);
      g.append(svg('rect', { x, y: y(v), width: bw, height: Math.max(0, H - M.b - y(v)), fill: color, rx: 2 }));
      g.append(svg('text', { x: x + bw / 2, y: y(v) - 4, 'text-anchor': 'middle', class: 'valor' }, String(v)));
    });
    g.append(svg('text', { x: x0 + ancho / 2, y: H - M.b + 18, 'text-anchor': 'middle' }, `${u} usuarios`));
  });
  cont.append(g);
}

function pintarTabla(tabla, columnas, filas, claseFila) {
  tabla.textContent = '';
  const tr = document.createElement('tr');
  columnas.forEach(([, titulo]) => {
    const th = document.createElement('th');
    th.textContent = titulo;
    tr.append(th);
  });
  tabla.append(tr);
  filas.forEach((f) => {
    const fila = document.createElement('tr');
    if (claseFila) fila.className = claseFila(f);
    columnas.forEach(([clave]) => {
      const td = document.createElement('td');
      td.textContent = f[clave] === undefined || f[clave] === '' ? '–' : String(f[clave]);
      fila.append(td);
    });
    tabla.append(fila);
  });
}

function pintarResultados() {
  pintarGrafica();
  const nb = $('r-backends').value;
  const filas = RES.filas.filter((f) => f.backends === nb)
    .sort((a, b) => a.algoritmo.localeCompare(b.algoritmo) || a.usuarios - b.usuarios);
  pintarTabla($('r-tabla'), [
    ['algoritmo', 'Algoritmo'], ['usuarios', 'Usuarios'], ['peticiones', 'Peticiones'],
    ['errores', 'Errores'], ['rps', 'Pet./s'], ['lat_media', 'Media ms'], ['p95', 'p95 ms'],
    ['p99', 'p99 ms'], ['desv_reparto_pct', 'Desv. reparto %'], ['sospechosa', 'Sospechosa'],
  ], filas, (f) => (f.sospechosa === 'SI' ? 'sospechosa' : ''));
}

async function listar(ruta) {
  const r = await fetch(ruta, { cache: 'no-store' });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json();   // listado de nginx (autoindex_format json)
}

async function cargarResultados() {
  try {
    const r = await fetch('/datos/metricas/datos/metricas_limpias.csv', { cache: 'no-store' });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    RES.filas = leerCSV(await r.text());
    pintarResultados();
  } catch (e) {
    $('r-grafica').textContent = `No se pudieron leer los resultados (${e.message}). ¿Se levantó la interfaz con interfaz/compose.interfaz.yml?`;
  }

  const gal = $('r-galeria');
  try {
    const pngs = (await listar('/datos/metricas/graficas/')).filter((f) => /\.png$/i.test(f.name));
    gal.textContent = pngs.length ? '' : 'Sin gráficas.';
    pngs.forEach((f) => {
      const fig = document.createElement('figure');
      const a = document.createElement('a');
      a.href = `/datos/metricas/graficas/${encodeURIComponent(f.name)}`;
      a.target = '_blank';
      const img = document.createElement('img');
      img.src = a.href;
      img.alt = f.name;
      img.loading = 'lazy';
      a.append(img);
      const cap = document.createElement('figcaption');
      cap.textContent = f.name;
      fig.append(a, cap);
      gal.append(fig);
    });
  } catch { gal.textContent = 'Sin gráficas.'; }

  try {
    const r = await fetch('/datos/metricas/ANALISIS.md', { cache: 'no-store' });
    $('r-analisis').textContent = r.ok ? await r.text() : 'No disponible.';
  } catch { $('r-analisis').textContent = 'No disponible.'; }

  // Corridas nuevas de "make carga" / "make concurrencia": se leen los JSON de Artillery.
  const tabla = $('r-nuevas');
  try {
    const jsons = (await listar('/datos/resultados/make/'))
      .filter((f) => /\.json$/i.test(f.name))
      .sort((a, b) => b.mtime.localeCompare(a.mtime)).slice(0, 15);
    const filas = await Promise.all(jsons.map(async (f) => {
      const d = await (await fetch(`/datos/resultados/make/${encodeURIComponent(f.name)}`)).json();
      const c = d.aggregate?.counters || {};
      const s = d.aggregate?.summaries || {};
      const rt = s['http.response_time'] || {};
      const pet = c['http.requests'] || 0;
      const reparto = Object.keys(c).filter((k) => k.startsWith('backend.')).sort()
        .map((k) => `${k.slice(8)}=${c[k]}`).join(' ');
      return {
        nombre: f.name.replace(/\.json$/, ''), peticiones: pet,
        errores: pet - (c['http.codes.200'] || 0), fallidos: c['vusers.failed'] || 0,
        media: rt.mean, p95: rt.p95, p99: rt.p99,
        sesion: s['vusers.session_length']?.mean, reparto,
      };
    }));
    if (!filas.length) throw new Error('vacío');
    pintarTabla(tabla, [
      ['nombre', 'Corrida'], ['peticiones', 'Peticiones'], ['errores', 'Errores'],
      ['fallidos', 'Usuarios fallidos'], ['media', 'Media ms'], ['p95', 'p95 ms'],
      ['p99', 'p99 ms'], ['sesion', 'Sesión media ms'], ['reparto', 'Reparto'],
    ], filas);
  } catch {
    tabla.textContent = '';
    const tr = document.createElement('tr');
    const td = document.createElement('td');
    td.textContent = 'Aún no hay corridas nuevas (make carga / make concurrencia).';
    tr.append(td);
    tabla.append(tr);
  }
}

async function ciclo() {
  await Promise.all([
    consultarEstadoLb(),
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
  b.addEventListener('click', () => cambiarEscenario(b.dataset.n === 'principal' ? 'principal' : Number(b.dataset.n)));
});

$('r-backends').addEventListener('change', pintarResultados);
$('r-metrica').addEventListener('change', pintarGrafica);

// ---------- Inicio ----------
(async () => {
  await cargarConfig();
  cambiarEscenario('principal');
  ciclo();
  cargarResultados();
})();
