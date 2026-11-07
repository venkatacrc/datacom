// Smoke test for the web app in headless Chrome at phone size: every view renders, a problem's
// reference solution passes its tests in Pyodide, a streaming playground run prints output,
// and Stop interrupts an endless loop. Screenshots go to build/shots/.
// Usage: node tools/smoke_web.mjs          Pyodide from a local copy in build/pyodide (fetched with curl)
//        node tools/smoke_web.mjs --cdn    Pyodide from cdn.jsdelivr.net, as on the phone
import { execFileSync, spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SHOTS = join(ROOT, 'build', 'shots');
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const PORT = 20000 + Math.floor(Math.random() * 20000);
const DEBUG = PORT + 1;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
mkdirSync(SHOTS, { recursive: true });

const CDN = 'https://cdn.jsdelivr.net/pyodide/v0.27.7/full/';
const useCdn = process.argv.includes('--cdn');
if (!useCdn) {
    const dir = join(ROOT, 'build', 'pyodide');
    mkdirSync(dir, { recursive: true });
    const get = (f) => { if (!existsSync(join(dir, f))) execFileSync('curl', ['-sfL', '-o', join(dir, f), CDN + f]); };
    ['pyodide.js', 'pyodide.asm.js', 'pyodide.asm.wasm', 'python_stdlib.zip', 'pyodide-lock.json'].forEach(get);
    const lock = JSON.parse(readFileSync(join(dir, 'pyodide-lock.json'), 'utf8')).packages;
    const want = new Set();
    const add = (name) => { if (!want.has(name)) { want.add(name); lock[name].depends.forEach(add); } };
    ['numpy', 'pandas', 'sqlite3'].forEach(add);
    want.forEach((name) => get(lock[name].file_name));
}
const START = `http://127.0.0.1:${PORT}/web/index.html${useCdn ? '' : '?pyodide=/build/pyodide/'}#learn`;

const server = spawn('python3', ['-m', 'http.server', String(PORT), '-d', ROOT], { stdio: 'ignore' });
const chrome = spawn(CHROME, [
    '--headless=new', `--remote-debugging-port=${DEBUG}`, `--user-data-dir=${mkdtempSync(join(tmpdir(), 'dc-chrome-'))}`,
    '--no-first-run', '--no-default-browser-check', '--window-size=390,844', 'about:blank',
], { stdio: 'ignore' });
const cleanup = () => { chrome.kill(); server.kill(); };
process.on('exit', cleanup);

let ws;
let seq = 0;
const pending = new Map();
const problems = [];
let failures = 0;

async function connect() {
    for (let i = 0; i < 50; i++) {
        try {
            const list = await (await fetch(`http://127.0.0.1:${DEBUG}/json/list`)).json();
            const page = list.find((t) => t.type === 'page');
            if (page) { ws = new WebSocket(page.webSocketDebuggerUrl); break; }
        } catch { /* Chrome still starting */ }
        await sleep(200);
    }
    await new Promise((r) => ws.addEventListener('open', r, { once: true }));
    ws.addEventListener('message', (e) => {
        const m = JSON.parse(e.data);
        if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
        if (m.method === 'Runtime.exceptionThrown') problems.push('exception: ' + m.params.exceptionDetails.exception?.description);
        if (m.method === 'Runtime.consoleAPICalled' && m.params.type === 'error') problems.push('console.error: ' + m.params.args.map((a) => a.value ?? a.description).join(' '));
        if (m.method === 'Log.entryAdded' && m.params.entry.level === 'error') problems.push('log: ' + m.params.entry.text + ' ' + (m.params.entry.url || ''));
    });
}
function send(method, params = {}) {
    const id = ++seq;
    ws.send(JSON.stringify({ id, method, params }));
    return new Promise((r) => pending.set(id, r));
}
async function js(expr) {
    const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
    if (r.result.exceptionDetails) throw new Error(r.result.exceptionDetails.exception?.description || 'evaluate failed');
    return r.result.result.value;
}
async function shot(name) {
    const r = await send('Page.captureScreenshot', { format: 'png' });
    writeFileSync(join(SHOTS, name + '.png'), Buffer.from(r.result.data, 'base64'));
}
async function waitFor(expr, ms = 15000) {
    const t0 = Date.now();
    while (Date.now() - t0 < ms) {
        if (await js(expr)) return true;
        await sleep(250);
    }
    return false;
}
function check(name, ok, detail = '') {
    console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${detail ? ' · ' + detail : ''}`);
    if (!ok) failures++;
}
async function go(hash) {
    await js(`location.hash = ${JSON.stringify(hash)}`);
    await sleep(400);
}

await connect();
await send('Page.enable');
await send('Runtime.enable');
await send('Log.enable');
await send('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 2, mobile: true });
await send('Page.navigate', { url: START });
if (!(await waitFor(`!!document.querySelector('.tiles .tile')`))) {
    console.log('FAIL library loads', await js(`location.href + ' · ' + document.body.innerText.slice(0, 300)`), problems);
    process.exit(1);
}
check('library loads', true);
check('home tiles', true, await js(`document.querySelectorAll('.tile').length + ' tracks'`));
await shot('01-home');

const lib = await js(`(() => { const l = window.__datacom.lib; return {
    lesson: l.lessons.find((x) => x.id.startsWith('algos:'))?.id, math: l.lessons.find((x) => x.id.startsWith('deepmath:'))?.id,
    track: l.tracks[0].id, problem: l.problems.find((p) => p.needs.length === 0).id,
    np: l.problems.find((p) => p.needs.includes('numpy'))?.id, pd: l.problems.find((p) => p.needs.includes('pandas'))?.id,
    sql: l.problems.find((p) => p.tests.includes('sqlite3') || p.starter.includes('QUERY'))?.id } })()`);

await go(`#track/${lib.track}`);
check('track page', await js(`document.querySelectorAll('.panel .row').length > 3`));
await shot('02-track');

await go(`#lesson/${lib.lesson}`);
check('algos lesson', await js(`document.querySelector('.lesson .content').textContent.length > 200`), lib.lesson);
await shot('03-lesson-algos');
await go(`#lesson/${lib.math}`);
await waitFor(`!!document.querySelector('.katex')`, 5000);
check('deepmath lesson renders KaTeX', await js(`document.querySelectorAll('.katex').length > 0`), lib.math);
await shot('04-lesson-math');

await go('#cards');
check('cards deck', await js(`!!document.querySelector('.card.flash .q')`));
await shot('05-cards');
await js(`document.querySelector('[data-act="mode"][data-mode="test"]').click()`);
await js(`document.querySelector('[data-act="reveal"]').click()`);
check('test mode reveal', await js(`!!document.querySelector('.flash .a')`));

await go('#code');
check('problem list', await js(`document.querySelectorAll('.row .dot').length >= 100`), await js(`document.querySelectorAll('.row .dot').length + ' problems'`));
await shot('06-code-list');

async function solve(id, label, ms = 120000) {
    await go(`#problem/${id}`);
    await js(`(() => { const p = window.__datacom.lib.problems.find((x) => x.id === ${JSON.stringify(id)});
        const ta = document.querySelector('.editor textarea'); ta.value = p.solution; ta.dispatchEvent(new Event('input', { bubbles: true })); })()`);
    const t0 = Date.now();
    await js(`document.querySelector('[data-act="run"]').click()`);
    const done = await waitFor(`/tests passed|Error|Stopped/.test(document.querySelector('#run-status').textContent)`, ms);
    const status = await js(`document.querySelector('#run-status').textContent`);
    check(`${label} solution passes in Pyodide`, done && /✓/.test(status) && /passed/.test(status), `${status} (${((Date.now() - t0) / 1000).toFixed(1)} s wall)`);
    if (!/✓/.test(status)) console.log(await js(`document.querySelector('#console').textContent.slice(0, 1500)`));
    return status;
}
await solve(lib.problem, 'pure-Python problem', 180000);
await shot('07-problem-solved');
check('solved recorded', await js(`!!window.__datacom.state.solved[${JSON.stringify(lib.problem)}]`));
if (lib.np) await solve(lib.np, 'numpy problem');
if (lib.pd) { await solve(lib.pd, 'pandas problem'); await shot('08-pandas'); }
if (lib.sql) await solve(lib.sql, 'sqlite problem');

// Every reference solution, through the same UI path.
const ids = await js(`window.__datacom.lib.problems.map((p) => p.id)`);
const failed = [];
for (const id of ids) {
    await go(`#problem/${id}`);
    await js(`(() => { const p = window.__datacom.lib.problems.find((x) => x.id === ${JSON.stringify(id)});
        const ta = document.querySelector('.editor textarea'); ta.value = p.solution; ta.dispatchEvent(new Event('input', { bubbles: true })); })()`);
    await js(`document.querySelector('[data-act="run"]').click()`);
    await waitFor(`/tests passed|Error|Finished/.test(document.querySelector('#run-status').textContent)`, 60000);
    const status = await js(`document.querySelector('#run-status').textContent`);
    if (!/✓ (\d+)\/\1 tests passed/.test(status)) failed.push(`${id}: ${status} ${await js(`document.querySelector('#console').textContent.slice(0, 400)`)}`);
}
check(`all ${ids.length} reference solutions pass in Pyodide`, !failed.length, failed.join('\n'));

// Starter code should fail the tests rather than crash the harness.
await go(`#problem/${lib.problem}`);
await js(`(() => { const p = window.__datacom.lib.problems.find((x) => x.id === ${JSON.stringify(lib.problem)});
    const ta = document.querySelector('.editor textarea'); ta.value = p.starter; ta.dispatchEvent(new Event('input', { bubbles: true })); })()`);
await js(`document.querySelector('[data-act="run"]').click()`);
await waitFor(`/tests passed|Error/.test(document.querySelector('#run-status').textContent)`, 30000);
check('starter code reports failures', await js(`/✗/.test(document.querySelector('#run-status').textContent)`), await js(`document.querySelector('#run-status').textContent`));

// Streaming playground template: output should arrive while it runs.
await go('#playground');
await js(`(() => { const s = document.querySelector('#pg-select'); const o = [...s.options].find((x) => /Streaming/.test(x.text)); s.value = o.value; s.dispatchEvent(new Event('change', { bubbles: true })); })()`);
await sleep(300);
await js(`document.querySelector('[data-act="run"]').click()`);
const streamed = await waitFor(`document.querySelector('#console').textContent.split('\\n').length > 3 && /Running/.test(document.querySelector('#run-status').textContent)`, 30000);
check('playground streams output while running', streamed);
await waitFor(`/Finished|Error|Stopped/.test(document.querySelector('#run-status').textContent)`, 60000);
check('streaming template finishes', await js(`/Finished/.test(document.querySelector('#run-status').textContent)`), await js(`document.querySelector('#run-status').textContent`));
await shot('09-playground-stream');

// Stop an endless loop.
await js(`(() => { const ta = document.querySelector('.editor textarea'); ta.value = 'i = 0\\nwhile True:\\n    i += 1\\n'; ta.dispatchEvent(new Event('input', { bubbles: true })); })()`);
await js(`document.querySelector('[data-act="run"]').click()`);
await sleep(1500);
await js(`document.querySelector('[data-act="stop"]').click()`);
check('stop interrupts an endless loop', await waitFor(`/Stopped/.test(document.querySelector('#run-status').textContent)`, 3000));
await js(`(() => { const ta = document.querySelector('.editor textarea'); ta.value = 'print(sum(range(10)))\\n'; ta.dispatchEvent(new Event('input', { bubbles: true })); })()`);
await js(`document.querySelector('[data-act="run"]').click()`);
await waitFor(`/Finished|Error/.test(document.querySelector('#run-status').textContent)`, 60000);
check('runs again after stop', await js(`document.querySelector('#console').textContent.trim() === '45'`), await js(`document.querySelector('#console').textContent.trim()`));

await go('#progress');
check('progress page', await js(`document.querySelectorAll('.kpi').length === 4`));
await shot('10-progress');
await go('#search');
await js(`(() => { const i = document.querySelector('#search-input'); i.value = 'sliding window'; i.dispatchEvent(new Event('input', { bubbles: true })); })()`);
check('search finds results', await js(`document.querySelectorAll('#search-results .row').length > 0`));
await shot('11-search');

check('no page errors', problems.length === 0, problems.slice(0, 8).join(' | '));
console.log(failures ? `${failures} check(s) failed` : 'all checks passed', `· screenshots in ${SHOTS}`);
cleanup();
process.exit(failures ? 1 : 0);
