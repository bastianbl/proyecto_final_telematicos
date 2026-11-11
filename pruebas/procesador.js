// Cuenta cuántas respuestas atiende cada backend para demostrar el reparto del balanceador.
// Los backends (backend/app.py) envían el header X-Backend-ID y devuelven "backendN" en el cuerpo.
// Aparece en el reporte como contador "backend.backendN".
module.exports = { contarBackend };

function contarBackend(req, res, context, ee, next) {
  let nombre = 'desconocido';
  const id = res.headers && res.headers['x-backend-id'];
  if (id) {
    nombre = 'backend' + id;
  } else if (typeof res.body === 'string') {
    const m = res.body.match(/backend\d+/);
    if (m) nombre = m[0];
  }
  ee.emit('counter', 'backend.' + nombre, 1);
  return next();
}
