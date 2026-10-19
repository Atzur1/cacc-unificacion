const puppeteer = require('puppeteer-core');
const path = require('path');
const OUT = __dirname;
const ADMIN = 'http://localhost:4200', DEPO = 'http://localhost:4300';
const CLAVE = 'Camioneros.Test.2026!';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const resultados = [];
function chk(nombre, ok, detalle = '') { resultados.push({ nombre, ok }); console.log(`${ok ? 'PASA ' : 'FALLA'} | ${nombre} | ${detalle}`); }

async function login(page, dni) {
  await page.goto(ADMIN + '/', { waitUntil: 'networkidle2' });
  await page.waitForSelector('input[formcontrolname="username"]', { timeout: 20000 });
  await page.type('input[formcontrolname="username"]', dni);
  await page.type('input[formcontrolname="password"]', CLAVE);
  await page.click('button[type="submit"].btn-primary');
}
async function esperarUrl(page, fn, ms = 40000) {
  try { await page.waitForFunction(fn, { timeout: ms }); return true; } catch { return false; }
}
async function texto(page) { return (await page.evaluate(() => document.body.innerText)).replace(/\s+/g, ' ').slice(0, 300); }

(async () => {
  const browser = await puppeteer.launch({ executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe', headless: 'new', args: ['--no-sandbox'] });
  const nuevo = async () => { const ctx = await browser.createBrowserContext(); const p = await ctx.newPage(); await p.setViewport({ width: 1280, height: 800 }); p.on('pageerror', (e) => console.log('   [pageerror]', String(e).slice(0, 160))); return p; };

  for (const [nombre, dni, ruta] of [['Médica', '30000003', '/medico'], ['Director Técnico', '30000004', '/dt']]) {
    const p = await nuevo();
    await login(p, dni);
    const ok = await esperarUrl(p, (d) => location.port === '4300' && !location.pathname.startsWith('/login'));
    await sleep(2500);
    const url = p.url();
    chk(`${nombre}: entra directo al Deportivo sin ver ningún login`, ok && url.startsWith(DEPO + ruta), url);
    chk(`${nombre}: la barra de direcciones no muestra el token`, !url.includes('sso=') && !url.includes('eyJ'), '');
    await p.screenshot({ path: path.join(OUT, `${dni}.png`) });
    console.log('   texto:', await texto(p));
    await p.browserContext().close();
  }

  // SuperAdmin: portales -> deportivo -> volver a portales -> personas
  const p = await nuevo();
  await login(p, '20111222');
  let ok = await esperarUrl(p, () => location.port === '4200' && location.pathname === '/portales');
  chk('SuperAdmin: ve la elección de portales (Administrativo)', ok, p.url());
  await sleep(1500);
  await p.screenshot({ path: path.join(OUT, 'portales.png') });
  await p.click('.card-portal-deportivo .btn-portal');
  ok = await esperarUrl(p, () => location.port === '4300' && location.pathname.startsWith('/admin'));
  await sleep(2500);
  chk('SuperAdmin: pasa al Deportivo (panel de administración) sin pedir clave', ok && !p.url().includes('sso='), p.url());
  await p.screenshot({ path: path.join(OUT, 'deportivo_admin.png') });
  await p.goto(DEPO + '/admin/portales', { waitUntil: 'domcontentloaded' });
  ok = await esperarUrl(p, () => location.port === '4200' && location.pathname === '/portales');
  await sleep(1500);
  chk('"Volver a portales" del Deportivo lleva a la elección ÚNICA del Administrativo, con la sesión abierta', ok, p.url() + ' | ' + await texto(p));
  await p.click('.card-portal-personas .btn-portal');
  ok = await esperarUrl(p, () => location.port === '4300' && location.pathname === '/admin/registro-personas');
  await sleep(2500);
  chk('SuperAdmin: "Personas" abre el alta de personas del Deportivo', ok, p.url());
  await p.screenshot({ path: path.join(OUT, 'personas.png') });
  await p.browserContext().close();

  // Sin sesión: el Deportivo no muestra login propio
  const q = await nuevo();
  await q.goto(DEPO + '/login', { waitUntil: 'domcontentloaded' });
  ok = await esperarUrl(q, () => location.port === '4200');
  chk('Entrar al Deportivo sin sesión redirige al login único (no muestra uno propio)', ok, q.url());
  const q2 = await nuevo();
  await q2.goto(DEPO + '/admin/jugadores', { waitUntil: 'domcontentloaded' });
  ok = await esperarUrl(q2, () => location.port === '4200');
  chk('Una pantalla protegida del Deportivo sin sesión también va al login único', ok, q2.url());

  await browser.close();
  const mal = resultados.filter((r) => !r.ok).length;
  console.log(`\n=== ${resultados.length - mal} PASAN | ${mal} FALLAN`);
  process.exit(mal ? 1 : 0);
})();
