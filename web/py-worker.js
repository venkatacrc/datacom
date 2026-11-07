// Runs Python in a Web Worker with Pyodide, so a long or endless loop never freezes the page and
// output streams back line by line. The page stops a run by terminating this worker.
/* global loadPyodide */
// py-worker.js?base=URL loads Pyodide from a self-hosted copy instead of the CDN.
const PYODIDE = new URL(self.location.href).searchParams.get('base') || 'https://cdn.jsdelivr.net/pyodide/v0.27.7/full/';
let pyodide = null;
let booting = null;
let helpers = '';

function post(msg) { self.postMessage(msg); }

// Fetched here rather than by loadPyodide so a blocked download gives a clear message instead
// of Python's "No module named 'encodings'" startup crash.
async function fetchStdlib() {
    let response;
    try { response = await fetch(PYODIDE + 'python_stdlib.zip'); } catch { response = null; }
    if (!response || !response.ok) {
        throw new Error(`Couldn't download Python's standard library from ${new URL(PYODIDE, self.location.href).host}. `
            + 'Some networks (corporate web filters in particular) block .zip and .whl downloads; '
            + 'try another network, or use the Mac app, which runs your local python3.');
    }
    return URL.createObjectURL(await response.blob());
}

async function boot() {
    if (!booting) {
        booting = (async () => {
            post({ type: 'status', text: 'Loading Python (about 10 MB the first time, then cached)…' });
            importScripts(PYODIDE + 'pyodide.js');
            const stdLibURL = await fetchStdlib();
            pyodide = await loadPyodide({ indexURL: PYODIDE, stdLibURL, stdout: () => {}, stderr: () => {} });
            URL.revokeObjectURL(stdLibURL);
            pyodide.FS.mkdirTree('/home/pyodide');
            post({ type: 'ready', version: pyodide.version });
        })();
        booting.catch(() => { booting = null; });
    }
    return booting;
}

// Drop Pyodide's own frames so the traceback points at the user's code.
function cleanTraceback(text) {
    const lines = String(text).split('\n');
    const out = [];
    let skip = false;
    for (const line of lines) {
        if (/^\s*File "\/lib\/python[\d.]+\/|^\s*File "\/lib\/python\d+\.zip|_pyodide|pyodide\/_base/.test(line)) { skip = true; continue; }
        if (skip && /^\s{4,}\S/.test(line) && !/^\s*File /.test(line)) continue;
        skip = false;
        out.push(line);
    }
    return out.join('\n').trim();
}

self.onmessage = async (e) => {
    const msg = e.data;
    if (msg.type === 'helpers') { helpers = msg.code; return; }
    if (msg.type === 'warm') { try { await boot(); } catch (err) { post({ type: 'error', text: String(err) }); } return; }
    if (msg.type !== 'run') return;
    const { id, code, stdin } = msg;
    try {
        await boot();
        pyodide.FS.writeFile('/home/pyodide/dc.py', msg.helpers || helpers);
        // `scan` is extra source to look for imports in, such as tests embedded in a string.
        await pyodide.loadPackagesFromImports(msg.scan ? `${code}\n${msg.scan}` : code, {
            messageCallback: (m) => { if (/^Loading /.test(m)) post({ type: 'status', id, text: m }); },
            errorCallback: (m) => post({ type: 'err', id, text: m + (/Failed to fetch|NetworkError/i.test(m) ? ' (the network may block .whl downloads)' : '') + '\n' }),
        });
        pyodide.setStdout({ batched: (s) => post({ type: 'out', id, text: s + '\n' }) });
        pyodide.setStderr({ batched: (s) => post({ type: 'err', id, text: s + '\n' }) });
        let fed = false;
        pyodide.setStdin({ stdin: () => { if (fed || !stdin) return undefined; fed = true; return stdin; } });
        pyodide.runPython("import sys, os\nos.chdir('/home/pyodide')\nsys.path.insert(0, '/home/pyodide') if '/home/pyodide' not in sys.path else None\nsys.modules.pop('dc', None)");
        const globals = pyodide.toPy({ __name__: '__main__' });
        post({ type: 'start', id });
        const t0 = performance.now();
        try {
            await pyodide.runPythonAsync(code, { globals, filename: 'main.py' });
            post({ type: 'done', id, ok: true, ms: performance.now() - t0 });
        } catch (err) {
            post({ type: 'err', id, text: cleanTraceback(err.message) + '\n' });
            post({ type: 'done', id, ok: false, ms: performance.now() - t0 });
        } finally {
            globals.destroy();
        }
    } catch (err) {
        post({ type: 'err', id, text: String(err && err.message || err) + '\n' });
        post({ type: 'done', id, ok: false, ms: 0 });
    }
};
