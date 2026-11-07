// Datacom: interview prep with lessons, flash cards and a Python runner. Plain JavaScript, no build step.
// library.json comes from tools/build_library.py; Python runs in py-worker.js (Pyodide).
(() => {
    'use strict';

    const STORE = 'datacom-v1';
    const VIEWS = [['learn', 'Learn'], ['cards', 'Cards'], ['code', 'Code'], ['progress', 'Progress']];
    const ROUTES = /^(learn|track\/|lesson\/|cards|code|problem\/|playground|progress|search)/;
    const MAX_CONSOLE = 200_000;
    const $ = (sel) => document.querySelector(sel);
    const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
    const plain = (h) => String(h || '').replace(/<[^>]+>/g, ' ').replace(/&[a-z#0-9]+;/gi, ' ').replace(/\s+/g, ' ').trim();
    const coarse = window.matchMedia('(pointer: coarse)').matches;

    let lib = null;
    let ix = null;
    let state = load();
    let route = { name: 'learn', id: null };
    let deck = [];
    let pos = 0;
    let revealed = false;
    let finished = false;
    let score = { got: 0, missed: 0, missedIds: [] };
    let editor = null;
    let saveTimer = 0;

    function blank() {
        return {
            selected: null, focus: null, cardMode: 'learn', filter: 'all', shuffle: false,
            cards: {}, read: {}, solved: {}, attempts: {}, code: {}, snippets: {}, scratch: null, pgCurrent: 'scratch',
            stdin: '', codeFilter: 'all', lastLesson: null, lastProblem: null, lastRoute: '#learn',
        };
    }
    function load() {
        try { return Object.assign(blank(), JSON.parse(localStorage.getItem(STORE) || '{}')); } catch { return blank(); }
    }
    function save() {
        try { localStorage.setItem(STORE, JSON.stringify(state)); } catch { toast('Storage is full: export your progress'); }
    }
    function saveSoon() { clearTimeout(saveTimer); saveTimer = setTimeout(save, 400); }

    function toast(msg) {
        const t = $('#toast');
        t.textContent = msg;
        t.hidden = false;
        clearTimeout(toast.timer);
        toast.timer = setTimeout(() => { t.hidden = true; }, 2200);
    }

    // ---------------------------------------------------------------- library index

    function index(l) {
        const x = {
            track: {}, section: {}, lesson: {}, problem: {}, card: {}, lessons: {}, problems: {}, cards: {},
            orderedLessons: [], orderedProblems: [],
        };
        l.tracks.forEach((t) => {
            x.track[t.id] = t;
            t.sections.forEach((s) => { x.section[s.id] = Object.assign(s, { track: t.id }); });
            x.lessons[t.id] = [];
            x.problems[t.id] = [];
            x.cards[t.id] = [];
        });
        l.lessons.forEach((it) => { x.lesson[it.id] = it; });
        l.problems.forEach((it) => { x.problem[it.id] = it; });
        l.cards.forEach((it) => { x.card[it.id] = it; if (x.cards[it.track]) x.cards[it.track].push(it); });
        l.tracks.forEach((t) => {
            t.sections.forEach((s) => {
                const ls = l.lessons.filter((it) => it.section === s.id);
                const ps = l.problems.filter((it) => it.section === s.id);
                s.lessons = ls;
                s.problems = ps;
                s.cardCount = l.cards.filter((c) => c.section === s.id).length;
                x.lessons[t.id].push(...ls);
                x.problems[t.id].push(...ps);
            });
            x.orderedLessons.push(...x.lessons[t.id]);
            x.orderedProblems.push(...x.problems[t.id]);
        });
        l.playground.forEach((p) => { x.template = x.template || {}; x.template[p.id] = p; });
        return x;
    }
    const trackTitle = (id) => (ix.track[id] ? ix.track[id].title : id);
    const sectionTitle = (id) => (ix.section[id] ? ix.section[id].title : '');
    const selectedTracks = () => state.selected || lib.tracks.map((t) => t.id);

    // ---------------------------------------------------------------- routing

    function parseHash() {
        const h = decodeURIComponent(location.hash.slice(1)) || 'learn';
        const [name, ...rest] = h.split('/');
        const id = rest.join('/') || null;
        if (name === 'lesson' && ix.lesson[id]) return { name, id };
        if (name === 'track' && ix.track[id]) return { name, id };
        if (name === 'problem' && ix.problem[id]) return { name, id };
        if (name === 'playground') return { name, id };
        if (['learn', 'cards', 'code', 'progress', 'search'].includes(name)) return { name, id: null };
        return { name: 'learn', id: null };
    }
    function viewOf(r) {
        if (['learn', 'track', 'lesson', 'search'].includes(r.name)) return 'learn';
        if (['code', 'problem', 'playground'].includes(r.name)) return 'code';
        return r.name;
    }
    function go(hash) {
        if (location.hash === hash) onRoute();
        else location.hash = hash;
    }

    function onRoute() {
        const before = route;
        route = parseHash();
        if (route.name === 'cards' && (before.name !== 'cards' || !deck.length)) buildDeck();
        if (route.name === 'lesson') { state.lastLesson = route.id; }
        if (route.name === 'problem') { state.lastProblem = route.id; }
        if (route.name === 'playground' && route.id) state.pgCurrent = route.id;
        state.lastRoute = location.hash || '#learn';
        save();
        render();
        const card = $('#card');
        if (card) card.scrollTop = 0;
        if (viewOf(route) === 'code') runner.warm();
    }

    // ---------------------------------------------------------------- render

    function render() {
        document.body.classList.toggle('wide', ['problem', 'playground'].includes(route.name));
        renderSwitches();
        renderStatus();
        renderStage();
        renderActions();
        if ($('#drawer').classList.contains('open')) renderDrawer();
        const titles = {
            lesson: () => ix.lesson[route.id].title, problem: () => ix.problem[route.id].title,
            track: () => ix.track[route.id].title,
        };
        document.title = (titles[route.name] ? titles[route.name]() + ' · ' : '') + 'Datacom';
    }

    function renderSwitches() {
        const v = viewOf(route);
        $('#view-switch').innerHTML = VIEWS.map(([id, t]) =>
            `<button type="button" data-act="view" data-view="${id}" class="${v === id ? 'on' : ''}">${t}</button>`).join('');
    }

    function renderStatus() {
        let left = '';
        let right = '';
        const r = route;
        if (r.name === 'learn') {
            left = `<strong>${esc(lib.subtitle || 'Crack the interview')}</strong>`;
            right = `built ${esc(lib.built)}`;
        } else if (r.name === 'track') {
            const ls = ix.lessons[r.id];
            left = `<strong>${esc(trackTitle(r.id))}</strong>`;
            right = `${ls.filter((l) => state.read[l.id]).length} of ${ls.length} read`;
        } else if (r.name === 'lesson') {
            const l = ix.lesson[r.id];
            const ls = ix.lessons[l.track];
            left = `<a href="#track/${esc(l.track)}">${esc(trackTitle(l.track))}</a> · ${esc(sectionTitle(l.section))}`;
            right = `${ls.indexOf(l) + 1} of ${ls.length}`;
        } else if (r.name === 'cards') {
            if (deck.length && !finished) {
                left = `<strong>Card ${pos + 1}</strong> of ${deck.length}${focusLabel() ? ' · ' + esc(focusLabel()) : ''}`;
                if (state.cardMode === 'test') {
                    const answered = score.got + score.missed;
                    right = `Score ${score.got}/${answered}`;
                } else {
                    right = `Known ${deck.filter((c) => state.cards[c.id] === 'known').length}`;
                }
            } else left = focusLabel() ? esc(focusLabel()) : '';
        } else if (r.name === 'code') {
            const n = lib.problems.length;
            left = '<strong>Coding problems</strong>';
            right = `${Object.keys(state.solved).filter((id) => ix.problem[id]).length} of ${n} solved`;
        } else if (r.name === 'problem') {
            const p = ix.problem[r.id];
            left = `<a href="#code">${esc(trackTitle(p.track))}</a> · ${esc(sectionTitle(p.section))}`;
            right = state.solved[p.id] ? '<span class="ok">✓ solved</span>' : attemptText(p.id);
        } else if (r.name === 'playground') {
            left = '<strong>Playground</strong> · any Python';
            right = 'Pyodide · Python 3.12';
        } else if (r.name === 'progress') {
            left = '<strong>Progress</strong>';
            right = 'saved in this browser';
        } else if (r.name === 'search') {
            left = '<strong>Search</strong>';
        }
        $('#status').innerHTML = `<span>${left}</span><span>${right}</span>`;
    }
    function attemptText(id) {
        const a = state.attempts[id];
        return a ? `last run ${a.passed}/${a.total}` : '';
    }

    function renderStage() {
        editor = null;
        const stage = $('#stage');
        const r = route;
        let html;
        if (r.name === 'learn') html = homeHTML();
        else if (r.name === 'track') html = trackHTML(ix.track[r.id]);
        else if (r.name === 'lesson') html = lessonHTML(ix.lesson[r.id]);
        else if (r.name === 'cards') html = cardHTML();
        else if (r.name === 'code') html = codeListHTML();
        else if (r.name === 'problem') html = problemHTML(ix.problem[r.id]);
        else if (r.name === 'playground') html = playgroundHTML();
        else if (r.name === 'progress') html = progressHTML();
        else if (r.name === 'search') html = searchHTML();
        stage.innerHTML = html;
        stage.querySelectorAll('.content a[href^="http"]').forEach((a) => { a.target = '_blank'; a.rel = 'noopener'; });
        window.DCRender.renderAll(stage, { onTry: tryInPlayground });
        if (r.name === 'problem') mountProblem(ix.problem[r.id]);
        if (r.name === 'playground') mountPlayground();
        if (r.name === 'search') { const i = $('#search-input'); i.focus(); renderSearchResults(i.value); }
    }

    // ---- learn ----

    function counts(t) {
        const ls = ix.lessons[t.id];
        const ps = ix.problems[t.id];
        const cs = ix.cards[t.id];
        return {
            lessons: ls.length, read: ls.filter((l) => state.read[l.id]).length,
            problems: ps.length, solved: ps.filter((p) => state.solved[p.id]).length,
            cards: cs.length, known: cs.filter((c) => state.cards[c.id] === 'known').length,
        };
    }
    function bar(done, total) {
        return `<span class="bar"><i style="width:${total ? (done / total) * 100 : 0}%"></i></span>`;
    }

    function homeHTML() {
        const solved = Object.keys(state.solved).filter((id) => ix.problem[id]).length;
        const known = Object.values(state.cards).filter((v) => v === 'known').length;
        const read = Object.keys(state.read).filter((id) => ix.lesson[id]).length;
        const cont = [];
        if (state.lastLesson && ix.lesson[state.lastLesson]) {
            cont.push(`<a class="row" href="#lesson/${esc(state.lastLesson)}"><span class="ico">📖</span><span class="grow">${esc(ix.lesson[state.lastLesson].title)}<small>Continue reading</small></span><span class="chev">›</span></a>`);
        }
        if (state.lastProblem && ix.problem[state.lastProblem]) {
            cont.push(`<a class="row" href="#problem/${esc(state.lastProblem)}"><span class="ico">⌨️</span><span class="grow">${esc(ix.problem[state.lastProblem].title)}<small>Continue coding</small></span><span class="chev">›</span></a>`);
        }
        cont.push(`<a class="row" href="#playground"><span class="ico">🧪</span><span class="grow">Playground<small>Run any Python: algorithms, batch or streaming data</small></span><span class="chev">›</span></a>`);
        const tiles = lib.tracks.map((t) => {
            const c = counts(t);
            const bits = [];
            if (c.lessons) bits.push(`${c.lessons} lessons`);
            if (c.cards) bits.push(`${c.cards} cards`);
            if (c.problems) bits.push(`${c.problems} problems`);
            const done = c.read + c.known + c.solved;
            const total = c.lessons + c.cards + c.problems;
            return `<a class="tile" href="#track/${esc(t.id)}" style="--tc:${esc(t.color || 'var(--accent)')}">
                <span class="tile-title">${esc(t.title)}</span>
                <span class="tile-blurb">${esc(t.blurb || '')}</span>
                <span class="tile-meta">${bits.join(' · ')}</span>
                ${bar(done, total)}</a>`;
        }).join('');
        return `<article class="card page" id="card">
            <h1 class="hero">Crack the interview</h1>
            <div class="kpis">
                <div class="kpi"><b>${solved}<small>/${lib.problems.length}</small></b><span>problems solved</span></div>
                <div class="kpi"><b>${known}<small>/${lib.cards.length}</small></b><span>cards known</span></div>
                <div class="kpi"><b>${read}<small>/${lib.lessons.length}</small></b><span>lessons read</span></div>
            </div>
            <div class="panel">${cont.join('')}</div>
            <h4>Tracks</h4>
            <div class="tiles">${tiles}</div>
            <p class="fine install-hint">On a phone: Chrome ⋮ → <strong>Install app</strong> (Safari: Share → <strong>Add to Home Screen</strong>). Lessons and cards work offline; Python works offline after its first run.</p>
        </article>`;
    }

    function trackHTML(t) {
        const c = counts(t);
        const secs = t.sections.map((s) => {
            const rows = s.lessons.map((l) => `<a class="row" href="#lesson/${esc(l.id)}">
                <span class="tick ${state.read[l.id] ? 'on' : ''}">${state.read[l.id] ? '✓' : ''}</span>
                <span class="grow">${esc(l.title)}</span><span class="chev">›</span></a>`).join('');
            const extra = [];
            if (s.problems.length) {
                const solved = s.problems.filter((p) => state.solved[p.id]).length;
                extra.push(`<button type="button" class="row" data-act="code-section" data-id="${esc(s.id)}"><span class="ico">⌨️</span><span class="grow">${s.problems.length} coding problems<small>${solved} solved</small></span><span class="chev">›</span></button>`);
            }
            if (s.cardCount) {
                extra.push(`<button type="button" class="row" data-act="focus" data-type="section" data-id="${esc(s.id)}"><span class="ico">🃏</span><span class="grow">Practise ${s.cardCount} cards</span><span class="chev">›</span></button>`);
            }
            return `<h4>${esc(s.title)}</h4><div class="panel">${rows}${extra.join('')}</div>`;
        }).join('');
        const credits = (t.sources || []).map((s) => (s.url ? `<a href="${esc(s.url)}" target="_blank" rel="noopener">${esc(s.title)}</a>` : esc(s.title))).join(' · ');
        return `<article class="card page" id="card" style="--tc:${esc(t.color || 'var(--accent)')}">
            <p class="kicker">Track</p>
            <h1>${esc(t.title)}</h1>
            <p class="lead">${esc(t.blurb || '')}</p>
            <div class="kpis small">
                <div class="kpi"><b>${c.read}/${c.lessons}</b><span>lessons read</span></div>
                <div class="kpi"><b>${c.known}/${c.cards}</b><span>cards known</span></div>
                <div class="kpi"><b>${c.solved}/${c.problems}</b><span>problems solved</span></div>
            </div>
            ${secs}
            ${credits ? `<p class="fine">From ${credits}</p>` : ''}
        </article>`;
    }

    function lessonHTML(l) {
        return `<article class="card page lesson" id="card">
            <div class="content">${l.html}</div>
            ${l.url ? `<p class="fine source-link"><a href="${esc(l.url)}" target="_blank" rel="noopener">↗ Open the original</a></p>` : ''}
        </article>`;
    }
    function stepLesson(delta) {
        const l = ix.lesson[route.id];
        const ls = ix.lessons[l.track];
        const next = ls[ls.indexOf(l) + delta];
        if (next) go(`#lesson/${next.id}`);
    }
    function cardsForLesson(id) { return lib.cards.filter((c) => c.lesson === id); }

    // ---- search ----

    function searchHTML() {
        return `<article class="card page" id="card">
            <input id="search-input" class="search" type="search" placeholder="Search lessons, problems and cards" autocomplete="off" value="${esc(state.lastSearch || '')}">
            <div id="search-results"></div></article>`;
    }
    function renderSearchResults(q) {
        state.lastSearch = q;
        const box = $('#search-results');
        if (!box) return;
        const terms = q.toLowerCase().split(/\s+/).filter(Boolean);
        if (!terms.length) { box.innerHTML = '<p class="fine">Type to search titles, problem tags and card text.</p>'; return; }
        const hit = (s) => { const t = s.toLowerCase(); return terms.every((w) => t.includes(w)); };
        const lessons = lib.lessons.filter((l) => hit(l.title + ' ' + sectionTitle(l.section))).slice(0, 25);
        const problems = lib.problems.filter((p) => hit(`${p.title} ${p.tags.join(' ')} ${sectionTitle(p.section)}`)).slice(0, 25);
        if (!ix.cardText) ix.cardText = new Map(lib.cards.map((c) => [c.id, plain(c.front).slice(0, 300)]));
        const cards = lib.cards.filter((c) => hit(ix.cardText.get(c.id))).slice(0, 25);
        const group = (title, rows) => (rows.length ? `<h4>${title}</h4><div class="panel">${rows.join('')}</div>` : '');
        box.innerHTML = group('Problems', problems.map((p) => `<a class="row" href="#problem/${esc(p.id)}"><span class="grow">${esc(p.title)}<small>${esc(trackTitle(p.track))} · ${esc(p.difficulty)}</small></span><span class="chev">›</span></a>`))
            + group('Lessons', lessons.map((l) => `<a class="row" href="#lesson/${esc(l.id)}"><span class="grow">${esc(l.title)}<small>${esc(trackTitle(l.track))} · ${esc(sectionTitle(l.section))}</small></span><span class="chev">›</span></a>`))
            + group('Cards', cards.map((c) => `<button type="button" class="row" data-act="focus" data-type="card" data-id="${esc(c.id)}"><span class="grow">${esc(ix.cardText.get(c.id).slice(0, 120))}<small>${esc(trackTitle(c.track))} · ${esc(c.label || '')}</small></span><span class="chev">›</span></button>`))
            || '<p class="fine">Nothing matches.</p>';
    }

    // ---- cards ----

    function focusLabel() {
        const f = state.focus;
        if (!f) return '';
        if (f.type === 'section') return sectionTitle(f.id);
        if (f.type === 'lesson') return ix.lesson[f.id] ? ix.lesson[f.id].title : '';
        if (f.type === 'track') return trackTitle(f.id);
        if (f.type === 'card') return 'Search result';
        return '';
    }
    function buildDeck() {
        const f = state.focus;
        let pool;
        if (f && f.type === 'section') pool = lib.cards.filter((c) => c.section === f.id);
        else if (f && f.type === 'lesson') pool = cardsForLesson(f.id);
        else if (f && f.type === 'track') pool = ix.cards[f.id] || [];
        else if (f && f.type === 'card') pool = ix.card[f.id] ? [ix.card[f.id]] : [];
        else { const sel = new Set(selectedTracks()); pool = lib.cards.filter((c) => sel.has(c.track)); }
        deck = pool.filter((c) => {
            const s = state.cards[c.id];
            if (state.filter === 'unknown') return s !== 'known';
            if (state.filter === 'review') return s === 'review';
            return true;
        });
        if (state.shuffle) {
            for (let i = deck.length - 1; i > 0; i--) {
                const j = Math.floor(Math.random() * (i + 1));
                [deck[i], deck[j]] = [deck[j], deck[i]];
            }
        }
        pos = 0;
        revealed = false;
        finished = false;
        score = { got: 0, missed: 0, missedIds: [] };
    }
    function moveCard(delta) {
        if (!deck.length || finished) return;
        const next = pos + delta;
        if (next < 0) return;
        if (next >= deck.length) {
            if (state.cardMode === 'test') finished = true;
            else return;
        } else pos = next;
        revealed = false;
        render();
    }
    function answer(got) {
        if (state.cardMode !== 'test' || !revealed || finished) return;
        const c = deck[pos];
        if (got) { score.got++; state.cards[c.id] = 'known'; } else { score.missed++; score.missedIds.push(c.id); state.cards[c.id] = 'review'; }
        save();
        if (pos + 1 >= deck.length) finished = true; else pos++;
        revealed = false;
        render();
    }
    function mark(kind) {
        const c = deck[pos];
        if (!c || state.cardMode !== 'learn') return;
        if (state.cards[c.id] === kind) delete state.cards[c.id]; else state.cards[c.id] = kind;
        save();
        render();
    }
    function reveal() {
        if (state.cardMode !== 'test' || revealed || finished || !deck.length) return;
        revealed = true;
        render();
    }

    function cardHTML() {
        const modes = `<div class="segmented mini">${[['learn', 'Learn'], ['test', 'Test']].map(([v, t]) =>
            `<button type="button" data-act="mode" data-mode="${v}" class="${state.cardMode === v ? 'on' : ''}">${t}</button>`).join('')}</div>`;
        const focus = state.focus ? `<div class="focus"><span>Cards from <strong>${esc(focusLabel())}</strong></span><button type="button" data-act="unfocus">All selected tracks</button></div>` : '';
        if (!deck.length) {
            return `<div class="cards-col">${modes}${focus}<div class="card empty" id="card">
                <p>No cards match. Choose tracks in the ☰ menu, or show all cards instead of a filtered set.</p>
                <button type="button" class="btn primary" data-act="drawer">Choose tracks</button></div></div>`;
        }
        if (finished) {
            const total = score.got + score.missed;
            const pct = Math.round((score.got / deck.length) * 100);
            return `<div class="cards-col">${modes}${focus}<div class="card flash summary" id="card">
                <div class="big">${score.got} / ${total}</div>
                <p>${pct}% of ${deck.length} cards. ${score.missed ? `The ${score.missed} you missed are marked for review.` : 'Every card answered is marked known.'}</p>
                <div class="stack">
                    ${score.missed ? `<button type="button" class="btn primary" data-act="retest">Retest the ${score.missed} missed</button>` : ''}
                    <button type="button" class="btn" data-act="restart">Start a new test</button>
                </div></div></div>`;
        }
        const c = deck[pos];
        const test = state.cardMode === 'test';
        const m = state.cards[c.id];
        const showA = !test || revealed;
        const lesson = c.lesson && ix.lesson[c.lesson];
        return `<div class="cards-col">${modes}${focus}
            <article class="card flash${test && revealed ? ' flipped' : ''}" id="card" style="--tc:${esc((ix.track[c.track] || {}).color || 'var(--accent)')}" ${test && !revealed ? 'data-act="reveal"' : ''}>
            <div class="badges"><span class="label">${esc(trackTitle(c.track))}${c.label ? ' · ' + esc(c.label) : ''}</span>${m ? `<span class="tag ${m}">${m === 'known' ? 'Known' : 'Review'}</span>` : ''}</div>
            <div class="q content">${c.front}</div>
            ${showA ? `<div class="a content">${c.back}</div>${lesson ? `<p class="fine"><a href="#lesson/${esc(lesson.id)}">📖 ${esc(lesson.title)}</a></p>` : ''}`
                : '<div class="hint">Recall the answer, then tap the card or press Space.</div>'}
        </article></div>`;
    }

    // ---- code list ----

    function codeListHTML() {
        const f = state.codeFilter;
        const sec = state.codeSection;
        const filters = [['all', 'All'], ['todo', 'To do'], ['solved', 'Solved']].map(([v, t]) =>
            `<button type="button" data-act="code-filter" data-v="${v}" class="${f === v ? 'on' : ''}">${t}</button>`).join('');
        const groups = lib.tracks.filter((t) => ix.problems[t.id].length).map((t) => {
            const secs = t.sections.filter((s) => s.problems.length && (!sec || sec === s.id)).map((s) => {
                const rows = s.problems.filter((p) => (f === 'all') || (f === 'solved' ? state.solved[p.id] : !state.solved[p.id]))
                    .map((p) => {
                        const st = state.solved[p.id] ? 'solved' : state.attempts[p.id] ? 'tried' : '';
                        return `<a class="row" href="#problem/${esc(p.id)}">
                            <span class="dot ${st}">${st === 'solved' ? '✓' : st === 'tried' ? '◐' : '○'}</span>
                            <span class="grow">${esc(p.title)}<small>${p.tags.slice(0, 3).map(esc).join(' · ')}${p.needs.length ? ' · ' + p.needs.join(', ') : ''}</small></span>
                            <span class="chip ${esc(p.difficulty.toLowerCase())}">${esc(p.difficulty)}</span></a>`;
                    }).join('');
                return rows ? `<h4>${esc(s.title)}</h4><div class="panel">${rows}</div>` : '';
            }).join('');
            return secs ? `<h3 class="group-title" style="--tc:${esc(t.color || 'var(--accent)')}">${esc(t.title)}</h3>${secs}` : '';
        }).join('');
        return `<article class="card page" id="card">
            <div class="panel"><a class="row" href="#playground"><span class="ico">🧪</span><span class="grow">Playground<small>Write and run any Python: algorithms, pandas / NumPy batch jobs, streaming generators</small></span><span class="chev">›</span></a></div>
            <div class="segmented mini filter">${filters}</div>
            ${sec ? `<div class="focus"><span>Only <strong>${esc(sectionTitle(sec))}</strong></span><button type="button" data-act="code-all">All problems</button></div>` : ''}
            ${groups || '<p class="fine">No problems match this filter.</p>'}
        </article>`;
    }

    // ---- problem ----

    function harness(code, tests) {
        return `${code.replace(/\s+$/, '')}\n\n\nimport dc as _dc\n_dc.run_tests(${JSON.stringify(tests)}, globals())\n`;
    }

    function problemHTML(p) {
        const chips = [];
        if (p.difficulty) chips.push(`<span class="chip ${esc(p.difficulty.toLowerCase())}">${esc(p.difficulty)}</span>`);
        p.tags.forEach((t) => chips.push(`<span class="chip">${esc(t)}</span>`));
        if (p.leetcode) chips.push(`<a class="chip" href="https://leetcode.com/problemset/?search=${encodeURIComponent(p.leetcode)}" target="_blank" rel="noopener">LeetCode ${esc(p.leetcode)}</a>`);
        if (p.source) chips.push(`<span class="chip">${esc(p.source)}</span>`);
        if (p.needs.length) chips.push(`<span class="chip">uses ${esc(p.needs.join(', '))}</span>`);
        return `<article class="card page problem-page" id="card">
            <div class="prob-grid">
                <section class="prob-prompt">
                    <p class="kicker">${esc(trackTitle(p.track))} · ${esc(sectionTitle(p.section))}</p>
                    <h1>${state.solved[p.id] ? '<span class="ok">✓</span> ' : ''}${esc(p.title)}</h1>
                    <div class="chips">${chips.join('')}</div>
                    <div class="content">${p.prompt}</div>
                    <details class="tests"><summary>Tests</summary><div class="content"><pre><code class="language-python">${esc(p.tests)}</code></pre></div></details>
                    <div id="solution-box"></div>
                </section>
                <section class="prob-work">
                    ${workbenchHTML('solution.py', `<button type="button" class="link" data-act="reset-code">Reset</button>`)}
                </section>
            </div>
        </article>`;
    }

    function workbenchHTML(name, tools) {
        return `<div class="editor-bar"><span class="file">${esc(name)}</span><span class="grow"></span>${tools}
                <button type="button" class="link" data-act="copy-code">Copy</button></div>
            <div id="editor-host"></div>
            <div class="console-wrap">
                <div class="console-head"><span id="run-status">Ready · ⌘/Ctrl-Enter runs</span><button type="button" class="link" data-act="clear-console">Clear</button></div>
                <pre class="console" id="console" aria-live="polite"></pre>
            </div>`;
    }

    function mountEditor(value, onChange) {
        editor = window.DCEditor.create($('#editor-host'), { value, onChange, onRun: runCurrent });
        editor.textarea.addEventListener('focus', () => showKeybar(true));
        editor.textarea.addEventListener('blur', () => setTimeout(() => showKeybar(document.activeElement === (editor && editor.textarea)), 150));
    }

    function mountProblem(p) {
        mountEditor(state.code[p.id] ?? p.starter, (v) => { state.code[p.id] = v; saveSoon(); });
        const last = runner.lastOutput[p.id];
        if (last) { $('#console').innerHTML = last.html; $('#run-status').innerHTML = last.status; }
    }

    function showSolution(p) {
        if (!confirm('Show the reference solution? Try for a while first: struggling is where the learning happens.')) return;
        $('#solution-box').innerHTML = `<details class="solution" open><summary>Reference solution</summary><div class="content">
            <pre><code class="language-python">${esc(p.solution)}</code></pre></div>
            <button type="button" class="btn" data-act="load-solution">Load into the editor</button></details>`;
        window.DCRender.renderAll($('#solution-box'));
    }

    function stepProblem(delta) {
        const ps = ix.orderedProblems;
        const next = ps[ps.indexOf(ix.problem[route.id]) + delta];
        if (next) go(`#problem/${next.id}`);
    }

    // ---- playground ----

    function pgItems() {
        const snippets = Object.entries(state.snippets).sort((a, b) => b[1].at - a[1].at);
        return { snippets, templates: lib.playground };
    }
    function pgTitle(id) {
        if (id === 'scratch') return 'Scratch';
        if (state.snippets[id]) return state.snippets[id].title;
        return 'Scratch';
    }
    function playgroundHTML() {
        const cur = state.snippets[state.pgCurrent] ? state.pgCurrent : 'scratch';
        const { snippets, templates } = pgItems();
        const opts = [`<option value="scratch" ${cur === 'scratch' ? 'selected' : ''}>Scratch</option>`]
            .concat(snippets.length ? [`<optgroup label="Saved">${snippets.map(([id, s]) => `<option value="${esc(id)}" ${cur === id ? 'selected' : ''}>${esc(s.title)}</option>`).join('')}</optgroup>`] : [])
            .concat([`<optgroup label="Start from a template">${templates.map((t) => `<option value="tpl:${esc(t.id)}">${esc(t.title)}</option>`).join('')}</optgroup>`]);
        return `<article class="card page problem-page" id="card">
            <div class="pg-bar">
                <select id="pg-select" aria-label="Snippet">${opts.join('')}</select>
                <button type="button" class="link" data-act="pg-save">${cur === 'scratch' ? 'Save as…' : 'Rename'}</button>
                ${cur !== 'scratch' ? '<button type="button" class="link danger" data-act="pg-delete">Delete</button>' : ''}
            </div>
            <div class="prob-work">${workbenchHTML(cur === 'scratch' ? 'scratch.py' : pgTitle(cur), '')}</div>
            <details class="stdin"><summary>Input (stdin)</summary><textarea id="stdin" rows="3" spellcheck="false" placeholder="Text for input() and sys.stdin">${esc(state.stdin)}</textarea></details>
            <p class="fine">Python 3.12 in your browser (Pyodide): standard library plus numpy, pandas, scipy, scikit-learn, networkx and sqlite3, loaded on first import. <code>from dc import stream, clickstream, ticks, sensor, orders, table, check</code> gives you data sources and test helpers.</p>
        </article>`;
    }
    function mountPlayground() {
        const cur = state.snippets[state.pgCurrent] ? state.pgCurrent : 'scratch';
        if (state.scratch == null) state.scratch = lib.playground[0] ? lib.playground[0].code : '';
        const value = cur === 'scratch' ? state.scratch : state.snippets[cur].code;
        mountEditor(value, (v) => {
            if (cur === 'scratch') state.scratch = v;
            else { state.snippets[cur].code = v; state.snippets[cur].at = Date.now(); }
            saveSoon();
        });
        const last = runner.lastOutput['pg:' + cur];
        if (last) { $('#console').innerHTML = last.html; $('#run-status').innerHTML = last.status; }
    }
    function isTemplateOrEmpty(code) {
        return !code || !code.trim() || lib.playground.some((t) => t.code === code);
    }
    function keepScratch() {
        if (isTemplateOrEmpty(state.scratch)) return;
        const id = 's' + Date.now().toString(36);
        state.snippets[id] = { title: 'Scratch ' + new Date().toLocaleString(), code: state.scratch, at: Date.now() };
        toast('Your previous scratch was saved');
    }
    function tryInPlayground(code) {
        keepScratch();
        state.scratch = code;
        state.pgCurrent = 'scratch';
        save();
        go('#playground');
    }

    // ---- runner ----

    const runner = {
        worker: null,
        run: null,
        seq: 0,
        lastOutput: {},
        ensure() {
            if (!this.worker) {
                const base = new URLSearchParams(location.search).get('pyodide');
                this.worker = new Worker(base ? `py-worker.js?base=${encodeURIComponent(new URL(base, location.href).href)}` : 'py-worker.js');
                this.worker.onmessage = (e) => this.onMessage(e.data);
                this.worker.onerror = (e) => { if (this.run) this.append(`Worker error: ${e.message}\n`, 'err'); };
                this.worker.postMessage({ type: 'helpers', code: lib.helpers });
            }
            return this.worker;
        },
        warm() { if (!this.worker) this.ensure().postMessage({ type: 'warm' }); },
        start(code, key, problem, scan = '') {
            if (this.run) return;
            const id = ++this.seq;
            this.run = { id, key, problem, t0: performance.now(), out: '', result: null, size: 0 };
            $('#console').innerHTML = '';
            $('.console-wrap').scrollIntoView({ behavior: 'smooth', block: 'nearest' });
            this.tick = setInterval(() => this.status(`Running… ${((performance.now() - this.run.t0) / 1000).toFixed(1)} s`), 100);
            this.status('Starting…');
            this.ensure().postMessage({ type: 'run', id, code, scan, stdin: problem ? '' : state.stdin, helpers: lib.helpers });
            renderActions();
        },
        stop() {
            if (!this.run) return;
            this.worker.terminate();
            this.worker = null;
            this.finish({ ok: false, stopped: true, ms: performance.now() - this.run.t0 });
        },
        status(text) { const el = $('#run-status'); if (el && this.run && this.isVisible()) el.innerHTML = text; },
        isVisible() {
            return this.run && ((route.name === 'problem' && this.run.key === route.id)
                || (route.name === 'playground' && this.run.key === 'pg:' + (state.snippets[state.pgCurrent] ? state.pgCurrent : 'scratch')));
        },
        append(text, cls) {
            const r = this.run;
            if (!r) return;
            text = text.replace(/^__DC_RESULT__ (\{.*\})\n?/m, (_, j) => { try { r.result = JSON.parse(j); } catch { /* ignore */ } return ''; });
            if (!text) return;
            r.size += text.length;
            const el = $('#console');
            if (!el || !this.isVisible()) { r.out += cls === 'err' ? `<span class="err">${esc(text)}</span>` : esc(text); return; }
            const atBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 40;
            const node = cls === 'err' ? Object.assign(document.createElement('span'), { className: 'err', textContent: text }) : document.createTextNode(text);
            el.appendChild(node);
            while (r.size > MAX_CONSOLE && el.firstChild) { r.size -= el.firstChild.textContent.length; el.removeChild(el.firstChild); }
            if (atBottom) el.scrollTop = el.scrollHeight;
        },
        onMessage(m) {
            if (m.type === 'status' && this.run) this.status(esc(m.text));
            if (!this.run || (m.id && m.id !== this.run.id)) return;
            if (m.type === 'start') this.status('Running…');
            else if (m.type === 'out') this.append(m.text, 'out');
            else if (m.type === 'err') this.append(m.text, 'err');
            else if (m.type === 'done') this.finish(m);
        },
        finish(m) {
            const r = this.run;
            clearInterval(this.tick);
            this.run = null;
            const secs = `${(m.ms / 1000).toFixed(2)} s`;
            let status;
            if (m.stopped) status = `<span class="bad">■ Stopped</span> after ${secs}`;
            else if (r.result && r.result.total) {
                const all = r.result.passed === r.result.total;
                status = `<span class="${all ? 'ok' : 'bad'}">${all ? '✓' : '✗'} ${r.result.passed}/${r.result.total} tests passed</span> · ${secs}`;
            } else status = m.ok ? `<span class="ok">✓ Finished</span> in ${secs}` : `<span class="bad">✗ Error</span> after ${secs}`;
            if (r.problem && r.result) {
                state.attempts[r.key] = { passed: r.result.passed, total: r.result.total, at: Date.now() };
                if (r.result.total && r.result.passed === r.result.total && !state.solved[r.key]) {
                    state.solved[r.key] = { at: Date.now() };
                    toast('Solved ✓');
                }
                save();
            }
            const el = $('#console');
            if (this.isVisibleKey(r.key)) {
                $('#run-status').innerHTML = status;
                if (r.out) el.insertAdjacentHTML('beforeend', r.out);
                if (!el.textContent) el.innerHTML = '<span class="muted">(no output)</span>';
                this.lastOutput[r.key] = { html: el.innerHTML, status };
            } else this.lastOutput[r.key] = { html: r.out, status };
            renderStatus();
            renderActions();
        },
        isVisibleKey(key) {
            return (route.name === 'problem' && key === route.id)
                || (route.name === 'playground' && key === 'pg:' + (state.snippets[state.pgCurrent] ? state.pgCurrent : 'scratch'));
        },
    };

    function runCurrent() {
        if (!editor || runner.run) return;
        if (route.name === 'problem') {
            const p = ix.problem[route.id];
            runner.start(harness(editor.value, p.tests), p.id, true, p.tests);
        } else if (route.name === 'playground') {
            const cur = state.snippets[state.pgCurrent] ? state.pgCurrent : 'scratch';
            runner.start(editor.value, 'pg:' + cur, false);
        }
    }

    // ---- progress ----

    function progressHTML() {
        const rows = lib.tracks.map((t) => {
            const c = counts(t);
            const part = (done, total, label) => (total ? `<span class="mini-stat">${label} ${done}/${total} ${bar(done, total)}</span>` : '');
            return `<a class="row col" href="#track/${esc(t.id)}" style="--tc:${esc(t.color || 'var(--accent)')}">
                <span class="grow"><b>${esc(t.title)}</b></span>
                <span class="stats">${part(c.read, c.lessons, 'read')}${part(c.known, c.cards, 'known')}${part(c.solved, c.problems, 'solved')}</span></a>`;
        }).join('');
        const solved = Object.keys(state.solved).filter((id) => ix.problem[id]).length;
        const known = Object.values(state.cards).filter((v) => v === 'known').length;
        const review = Object.values(state.cards).filter((v) => v === 'review').length;
        const recent = Object.entries(state.solved).filter(([id]) => ix.problem[id]).sort((a, b) => b[1].at - a[1].at).slice(0, 8)
            .map(([id, s]) => `<a class="row" href="#problem/${esc(id)}"><span class="dot solved">✓</span><span class="grow">${esc(ix.problem[id].title)}<small>${new Date(s.at).toLocaleDateString()}</small></span></a>`).join('');
        return `<article class="card page" id="card">
            <h1>Progress</h1>
            <div class="kpis">
                <div class="kpi"><b>${solved}</b><span>problems solved</span></div>
                <div class="kpi"><b>${known}</b><span>cards known</span></div>
                <div class="kpi"><b>${review}</b><span>cards to review</span></div>
                <div class="kpi"><b>${Object.keys(state.read).length}</b><span>lessons read</span></div>
            </div>
            <h4>Tracks</h4><div class="panel">${rows}</div>
            ${recent ? `<h4>Recently solved</h4><div class="panel">${recent}</div>` : ''}
            <p class="fine">Progress, your code and saved snippets stay in this browser. Export them from here or the ☰ menu to move them to another device or the Mac app.</p>
        </article>`;
    }

    // ---- actions bar ----

    function renderActions() {
        const a = $('#actions');
        const nav = (act, d, off, label) => `<button type="button" class="btn nav" data-act="${act}" data-delta="${d}" aria-label="${label}" ${off ? 'disabled' : ''}>${d < 0 ? '‹' : '›'}</button>`;
        const r = route;
        if (r.name === 'learn') {
            a.innerHTML = '<button type="button" class="btn" data-act="view" data-view="cards">Practise cards</button><button type="button" class="btn primary" data-act="next-problem">Solve a problem ›</button>';
        } else if (r.name === 'track') {
            const n = ix.cards[r.id].length;
            const p = ix.problems[r.id].length;
            a.innerHTML = `<button type="button" class="btn" data-act="focus" data-type="track" data-id="${esc(r.id)}" ${n ? '' : 'disabled'}>Practise ${n} cards</button>`
                + `<button type="button" class="btn primary" data-act="next-problem" data-track="${esc(r.id)}" ${p ? '' : 'disabled'}>${p} problems ›</button>`;
        } else if (r.name === 'lesson') {
            const l = ix.lesson[r.id];
            const ls = ix.lessons[l.track];
            const i = ls.indexOf(l);
            const n = cardsForLesson(l.id).length;
            a.innerHTML = nav('lesson', -1, i <= 0, 'Previous lesson')
                + (n ? `<button type="button" class="btn" data-act="focus" data-type="lesson" data-id="${esc(l.id)}">${n} cards</button>` : '')
                + `<button type="button" class="btn ${state.read[l.id] ? 'on-known' : 'primary'}" data-act="toggle-read">${state.read[l.id] ? '✓ Read' : 'Mark read'}</button>`
                + nav('lesson', 1, i >= ls.length - 1, 'Next lesson');
        } else if (r.name === 'cards') {
            if (!deck.length || finished) { a.innerHTML = ''; return; }
            const c = deck[pos];
            if (state.cardMode === 'learn') {
                const m = state.cards[c.id];
                a.innerHTML = nav('card', -1, pos <= 0, 'Previous card')
                    + `<button type="button" class="btn${m === 'known' ? ' on-known' : ''}" data-act="known">${m === 'known' ? '✓ Known' : 'Known'}</button>`
                    + `<button type="button" class="btn${m === 'review' ? ' on-review' : ''}" data-act="review">${m === 'review' ? '⚑ Review' : 'Review'}</button>`
                    + nav('card', 1, pos >= deck.length - 1, 'Next card');
            } else if (!revealed) {
                a.innerHTML = nav('card', -1, pos <= 0, 'Previous card') + '<button type="button" class="btn primary" data-act="reveal">Show answer</button>' + nav('card', 1, false, 'Skip');
            } else {
                a.innerHTML = nav('card', -1, pos <= 0, 'Previous card')
                    + '<button type="button" class="btn bad" data-act="missed">✗ Missed</button><button type="button" class="btn good" data-act="got">✓ Got it</button>'
                    + nav('card', 1, false, 'Skip');
            }
        } else if (r.name === 'code') {
            a.innerHTML = '<a class="btn" href="#playground">🧪 Playground</a><button type="button" class="btn primary" data-act="next-problem">Next unsolved ›</button>';
        } else if (r.name === 'problem') {
            const ps = ix.orderedProblems;
            const i = ps.indexOf(ix.problem[r.id]);
            a.innerHTML = nav('problem', -1, i <= 0, 'Previous problem')
                + (runner.run ? '<button type="button" class="btn bad" data-act="stop">■ Stop</button>' : '<button type="button" class="btn primary" data-act="run">▶ Run tests</button>')
                + '<button type="button" class="btn" data-act="solution">Solution</button>'
                + nav('problem', 1, i >= ps.length - 1, 'Next problem');
        } else if (r.name === 'playground') {
            a.innerHTML = (runner.run ? '<button type="button" class="btn bad" data-act="stop">■ Stop</button>' : '<button type="button" class="btn primary" data-act="run">▶ Run</button>')
                + '<button type="button" class="btn" data-act="clear-console">Clear output</button>';
        } else if (r.name === 'progress') {
            a.innerHTML = '<button type="button" class="btn" data-act="export">⤓ Export</button><button type="button" class="btn" data-act="import">⤒ Import</button>';
        } else a.innerHTML = '';
    }

    // ---- key bar for coding on a phone ----

    const KEYS = [['⇥', 'indent'], ['⇤', 'dedent'], ['←', 'left'], ['→', 'right'], ['(', '('], [')', ')'], ['[', '['], [']', ']'],
        ['{', '{'], ['}', '}'], [':', ':'], ['=', '='], ['_', '_'], ['"', '"'], ["'", "'"], ['#', '#'], [',', ','], ['.', '.'],
        ['<', '<'], ['>', '>'], ['+', '+'], ['-', '-'], ['*', '*'], ['/', '/'], ['%', '%'], ['!', '!']];
    function showKeybar(on) {
        const kb = $('#keybar');
        const show = on && coarse;
        if (kb.hidden === !show) return;
        kb.hidden = !show;
        document.body.classList.toggle('editing', show);
        if (show && !kb.innerHTML) {
            kb.innerHTML = KEYS.map(([label, k]) => `<button type="button" data-key="${esc(k)}">${esc(label)}</button>`).join('');
        }
    }
    $('#keybar').addEventListener('pointerdown', (e) => {
        const b = e.target.closest('button');
        if (!b || !editor) return;
        e.preventDefault();
        const k = b.dataset.key;
        if (k === 'indent') editor.indent();
        else if (k === 'dedent') editor.dedent();
        else if (k === 'left') editor.move(-1);
        else if (k === 'right') editor.move(1);
        else editor.insert(k);
    });

    // ---- drawer ----

    function openDrawer() {
        renderDrawer();
        $('#drawer').classList.add('open');
        $('#drawer').setAttribute('aria-hidden', 'false');
        $('#backdrop').hidden = false;
    }
    function closeDrawer() {
        $('#drawer').classList.remove('open');
        $('#drawer').setAttribute('aria-hidden', 'true');
        $('#backdrop').hidden = true;
    }
    function renderDrawer() {
        const body = $('#drawer-body');
        const scroll = body.scrollTop;
        const sel = new Set(selectedTracks());
        const rows = lib.tracks.map((t) => `<div class="row">
                <input type="checkbox" data-sel="${esc(t.id)}" ${sel.has(t.id) ? 'checked' : ''} aria-label="Include ${esc(t.title)} in Cards">
                <a class="open" href="#track/${esc(t.id)}"><span class="swatch" style="background:${esc(t.color || 'var(--accent)')}"></span>
                <span class="grow">${esc(t.title)}<small>${ix.cards[t.id].length} cards · ${ix.lessons[t.id].length} lessons · ${ix.problems[t.id].length} problems</small></span></a></div>`).join('');
        const filters = [['all', 'All cards'], ['unknown', 'Not yet known'], ['review', 'Review only']]
            .map(([v, t]) => `<option value="${v}" ${state.filter === v ? 'selected' : ''}>${t}</option>`).join('');
        body.innerHTML = `<h4>Tracks · tick to include in Cards</h4>
            <div class="panel"><div class="links"><button type="button" data-act="sel-all">Select all</button><button type="button" data-act="sel-none">Clear</button></div>${rows}</div>
            <h4>Cards</h4>
            <div class="panel">
                <div class="row"><span class="grow">Practise</span><select id="card-filter" aria-label="Which cards">${filters}</select></div>
                <div class="row"><input type="checkbox" id="shuffle" ${state.shuffle ? 'checked' : ''}><label for="shuffle">Shuffle</label></div>
                <button type="button" class="menu-btn" data-act="restart">↺ Restart the deck</button>
            </div>
            <h4>More</h4>
            <div class="panel">
                <a class="menu-btn" href="#playground">🧪 Playground</a>
                <a class="menu-btn" href="#search">🔎 Search</a>
                <button type="button" class="menu-btn" data-act="print">🖨 Print this page</button>
                <button type="button" class="menu-btn" data-act="export">⤓ Export progress</button>
                <button type="button" class="menu-btn" data-act="import">⤒ Import progress</button>
                <button type="button" class="menu-btn" data-act="help">⌨ Keyboard shortcuts</button>
                <a class="menu-btn" href="https://github.com/venkatacrc/datacom" target="_blank" rel="noopener">↗ Repository</a>
                <button type="button" class="menu-btn danger" data-act="reset">Reset progress</button>
            </div>`;
        body.scrollTop = scroll;
        const n = lib.cards.filter((c) => sel.has(c.track)).length;
        $('#drawer-foot').textContent = `${sel.size} tracks · ${n} cards · library ${lib.version}`;
    }
    function setSelected(ids) {
        const all = lib.tracks.map((t) => t.id);
        state.selected = ids.length === all.length ? null : all.filter((x) => ids.includes(x));
        state.focus = null;
        save();
        if (route.name === 'cards') buildDeck();
        render();
    }

    // ---- export / import ----

    function exportProgress() {
        const data = { app: 'datacom', version: 1, exported: new Date().toISOString(), state };
        const blob = new Blob([JSON.stringify(data, null, 1)], { type: 'application/json' });
        const a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = `datacom-progress-${new Date().toISOString().slice(0, 10)}.json`;
        a.click();
        setTimeout(() => URL.revokeObjectURL(a.href), 2000);
    }
    function importProgress(file) {
        const reader = new FileReader();
        reader.onload = () => {
            try {
                const data = JSON.parse(reader.result);
                if (data.app !== 'datacom') throw new Error('not a Datacom progress file');
                const incoming = data.state || {};
                // Merge so importing from another device never loses local work.
                ['cards', 'read', 'attempts', 'code', 'snippets'].forEach((k) => { state[k] = Object.assign({}, state[k], incoming[k]); });
                state.solved = Object.assign({}, incoming.solved, state.solved);
                save();
                render();
                toast('Progress imported');
            } catch (err) { alert('Import failed: ' + err.message); }
        };
        reader.readAsText(file);
    }

    // ---- events ----

    function act(el, e) {
        const d = el.dataset;
        switch (d.act) {
            case 'view': {
                const target = { learn: '#learn', cards: '#cards', code: '#code', progress: '#progress' }[d.view];
                if (d.view === 'cards') state.focus = state.focus && route.name === 'cards' ? state.focus : null;
                go(target);
                break;
            }
            case 'mode': state.cardMode = d.mode; save(); buildDeck(); render(); break;
            case 'lesson': stepLesson(Number(d.delta)); break;
            case 'card': moveCard(Number(d.delta)); break;
            case 'problem': stepProblem(Number(d.delta)); break;
            case 'focus': state.focus = { type: d.type, id: d.id }; save(); buildDeck(); go('#cards'); if (route.name === 'cards') render(); break;
            case 'unfocus': state.focus = null; save(); buildDeck(); render(); break;
            case 'reveal': reveal(); break;
            case 'got': answer(true); break;
            case 'missed': answer(false); break;
            case 'known': mark('known'); break;
            case 'review': mark('review'); break;
            case 'retest': {
                const ids = new Set(score.missedIds);
                deck = deck.filter((c) => ids.has(c.id));
                pos = 0; revealed = false; finished = false; score = { got: 0, missed: 0, missedIds: [] };
                render();
                break;
            }
            case 'restart': buildDeck(); closeDrawer(); render(); break;
            case 'toggle-read': {
                const id = route.id;
                if (state.read[id]) delete state.read[id]; else state.read[id] = Date.now();
                save();
                renderActions();
                renderStatus();
                if (state.read[id]) setTimeout(() => stepLesson(1), 250);
                break;
            }
            case 'code-filter': state.codeFilter = d.v; save(); render(); break;
            case 'code-section': state.codeSection = d.id; save(); go('#code'); break;
            case 'code-all': state.codeSection = null; save(); render(); break;
            case 'next-problem': {
                const pool = d.track ? ix.problems[d.track] : ix.orderedProblems;
                const p = pool.find((x) => !state.solved[x.id]) || pool[0];
                if (p) go(`#problem/${p.id}`);
                break;
            }
            case 'run': runCurrent(); break;
            case 'stop': runner.stop(); break;
            case 'clear-console': { const c = $('#console'); if (c) c.innerHTML = ''; break; }
            case 'reset-code': {
                const p = ix.problem[route.id];
                if (editor && confirm('Replace your code with the starter code?')) { editor.setValue(p.starter); delete state.code[p.id]; save(); }
                break;
            }
            case 'copy-code': if (editor) window.DCRender.copyText(editor.value, el); break;
            case 'solution': showSolution(ix.problem[route.id]); break;
            case 'load-solution': {
                const p = ix.problem[route.id];
                if (editor && confirm('Replace your code with the reference solution?')) { editor.setValue(p.solution); state.code[p.id] = p.solution; save(); }
                break;
            }
            case 'pg-save': {
                const cur = state.snippets[state.pgCurrent] ? state.pgCurrent : 'scratch';
                const name = prompt(cur === 'scratch' ? 'Save this code as:' : 'Rename to:', cur === 'scratch' ? '' : state.snippets[cur].title);
                if (!name) break;
                if (cur === 'scratch') {
                    const id = 's' + Date.now().toString(36);
                    state.snippets[id] = { title: name, code: editor ? editor.value : state.scratch, at: Date.now() };
                    state.pgCurrent = id;
                } else state.snippets[cur].title = name;
                save();
                render();
                break;
            }
            case 'pg-delete': {
                const cur = state.pgCurrent;
                if (state.snippets[cur] && confirm(`Delete “${state.snippets[cur].title}”?`)) {
                    delete state.snippets[cur];
                    state.pgCurrent = 'scratch';
                    save();
                    render();
                }
                break;
            }
            case 'drawer': openDrawer(); break;
            case 'sel-all': setSelected(lib.tracks.map((t) => t.id)); break;
            case 'sel-none': setSelected([]); break;
            case 'print': closeDrawer(); setTimeout(() => window.print(), 250); break;
            case 'export': exportProgress(); break;
            case 'import': $('#import-file').click(); break;
            case 'help': closeDrawer(); $('#help-dialog').showModal(); break;
            case 'reset':
                if (!confirm('Clear card marks, read lessons and solved problems in this browser? Your code and snippets are kept.')) return;
                Object.assign(state, { cards: {}, read: {}, solved: {}, attempts: {} });
                save();
                buildDeck();
                render();
                toast('Progress cleared');
                break;
            default: break;
        }
        if (e) e.preventDefault();
    }

    document.addEventListener('click', (e) => {
        const a = e.target.closest && e.target.closest('a[href^="#"]');
        if (a && !ROUTES.test(a.getAttribute('href').slice(1))) {
            // In-page anchors inside lessons: scroll instead of routing.
            e.preventDefault();
            const id = decodeURIComponent(a.getAttribute('href').slice(1));
            const target = id && document.getElementById(id);
            if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
            return;
        }
        if (a && $('#drawer').classList.contains('open')) closeDrawer();
        const el = e.target.closest ? e.target.closest('[data-act]') : null;
        if (!el || el.disabled) return;
        if (el.id === 'card' && e.target.closest('a, button, summary')) return;
        act(el, e);
    });

    document.addEventListener('change', (e) => {
        const t = e.target;
        if (t.dataset && t.dataset.sel) {
            const set = new Set(selectedTracks());
            if (t.checked) set.add(t.dataset.sel); else set.delete(t.dataset.sel);
            setSelected([...set]);
        } else if (t.id === 'card-filter') { state.filter = t.value; save(); buildDeck(); render(); }
        else if (t.id === 'shuffle') { state.shuffle = t.checked; save(); buildDeck(); render(); }
        else if (t.id === 'import-file' && t.files && t.files[0]) { importProgress(t.files[0]); t.value = ''; }
        else if (t.id === 'pg-select') {
            const v = t.value;
            if (v.startsWith('tpl:')) {
                const tpl = ix.template[v.slice(4)];
                keepScratch();
                state.scratch = tpl.code;
                state.pgCurrent = 'scratch';
            } else state.pgCurrent = v;
            save();
            render();
        }
    });
    document.addEventListener('input', (e) => {
        if (e.target.id === 'search-input') renderSearchResults(e.target.value);
        if (e.target.id === 'stdin') { state.stdin = e.target.value; saveSoon(); }
    });

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && $('#drawer').classList.contains('open')) { closeDrawer(); return; }
        if ((e.metaKey || e.ctrlKey) && e.key === 'Enter' && editor) { e.preventDefault(); runCurrent(); return; }
        if (e.target.matches && e.target.matches('input, textarea, select')) return;
        if (e.metaKey || e.ctrlKey || e.altKey) return;
        if (/^[1-4]$/.test(e.key)) { act({ dataset: { act: 'view', view: VIEWS[Number(e.key) - 1][0] } }); return; }
        if (e.key === '/') { e.preventDefault(); go('#search'); return; }
        const k = e.key.length === 1 ? e.key.toLowerCase() : e.key;
        if (route.name === 'cards') {
            const map = { ArrowLeft: () => moveCard(-1), ArrowRight: () => moveCard(1), ' ': reveal, g: () => answer(true), m: () => answer(false), k: () => mark('known'), r: () => mark('review') };
            if (map[k]) { e.preventDefault(); map[k](); }
        } else if (route.name === 'lesson' && (k === 'ArrowLeft' || k === 'ArrowRight')) stepLesson(k === 'ArrowRight' ? 1 : -1);
        else if (route.name === 'problem' && (k === 'ArrowLeft' || k === 'ArrowRight')) stepProblem(k === 'ArrowRight' ? 1 : -1);
    });

    $('#open-drawer').addEventListener('click', openDrawer);
    $('#close-drawer').addEventListener('click', closeDrawer);
    $('#backdrop').addEventListener('click', closeDrawer);
    $('#open-search').addEventListener('click', () => go('#search'));

    // Swipe lessons and cards left or right, as in Sloka Words.
    let x0 = null;
    let y0 = null;
    const stage = $('#stage');
    stage.addEventListener('touchstart', (e) => {
        if (!['cards', 'lesson'].includes(route.name) || e.target.closest('pre, table, input, select, textarea, .table-wrap, .katex-display, .tex.display')) { x0 = null; return; }
        x0 = e.touches[0].clientX;
        y0 = e.touches[0].clientY;
    }, { passive: true });
    stage.addEventListener('touchend', (e) => {
        if (x0 == null) return;
        const dx = e.changedTouches[0].clientX - x0;
        const dy = e.changedTouches[0].clientY - y0;
        x0 = null;
        if (Math.abs(dx) < 60 || Math.abs(dx) < Math.abs(dy) * 1.5) return;
        if (route.name === 'cards') moveCard(dx < 0 ? 1 : -1);
        else stepLesson(dx < 0 ? 1 : -1);
    }, { passive: true });

    // Keep the layout above the on-screen keyboard (iOS ignores interactive-widget).
    if (window.visualViewport) {
        const fit = () => document.documentElement.style.setProperty('--app-h', `${window.visualViewport.height}px`);
        window.visualViewport.addEventListener('resize', fit);
        fit();
    }

    // ---- boot ----

    window.addEventListener('hashchange', onRoute);
    fetch('library.json', { cache: 'no-cache' })
        .then((r) => { if (!r.ok) throw new Error(`HTTP ${r.status}`); return r.json(); })
        .then((l) => {
            lib = l;
            ix = index(l);
            if (!location.hash && state.lastRoute && state.lastRoute !== '#learn') history.replaceState(null, '', state.lastRoute);
            onRoute();
        })
        .catch((err) => {
            $('#stage').innerHTML = `<div class="card empty">Could not load library.json (${esc(err.message)}).<br>
                Serve the folder over HTTP: <code>python3 -m http.server -d web 8080</code></div>`;
        });

    if ('serviceWorker' in navigator && location.protocol.startsWith('http')) navigator.serviceWorker.register('sw.js').catch(() => {});
    window.__datacom = { get lib() { return lib; }, get state() { return state; }, runner, go };
})();
