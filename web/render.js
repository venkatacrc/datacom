// Shared by the web app and the Mac app's content views: code highlighting, copy / try buttons,
// KaTeX for math and Mermaid for diagrams. Exposes window.DCRender.
(function () {
    'use strict';

    const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
    const config = { katexBase: 'katex/', mermaidSrc: 'https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js' };

    const PY_KW = 'False|None|True|and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield';
    const PY_BI = 'print|len|range|enumerate|zip|map|filter|sorted|sum|min|max|abs|list|dict|set|tuple|str|int|float|bool|isinstance|iter|next|open|super|any|all|reversed|round|type|object|self|cls|divmod|hash|repr|frozenset|bytes';
    const C_KW = 'if|else|for|while|return|const|void|int|float|double|long|unsigned|char|bool|struct|template|typename|auto|__global__|__device__|__shared__|__syncthreads|blockIdx|threadIdx|blockDim|gridDim|float4|include|define';
    const SQL_KW = 'select|from|where|group|by|order|having|limit|offset|join|left|right|inner|outer|full|cross|on|as|and|or|not|in|is|null|distinct|count|sum|avg|min|max|over|partition|rows|range|between|unbounded|preceding|following|current|row|with|union|all|case|when|then|else|end|insert|into|values|update|set|delete|create|table|index|desc|asc|rank|dense_rank|row_number|lag|lead|coalesce|exists|cast';
    const SH_KW = 'cd|ls|git|python|python3|pip|export|source|bash|echo|cat|mkdir|rm|cp|mv|sudo|docker|kubectl|nvidia-smi';

    const cache = {};
    function grammar(lang) {
        if (cache[lang]) return cache[lang];
        let parts;
        if (/^(c|cpp|cu|cuda|c\+\+|js|javascript|ts|swift)$/.test(lang)) {
            parts = [String.raw`\/\/[^\n]*|\/\*[\s\S]*?(?:\*\/|$)`, String.raw`"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'`,
                String.raw`#\w+`, String.raw`\b\d+(?:\.\d+)?f?\b`, `\\b(?:${C_KW})\\b`, String.raw`\b[A-Za-z_]\w*(?=\s*\()`];
        } else if (lang === 'sql') {
            parts = [String.raw`--[^\n]*`, String.raw`'(?:[^'\n]|'')*'|"[^"\n]*"`, String.raw`(?!)`, String.raw`\b\d+(?:\.\d+)?\b`,
                `\\b(?:${SQL_KW})\\b`, String.raw`(?!)`];
        } else if (/^(bash|sh|shell|console|zsh)$/.test(lang)) {
            parts = [String.raw`#[^\n]*`, String.raw`"(?:[^"\\\n]|\\.)*"|'[^'\n]*'`, String.raw`\$\{?\w+\}?`, String.raw`\b\d+(?:\.\d+)?\b`,
                `\\b(?:${SH_KW})\\b`, String.raw`(?:^|\s)--?[\w-]+`];
        } else {
            parts = [String.raw`#[^\n]*`,
                String.raw`[rRbBuUfF]{0,2}(?:"""[\s\S]*?(?:"""|$)|'''[\s\S]*?(?:'''|$)|"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*')`,
                String.raw`@[\w.]+`, String.raw`\b(?:0x[\da-fA-F_]+|\d[\d_]*(?:\.\d+)?(?:e-?\d+)?j?)\b`,
                `\\b(?:${PY_KW})\\b`, `\\b(?:${PY_BI})\\b`];
        }
        const flags = lang === 'sql' ? 'gi' : 'g';
        cache[lang] = new RegExp(parts.map((p) => `(${p})`).join('|'), flags);
        return cache[lang];
    }
    const CLS = ['tok-c', 'tok-s', 'tok-f', 'tok-n', 'tok-k', 'tok-b'];

    // One left-to-right scan over raw text, so a token can never land inside markup.
    function highlight(text, lang = 'python') {
        lang = (lang || 'python').toLowerCase();
        if (lang === 'text' || lang === 'plain' || lang === 'output') return esc(text);
        const re = grammar(lang);
        re.lastIndex = 0;
        let out = '';
        let last = 0;
        let m;
        while ((m = re.exec(text))) {
            if (m[0] === '') { re.lastIndex++; continue; }
            const g = m.slice(1).findIndex((x) => x !== undefined);
            out += esc(text.slice(last, m.index)) + `<span class="${CLS[g]}">${esc(m[0])}</span>`;
            last = m.index + m[0].length;
        }
        return out + esc(text.slice(last));
    }

    function langOf(code) {
        const cls = (code.className || '') + ' ' + ((code.parentElement && code.parentElement.className) || '');
        const m = cls.match(/(?:language|lang)-([\w+-]+)/);
        if (m) return m[1].toLowerCase();
        const t = code.textContent;
        if (/^\s*(SELECT|WITH|CREATE)\b/i.test(t)) return 'sql';
        if (/^\s*(\$ |git |pip |cd |python )/m.test(t) && !/\bdef\b/.test(t)) return 'bash';
        return /\b(def|import|print|return|for .* in)\b/.test(t) ? 'python' : 'text';
    }

    // Highlights <pre> blocks and adds Copy, plus Try for Python when onTry is given.
    function decorateCode(root, { onTry, onCopy } = {}) {
        root.querySelectorAll('pre').forEach((pre) => {
            if (pre.dataset.dc || pre.classList.contains('mermaid') || pre.closest('.editor')) return;
            pre.dataset.dc = '1';
            const code = pre.querySelector('code') || pre;
            const lang = langOf(code);
            const text = code.textContent.replace(/\n$/, '');
            code.innerHTML = highlight(text, lang);
            const tools = document.createElement('div');
            tools.className = 'code-tools';
            const copy = document.createElement('button');
            copy.type = 'button';
            copy.textContent = 'Copy';
            copy.addEventListener('click', (e) => { e.stopPropagation(); (onCopy || copyText)(text, copy); });
            tools.appendChild(copy);
            if (onTry && lang === 'python') {
                const run = document.createElement('button');
                run.type = 'button';
                run.className = 'try';
                run.textContent = '▶ Try';
                run.addEventListener('click', (e) => { e.stopPropagation(); onTry(text); });
                tools.appendChild(run);
            }
            pre.appendChild(tools);
        });
    }

    function copyText(text, btn) {
        const done = () => { if (btn) { btn.textContent = 'Copied'; setTimeout(() => { btn.textContent = 'Copy'; }, 1200); } };
        if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(text).then(done, () => {});
        else {
            const ta = document.createElement('textarea');
            ta.value = text;
            document.body.appendChild(ta);
            ta.select();
            try { document.execCommand('copy'); done(); } catch { /* ignore */ }
            ta.remove();
        }
    }

    const loaded = {};
    function loadScript(src) {
        if (!loaded[src]) {
            loaded[src] = new Promise((resolve, reject) => {
                const s = document.createElement('script');
                s.src = src;
                s.onload = resolve;
                s.onerror = () => { delete loaded[src]; reject(new Error('could not load ' + src)); };
                document.head.appendChild(s);
            });
        }
        return loaded[src];
    }
    function loadCSS(href) {
        if (document.querySelector(`link[href="${href}"]`)) return;
        const l = document.createElement('link');
        l.rel = 'stylesheet';
        l.href = href;
        document.head.appendChild(l);
    }

    const DELIMS = /\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]|\\\(([\s\S]+?)\\\)/g;
    const hasDelims = (s) => /\$\$[\s\S]+?\$\$|\\\[[\s\S]+?\\\]|\\\([\s\S]+?\\\)/.test(s);

    async function renderMath(root) {
        const marked = root.querySelectorAll('.tex[data-tex]:not([data-done])');
        if (!marked.length && !hasDelims(root.textContent)) return;
        loadCSS(config.katexBase + 'katex.min.css');
        try { await loadScript(config.katexBase + 'katex.min.js'); } catch { return; }
        const katex = window.katex;
        root.querySelectorAll('.tex[data-tex]:not([data-done])').forEach((el) => {
            el.dataset.done = '1';
            try { katex.render(el.dataset.tex, el, { displayMode: el.classList.contains('display'), throwOnError: false }); } catch { /* keep the source */ }
        });
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode: (n) => (n.parentElement.closest('pre, code, script, style, textarea, .katex, .tex')
                ? NodeFilter.FILTER_REJECT : hasDelims(n.nodeValue) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP),
        });
        const nodes = [];
        while (walker.nextNode()) nodes.push(walker.currentNode);
        nodes.forEach((node) => {
            const span = document.createElement('span');
            span.innerHTML = esc(node.nodeValue).replace(DELIMS, (whole, a, b, c) => {
                const src = (a || b || c).replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&').replace(/&quot;/g, '"');
                try { return katex.renderToString(src, { displayMode: Boolean(a || b), throwOnError: false }); } catch { return whole; }
            });
            node.replaceWith(...span.childNodes);
        });
    }

    async function renderMermaid(root) {
        const nodes = [...root.querySelectorAll('.mermaid:not([data-processed])')];
        if (!nodes.length) return;
        try {
            await loadScript(config.mermaidSrc);
            const dark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
            window.mermaid.initialize({ startOnLoad: false, theme: dark ? 'dark' : 'default', securityLevel: 'strict' });
            await window.mermaid.run({ nodes });
        } catch { nodes.forEach((n) => n.classList.add('mermaid-offline')); }
    }

    function renderAll(root, opts = {}) {
        decorateCode(root, opts);
        renderMath(root);
        renderMermaid(root);
    }

    window.DCRender = { config, esc, highlight, decorateCode, renderMath, renderMermaid, renderAll, copyText, loadScript };
})();
