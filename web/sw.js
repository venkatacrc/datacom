// App files: network first, so a republished library shows up as soon as the phone is online.
// Pyodide and its packages are versioned and immutable: cache first, so Python works offline
// after the first run.
const CACHE = 'datacom-v1';
const RUNTIME = 'datacom-pyodide-v0.27.7';
const FILES = [
    './', 'index.html', 'app.css', 'content.css', 'render.js', 'editor.js', 'app.js', 'py-worker.js',
    'library.json', 'manifest.webmanifest', 'icons/icon-192.png', 'icons/icon-512.png', 'icons/maskable-512.png',
    'katex/katex.min.js', 'katex/katex.min.css',
];

self.addEventListener('install', (event) => {
    event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(FILES)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys()
            .then((keys) => Promise.all(keys.filter((k) => k !== CACHE && k !== RUNTIME).map((k) => caches.delete(k))))
            .then(() => self.clients.claim()));
});

self.addEventListener('fetch', (event) => {
    const { request } = event;
    if (request.method !== 'GET') return;
    const url = new URL(request.url);
    if (url.hostname === 'cdn.jsdelivr.net') {
        event.respondWith(caches.open(RUNTIME).then(async (cache) => {
            const hit = await cache.match(request);
            if (hit) return hit;
            const response = await fetch(request);
            if (response.ok) cache.put(request, response.clone());
            return response;
        }));
        return;
    }
    if (url.origin !== location.origin) return;
    event.respondWith(
        fetch(request)
            .then((response) => {
                if (response.ok) {
                    const copy = response.clone();
                    caches.open(CACHE).then((cache) => cache.put(request, copy));
                }
                return response;
            })
            .catch(() => caches.match(request, { ignoreSearch: true })));
});
