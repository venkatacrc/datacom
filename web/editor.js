// A small Python editor: a transparent <textarea> over a highlighted <pre>, with line numbers,
// auto-indent, Tab / Shift-Tab, Cmd/Ctrl-/ to comment and Cmd/Ctrl-Enter to run.
// Edits go through execCommand('insertText') so the browser's undo stack keeps working.
(function () {
    'use strict';
    const INDENT = '    ';

    function create(host, { value = '', lang = 'python', onChange, onRun } = {}) {
        host.innerHTML = `<div class="editor">
            <div class="gutter" aria-hidden="true"><div class="nums"></div></div>
            <div class="pane">
                <pre class="hl" aria-hidden="true"><code></code></pre>
                <textarea class="ta" spellcheck="false" autocapitalize="off" autocomplete="off" autocorrect="off"
                    wrap="off" aria-label="Code editor"></textarea>
            </div></div>`;
        const ta = host.querySelector('textarea');
        const code = host.querySelector('.hl code');
        const pre = host.querySelector('.hl');
        const nums = host.querySelector('.nums');
        let lines = 0;
        let frame = 0;
        ta.value = value;

        function paint() {
            frame = 0;
            const text = ta.value;
            code.innerHTML = window.DCRender.highlight(text, lang) + (text.endsWith('\n') || !text ? ' ' : '');
            const n = text.split('\n').length;
            if (n !== lines) {
                lines = n;
                nums.textContent = Array.from({ length: n }, (_, i) => i + 1).join('\n');
            }
            sync();
        }
        function sync() {
            pre.scrollTop = ta.scrollTop;
            pre.scrollLeft = ta.scrollLeft;
            nums.style.transform = `translateY(${-ta.scrollTop}px)`;
        }
        function changed() {
            if (!frame) frame = requestAnimationFrame(paint);
            if (onChange) onChange(ta.value);
        }

        function insert(text) {
            ta.focus();
            if (!document.execCommand('insertText', false, text)) {
                ta.setRangeText(text, ta.selectionStart, ta.selectionEnd, 'end');
                changed();
            }
        }
        function lineStart(pos) { return ta.value.lastIndexOf('\n', pos - 1) + 1; }

        // Rewrites whole lines in the selection, keeping the selection over the same lines.
        function mapLines(fn) {
            const v = ta.value;
            const s = lineStart(ta.selectionStart);
            let e = ta.selectionEnd;
            if (e > s && v[e - 1] === '\n') e -= 1;
            const endNl = v.indexOf('\n', e);
            const end = endNl < 0 ? v.length : endNl;
            const block = v.slice(s, end).split('\n');
            const out = fn(block).join('\n');
            ta.setSelectionRange(s, end);
            insert(out);
            ta.setSelectionRange(s, s + out.length);
        }

        function indent(back) {
            const v = ta.value;
            const multi = v.slice(ta.selectionStart, ta.selectionEnd).includes('\n');
            if (!back && !multi) {
                const col = ta.selectionStart - lineStart(ta.selectionStart);
                insert(' '.repeat(4 - (col % 4)));
                return;
            }
            mapLines((ls) => ls.map((l) => (back ? l.replace(/^ {1,4}/, '') : (l.trim() ? INDENT + l : l))));
        }

        function toggleComment() {
            mapLines((ls) => {
                const filled = ls.filter((l) => l.trim());
                const all = filled.length && filled.every((l) => /^\s*#/.test(l));
                const pad = Math.min(...filled.map((l) => l.match(/^ */)[0].length));
                return ls.map((l) => {
                    if (!l.trim()) return l;
                    return all ? l.replace(/^(\s*)# ?/, '$1') : l.slice(0, pad) + '# ' + l.slice(pad);
                });
            });
        }

        function newline() {
            const v = ta.value;
            const s = lineStart(ta.selectionStart);
            const before = v.slice(s, ta.selectionStart);
            let pad = before.match(/^ */)[0];
            if (/[:([{]\s*$/.test(before)) pad += INDENT;
            else if (/^\s*(return|pass|break|continue|raise)\b/.test(before)) pad = pad.slice(0, Math.max(0, pad.length - 4));
            insert('\n' + pad);
        }

        function backspace(e) {
            if (ta.selectionStart !== ta.selectionEnd) return;
            const pos = ta.selectionStart;
            const before = ta.value.slice(lineStart(pos), pos);
            if (before.length && /^ +$/.test(before)) {
                const n = before.length % 4 || 4;
                e.preventDefault();
                ta.setSelectionRange(pos - n, pos);
                insert('');
            }
        }

        ta.addEventListener('input', changed);
        ta.addEventListener('scroll', sync, { passive: true });
        ta.addEventListener('keydown', (e) => {
            const mod = e.metaKey || e.ctrlKey;
            if (mod && e.key === 'Enter') { e.preventDefault(); if (onRun) onRun(); return; }
            if (mod && e.key === '/') { e.preventDefault(); toggleComment(); return; }
            if (e.key === 'Tab' && !mod && !e.altKey) { e.preventDefault(); indent(e.shiftKey); return; }
            if (e.key === 'Enter' && !mod && !e.shiftKey && !e.isComposing) { e.preventDefault(); newline(); return; }
            if (e.key === 'Backspace' && !mod) backspace(e);
            if (e.key === 'Escape') ta.blur();
        });

        paint();
        return {
            textarea: ta,
            get value() { return ta.value; },
            setValue(v) { ta.value = v; ta.scrollTop = 0; paint(); },
            focus() { ta.focus(); },
            insert,
            indent: () => indent(false),
            dedent: () => indent(true),
            move(delta) {
                ta.focus();
                const p = Math.max(0, Math.min(ta.value.length, ta.selectionStart + delta));
                ta.setSelectionRange(p, p);
            },
        };
    }

    window.DCEditor = { create };
})();
