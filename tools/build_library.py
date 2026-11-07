#!/usr/bin/env python3
"""Builds the Datacom library from the repos listed in sources.json.

Every source becomes lessons, flash cards and/or coding problems inside a track:

  problems     content/problems/**/*.md   coding problems (format below)
  playground   content/playground/*.py    starter files for the free-form playground
  algos        ~/code/algos               Markdown, HTML and .py notes, read live; quiz cards from test-mode.js
  deepmath     web/deck.json              notation and equation cards, one study sheet per topic
  systemlegos  web/deck.json              building blocks and design exercises
  gpukernels   web/course.json            lessons (write/run/measure/explain) and cards
  vllm         web/course.json            serving lessons and cards
  deck         web/deck.json              HSTU / NCP-GENL style decks (front + back blocks)
  labs         README.md files            lab READMEs as lessons, with a few generated cards

Sources marked "public": false (private repos) go into the Mac app only, unless --include-private.

Problem files: YAML-ish front matter (track, section), then one "## Title" per problem with an optional
"> difficulty: Medium | tags: heap | leetcode: 295" line, a Markdown prompt, and three fenced blocks
tagged ```python starter, ```python solution and ```python tests. Tests call check(actual, expected).

Usage: python3 tools/build_library.py [--include-private] [--web OUT] [--app OUT]
"""
from __future__ import annotations

import argparse
import datetime
import fnmatch
import hashlib
import html
import json
import posixpath
import re
import shutil
import subprocess
import sys
from pathlib import Path

from markdown_it import MarkdownIt

ROOT = Path(__file__).resolve().parent.parent
WEB_OUT = ROOT / "web" / "library.json"
APP_OUT = ROOT / "app" / "Sources" / "Datacom" / "Resources" / "library.json"

md = MarkdownIt("commonmark", {"html": True}).enable(["table", "strikethrough"])
esc = html.escape


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-") or "x"


def first_heading(text: str, fallback: str) -> str:
    m = re.search(r"^#\s+(.+)$", text, re.M)
    return m.group(1).strip() if m else fallback


def front_matter(text: str) -> tuple[dict, str]:
    if not text.startswith("---\n"):
        return {}, text
    end = text.index("\n---", 4)
    meta = {}
    for line in text[4:end].splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            meta[k.strip()] = v.strip().strip('"')
    return meta, text[end + 4:].lstrip("\n")


def split_h2(body: str) -> list[tuple[str, str]]:
    """Splits Markdown on level-2 headings outside code fences: [(heading, text)]."""
    out, head, buf, fence = [], "", [], False
    for line in body.splitlines():
        if line.lstrip().startswith("```"):
            fence = not fence
        if not fence and line.startswith("## "):
            out.append((head, "\n".join(buf)))
            head, buf = line[3:].strip(), []
        else:
            buf.append(line)
    out.append((head, "\n".join(buf)))
    return out


def wrap_tables(h: str) -> str:
    return h.replace("<table>", '<div class="table-wrap"><table>').replace("</table>", "</table></div>")


def render_md(text: str, resolve=None) -> str:
    tokens = md.parse(text)
    if resolve:
        for tok in tokens:
            for child in tok.children or []:
                if child.type == "link_open":
                    child.attrSet("href", resolve(child.attrGet("href") or ""))
                elif child.type == "image":
                    child.attrSet("src", resolve(child.attrGet("src") or "", asset=True))
    return wrap_tables(md.renderer.render(tokens, md.options, {}))


def with_title(h: str, title: str) -> str:
    return h if "<h1" in h[:600] else f"<h1>{esc(title)}</h1>\n{h}"


def is_external(href: str) -> bool:
    return bool(re.match(r"^[a-z][a-z0-9+.-]*:", href, re.I)) or href.startswith(("#", "//"))


class Library:
    def __init__(self, config: dict):
        self.config = config
        self.tracks = {t["id"]: dict(t, sections=[], sources=[]) for t in config["tracks"]}
        self.sections: dict[str, dict] = {}
        self.lessons: list[dict] = []
        self.cards: list[dict] = []
        self.problems: list[dict] = []
        self.playground: list[dict] = []
        self.ids: set[str] = set()

    def section(self, track: str, title: str) -> str:
        if track not in self.tracks:
            raise SystemExit(f"unknown track {track!r} (add it to sources.json)")
        sid = f"{track}/{slug(title)}"
        if sid not in self.sections:
            self.sections[sid] = {"id": sid, "title": title}
            self.tracks[track]["sections"].append(self.sections[sid])
        return sid

    def uid(self, base: str) -> str:
        uid, n = base, 2
        while uid in self.ids:
            uid, n = f"{base}~{n}", n + 1
        self.ids.add(uid)
        return uid

    def lesson(self, lid, track, section, title, body, url="", source=""):
        lid = self.uid(lid)
        self.lessons.append({"id": lid, "track": track, "section": self.section(track, section),
                             "title": title, "html": with_title(body, title), "url": url, "source": source})
        return lid

    def card(self, cid, track, section, front, back, label="", lesson=None):
        c = {"id": self.uid(cid), "track": track, "section": self.section(track, section),
             "label": label, "front": front, "back": back}
        if lesson:
            c["lesson"] = lesson
        self.cards.append(c)

    def credit(self, track: str, src: dict):
        url = src.get("url") or src.get("repo") or ""
        entry = {"id": src["id"], "title": src.get("title", src["id"]), "url": url}
        if entry not in self.tracks[track]["sources"]:
            self.tracks[track]["sources"].append(entry)

    def result(self, title: str, subtitle: str, helpers: str) -> dict:
        tracks = [t for t in self.tracks.values() if t["sections"]]
        lib = {
            "title": title, "subtitle": subtitle, "built": datetime.date.today().isoformat(),
            "tracks": tracks, "lessons": self.lessons, "cards": self.cards,
            "problems": self.problems, "playground": self.playground, "helpers": helpers,
        }
        lib["version"] = hashlib.sha1(json.dumps(lib, sort_keys=True).encode()).hexdigest()[:10]
        return lib


# ------------------------------------------------------------------ problems

CODE_BLOCK = re.compile(r"^```python[ \t]+(starter|solution|tests)[ \t]*\n(.*?)^```[ \t]*$", re.S | re.M)
NEEDS = ("numpy", "pandas", "sqlite3")


def add_problems(lib: Library, src: dict, base: Path):
    for path in sorted(base.rglob("*.md")):
        meta, body = front_matter(path.read_text(encoding="utf-8"))
        track, section = meta.get("track"), meta.get("section")
        if not track or not section:
            raise SystemExit(f"{path}: front matter needs track and section")
        lib.credit(track, src)
        for title, text in split_h2(body):
            if not title:
                continue
            blocks = {kind: code.rstrip() + "\n" for kind, code in CODE_BLOCK.findall(text)}
            missing = {"starter", "solution", "tests"} - blocks.keys()
            if missing:
                raise SystemExit(f"{path.name} · {title}: missing {', '.join(sorted(missing))} block")
            prompt = CODE_BLOCK.sub("", text).strip()
            info = {}
            m = re.match(r"^>\s*(.+)$", prompt.splitlines()[0]) if prompt else None
            if m and ":" in m.group(1):
                for part in m.group(1).split("|"):
                    if ":" in part:
                        k, v = part.split(":", 1)
                        info[k.strip().lower()] = v.strip()
                prompt = "\n".join(prompt.splitlines()[1:]).strip()
            code = blocks["starter"] + blocks["solution"] + blocks["tests"]
            lc = info.get("leetcode", "")
            lib.problems.append({
                "id": lib.uid(f"{track}:{slug(title)}"), "track": track, "section": lib.section(track, section),
                "title": title, "difficulty": info.get("difficulty", ""),
                "tags": [t.strip() for t in info.get("tags", "").split(",") if t.strip()],
                "source": info.get("source", ""),
                "leetcode": lc if lc and lc != "—" else "",
                "needs": [n for n in NEEDS if re.search(rf"^\s*(import|from)\s+{n}\b", code, re.M)],
                "prompt": render_md(prompt), "starter": blocks["starter"],
                "solution": blocks["solution"], "tests": blocks["tests"],
                "file": path.relative_to(ROOT).as_posix(),
            })


def add_playground(lib: Library, src: dict, base: Path):
    for path in sorted(base.glob("*.py")):
        code = path.read_text(encoding="utf-8")
        m = re.match(r"#\s*title:\s*(.+)\n", code)
        title = m.group(1).strip() if m else path.stem.replace("_", " ")
        lib.playground.append({"id": f"pg:{path.stem}", "title": title, "code": code[m.end():] if m else code})


# ------------------------------------------------------------------ algos

def extract_html_page(text: str) -> tuple[str, str]:
    t = re.search(r"<title[^>]*>(.*?)</title>", text, re.S | re.I)
    b = re.search(r"<body[^>]*>(.*)</body>", text, re.S | re.I)
    body = b.group(1) if b else text
    for tag in ("script", "style", "noscript", "head"):
        body = re.sub(rf"<{tag}\b.*?</{tag}\s*>", "", body, flags=re.S | re.I)
    body = re.sub(r"<link\b[^>]*>", "", body, flags=re.I)
    body = re.sub(r"""\son[a-z]+\s*=\s*("[^"]*"|'[^']*')""", "", body, flags=re.I)
    body = re.sub(r'<div class="noscript-fallback".*?</div>', "", body, flags=re.S)
    return (html.unescape(t.group(1)).strip() if t else ""), body.strip()


def js_object_literal(js: str, marker: str) -> str | None:
    start = js.find(marker)
    if start < 0:
        return None
    i = js.index("{", start)
    depth, quote, j = 0, None, i
    while j < len(js):
        ch = js[j]
        if quote:
            if ch == "\\":
                j += 1
            elif ch == quote:
                quote = None
        elif ch in "\"'`":
            quote = ch
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return js[i:j + 1]
        j += 1
    return None


def quiz_data(path: Path) -> dict:
    if not path.exists() or not shutil.which("node"):
        return {}
    literal = js_object_literal(path.read_text(encoding="utf-8"), "const QUIZ_DATA")
    if not literal:
        return {}
    script = "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>process.stdout.write(JSON.stringify(eval('('+s+')'))))"
    try:
        out = subprocess.run(["node", "-e", script], input=literal, capture_output=True, text=True, timeout=30)
        return json.loads(out.stdout) if out.returncode == 0 else {}
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return {}


def add_algos(lib: Library, src: dict, base: Path):
    repo, pages = src["repo"].rstrip("/"), src["pages"].rstrip("/") + "/"
    rules = src["map"]
    files = []
    for path in sorted(base.rglob("*")):
        rel = path.relative_to(base).as_posix()
        if (not path.is_file() or rel.startswith(".") or "/." in rel or "__pycache__" in rel
                or path.suffix.lower() not in (".md", ".html", ".py", ".sql")
                or any(fnmatch.fnmatch(rel, s) for s in src.get("skip", []))):
            continue
        rule_i = next(i for i, r in enumerate(rules) if fnmatch.fnmatch(rel, r["glob"]))
        files.append((rule_i, rel, path))
    files.sort()
    ids = {rel: f"algos:{rel.rsplit('.', 1)[0]}" for _, rel, _ in files}

    def resolver(rel_file):
        def resolve(href, asset=False):
            if not href or is_external(href):
                return href
            path, _, frag = href.partition("#")
            target = posixpath.normpath(posixpath.join(posixpath.dirname(rel_file), path))
            if not asset and target in ids:
                return f"#lesson/{ids[target]}"
            if asset or target.endswith(".html") or target.endswith(".pdf"):
                return pages + target + (f"#{frag}" if frag else "")
            return f"{repo}/blob/main/{target}" + (f"#{frag}" if frag else "")
        return resolve

    for rule_i, rel, path in files:
        rule = rules[rule_i]
        text = path.read_text(encoding="utf-8", errors="replace")
        resolve = resolver(rel)
        if path.suffix == ".html":
            title, body = extract_html_page(text)
            body = re.sub(r'\b(href|src)="([^"]*)"',
                          lambda m: f'{m.group(1)}="{resolve(m.group(2), asset=m.group(1) == "src")}"', body)
            title = title or path.stem.replace("_", " ")
            url = pages + rel
        elif path.suffix == ".md":
            title = first_heading(text, path.stem.replace("_", " "))
            body = render_md(text, resolve)
            url = f"{repo}/blob/main/{rel}"
        else:
            lang = "sql" if path.suffix == ".sql" else "python"
            title = path.name
            body = f'<pre><code class="language-{lang}">{esc(text)}</code></pre>'
            url = f"{repo}/blob/main/{rel}"
        lib.lesson(ids[rel], rule["track"], rule["section"], title, wrap_tables(body), url=url, source="algos")
        lib.credit(rule["track"], {"id": "algos", "title": "algos", "url": repo})

    by_rel = {l["id"]: l for l in lib.lessons}
    for cat, items in quiz_data(base / "test-mode.js").items():
        rel = src.get("quiz_map", {}).get(cat)
        lesson = by_rel.get(ids.get(rel, ""))
        track = lesson["track"] if lesson else "algorithms"
        section = lib.sections[lesson["section"]]["title"] if lesson else "Quizzes"
        for i, q in enumerate(items):
            opts = q.get("o") or []
            ans = q.get("a", 0)
            front = f"<p>{esc(q.get('q', ''))}</p>"
            if opts:
                front += '<ol class="options" type="A">' + "".join(f"<li>{esc(o)}</li>" for o in opts) + "</ol>"
            right = opts[ans] if isinstance(ans, int) and ans < len(opts) else str(ans)
            letter = chr(65 + ans) if isinstance(ans, int) else ""
            back = f"<p><strong>{letter}.</strong> {esc(right)}</p>" + (f"<p>{esc(q['ex'])}</p>" if q.get("ex") else "")
            lib.card(f"algos:quiz:{cat}:{i}", track, section, front, back,
                     label=f"Quiz · {lesson['title'] if lesson else cat}", lesson=lesson["id"] if lesson else None)


# ------------------------------------------------------------------ decks from earlier apps

TEX_INLINE = re.compile(r"\$([^$]+)\$")


def tex(s: str, display=False) -> str:
    if not s:
        return ""
    tag = "div" if display else "span"
    return f'<{tag} class="tex{" display" if display else ""}" data-tex="{esc(s)}">{esc(s)}</{tag}>'


def text_with_tex(s: str) -> str:
    out, last = [], 0
    for m in TEX_INLINE.finditer(s or ""):
        out.append(esc(s[last:m.start()]))
        out.append(tex(m.group(1)))
        last = m.end()
    out.append(esc((s or "")[last:]))
    return "".join(out)


def add_deepmath(lib: Library, src: dict, base: Path):
    deck = json.loads((base / "web" / "deck.json").read_text(encoding="utf-8"))
    track = src["track"]
    lib.credit(track, src)
    levels = {lv["id"]: lv["label"] for lv in deck.get("levels", [])}
    for s in deck["sources"]:
        groups = {g["id"]: g["label"] for g in s["groups"]}
        cards = [c for c in deck["cards"] if c["src"] == s["id"]]
        sheet = [f'<p class="lead">{text_with_tex(s.get("ai", ""))}</p>']
        lesson_id = f"deepmath:{s['id']}"
        for gid, glabel in groups.items():
            group_cards = [c for c in cards if c["group"] == gid]
            if group_cards:
                sheet.append(f"<h2>{esc(glabel)}</h2>")
            for c in group_cards:
                sheet.append(f'<section class="sheet-card"><h3>{esc(c["name"])}</h3>{tex(c["tex"], True)}'
                             f'{deepmath_back(c, levels)}</section>')
        lid = lib.lesson(lesson_id, track, s["title"], s["title"], "\n".join(sheet), url=src.get("url", ""),
                         source=src["id"])
        for c in cards:
            front = f'<p class="card-title">{esc(c["name"])}</p>{tex(c["tex"], True)}'
            lib.card(f"deepmath:{c['id']}", track, s["title"], front, deepmath_back(c, levels),
                     label=f"{groups.get(c['group'], '')} · {levels.get(c.get('level'), '')}", lesson=lid)


def deepmath_back(c: dict, levels: dict) -> str:
    parts = []
    if c.get("read"):
        parts.append(f'<p class="read">“{esc(c["read"])}”</p>')
    if c.get("meaning"):
        parts.append(f"<p>{text_with_tex(c['meaning'])}</p>")
    if c.get("example"):
        parts.append(f'<h4>Example</h4>{tex(c["example"], True)}')
    if c.get("terms"):
        parts.append("<h4>Term by term</h4><ul>" + "".join(
            f"<li>{tex(t.get('tex', ''))} — {text_with_tex(t.get('text', ''))}</li>" for t in c["terms"]) + "</ul>")
    if c.get("ai"):
        parts.append(f"<h4>In AI papers</h4><p>{text_with_tex(c['ai'])}</p>")
    if c.get("cite"):
        parts.append(f'<p class="fine">{text_with_tex(c["cite"])}</p>')
    return "".join(parts)


def add_systemlegos(lib: Library, src: dict, base: Path):
    deck = json.loads((base / "web" / "deck.json").read_text(encoding="utf-8"))
    track = src["track"]
    lib.credit(track, src)
    titles = {c["id"]: c["title"] for c in deck["cards"]}
    for mod in deck["modules"]:
        section = re.sub(r"^\d+\s*·\s*", "", mod["title"])
        section = f"System Legos · {section}"
        groups = {g["id"]: g["label"] for g in mod["groups"]}
        cards = [c for c in deck["cards"] if c["module"] == mod["id"]]
        sheet = []
        for gid, glabel in groups.items():
            gc = [c for c in cards if c["group"] == gid]
            if gc:
                sheet.append(f"<h2>{esc(glabel)}</h2>")
            sheet += [f'<section class="sheet-card"><h3>{esc(c["title"])}</h3>'
                      f'<p class="fine">{esc(c.get("subtitle") or "")}</p>{legos_back(c, titles)}</section>' for c in gc]
        lid = lib.lesson(f"systemlegos:{mod['id']}", track, section, mod["title"], "\n".join(sheet),
                         url=src.get("url", ""), source=src["id"])
        for c in cards:
            front = f'<p class="card-title">{esc(c["title"])}</p><p class="fine">{esc(c.get("subtitle") or "")}</p>'
            if c["kind"] == "build":
                front += f"<p>{esc(c.get('summary') or '')}</p>"
            lib.card(f"systemlegos:{c['id']}", track, section, front, legos_back(c, titles, front_has_summary=c["kind"] == "build"),
                     label=f"{groups.get(c['group'], '')} · {'design exercise' if c['kind'] == 'build' else 'brick'}",
                     lesson=lid)


def legos_back(c: dict, titles: dict, front_has_summary=False) -> str:
    parts = []
    if c.get("lego"):
        parts.append(f'<p class="read">{esc(c["lego"])}</p>')
    if c.get("summary") and not front_has_summary:
        parts.append(f"<p>{esc(c['summary'])}</p>")
    if c.get("steps"):
        parts.append("<h4>Steps</h4><ol>" + "".join(f"<li>{esc(s)}</li>" for s in c["steps"]) + "</ol>")
    for sec in c.get("sections") or []:
        parts.append(f"<h4>{esc(sec['title'])}</h4><ul>" + "".join(f"<li>{esc(i)}</li>" for i in sec["items"]) + "</ul>")
    if c.get("uses"):
        parts.append("<h4>Bricks used</h4><p>" + ", ".join(esc(titles.get(u, u)) for u in c["uses"]) + "</p>")
    if c.get("links"):
        parts.append("<h4>Read more</h4><ul>" + "".join(
            f'<li><a href="{esc(l["url"])}">{esc(l["title"])}</a>{" — " + esc(l["note"]) if l.get("note") else ""}</li>'
            for l in c["links"]) + "</ul>")
    return "".join(parts)


GK_LABEL = {"write": "Write", "run": "Run", "measure": "Measure", "explain": "Explain", "note": "Note"}


def add_gpukernels(lib: Library, src: dict, base: Path):
    course = json.loads((base / "web" / "course.json").read_text(encoding="utf-8"))
    track = src["track"]
    lib.credit(track, src)
    names = src.get("sections", {})
    lesson_ids = {}
    for l in course["lessons"]:
        parts = [f'<p class="lead">{esc(l["summary"][:1].upper() + l["summary"][1:])}.</p>' if l.get("summary") else ""]
        meta = [f"{l.get('minutes', '?')} min"] + ([f"lab <code>{esc(l['lab'])}</code>"] if l.get("lab") else [])
        parts.insert(0, f'<p class="meta">{" · ".join(meta)}</p>')
        for s in l["sections"]:
            if s["kind"] == "read":
                parts.append(s["html"])
                continue
            body = s.get("html", "")
            if s["kind"] == "measure":
                rows = "".join(f"<tr><td>{esc(f['label'])}</td><td>{esc(f.get('unit', ''))}</td>"
                               f"<td>{'' if f.get('ref') is None else f['ref']}</td></tr>" for f in s.get("fields", []))
                body = ("<p>Run the lab and record what your GPU prints. Reference values were measured on one GB200.</p>"
                        f'<div class="table-wrap"><table><tr><th>Measurement</th><th>Unit</th><th>Reference</th></tr>{rows}</table></div>')
            parts.append(f'<section class="step {s["kind"]}"><header><span class="badge">{GK_LABEL.get(s["kind"], s["kind"])}'
                         f'</span></header><div class="body">{body}</div></section>')
        title = f"{l['id']}. {l['title']}"
        section = names.get(l.get("track"), (l.get("track") or "Lessons").title())
        lesson_ids[l["id"]] = lib.lesson(f"gpukernels:{l['id']}", track, section, title, "\n".join(parts),
                                         url=f"{src.get('url', '')}#lesson/{l['id']}", source=src["id"])
    by_id = {l["id"]: l for l in course["lessons"]}
    for c in course["cards"]:
        l = by_id.get(c["lesson"], {})
        section = names.get(l.get("track"), (l.get("track") or "Lessons").title())
        lib.card(f"gpukernels:{c['id']}", track, section, f"<p>{c['q']}</p>", f"<p>{c['a']}</p>",
                 label=f"Lesson {c['lesson']} · {l.get('title', '')}", lesson=lesson_ids.get(c["lesson"]))


def add_vllm(lib: Library, src: dict, base: Path):
    course = json.loads((base / "web" / "course.json").read_text(encoding="utf-8"))
    track = src["track"]
    lib.credit(track, src)
    fix = lambda h: h.replace('href="#/lesson/', 'href="#lesson/vllm_labs:')  # noqa: E731
    for t in course["tracks"]:
        section = f"Serving labs · {t['title']}"
        for l in t["lessons"]:
            lid = lib.lesson(f"vllm_labs:{l['id']}", track, section, l["title"], fix(l["html"]),
                             url=l.get("url", ""), source=src["id"])
            for c in l.get("cards", []):
                lib.card(f"vllm_labs:{c['id']}", track, section, c.get("qHtml") or esc(c["q"]),
                         fix(c.get("aHtml") or esc(c["a"])), label=l["title"], lesson=lid)


KIND_ORDER = ["lesson", "verse", "concept", "lab", "trap", "question", "reading"]


def add_deck(lib: Library, src: dict, base: Path):
    deck = json.loads((base / "web" / "deck.json").read_text(encoding="utf-8"))
    track = src["track"]
    lib.credit(track, src)
    prefix = src.get("prefix", "")
    for s in deck["sources"]:
        for g in s["groups"]:
            cards = [c for c in deck["cards"] if c["src"] == s["id"] and c["group"] == g["id"]]
            if not cards:
                continue
            section = prefix + (s["title"] if len(deck["sources"]) > 1 else "Course")
            ordered = sorted(cards, key=lambda c: KIND_ORDER.index(c["kind"]) if c["kind"] in KIND_ORDER else 99)
            sheet = [f'<section class="sheet-card kind-{esc(c["kind"])}"><h3><span class="kind">{esc(c.get("label") or c["kind"])}</span> '
                     f'{c["front"]}</h3>{deck_options(c)}{deck_back(c)}</section>' for c in ordered]
            lid = lib.lesson(f"{src['id']}:{s['id']}:{g['id']}", track, section, g["label"], "\n".join(sheet),
                             url=src.get("url", ""), source=src["id"])
            for c in cards:
                lib.card(f"{src['id']}:{c['id']}", track, section, f'<p class="card-title">{c["front"]}</p>{deck_options(c)}',
                         deck_back(c), label=f"{g['label']} · {c.get('label') or c['kind']}", lesson=lid)


def deck_options(c: dict) -> str:
    if not c.get("options"):
        return ""
    return '<ol class="options" type="A">' + "".join(f"<li>{o['html']}</li>" for o in c["options"]) + "</ol>"


def deck_back(c: dict) -> str:
    parts = []
    if c.get("answer"):
        parts.append(f"<p><strong>Answer: {esc(str(c['answer']))}</strong></p>")
    for b in c.get("back") or []:
        parts.append(f'<div class="block {esc(b.get("cls", ""))}"><h4>{esc(b.get("title", ""))}</h4>{b.get("html", "")}</div>')
    if c.get("meta"):
        parts.append(f'<p class="fine">{esc(c["meta"])}</p>')
    if c.get("link"):
        parts.append(f'<p class="fine"><a href="{esc(c["link"])}">↗ {esc(c.get("linkLabel") or "source")}</a></p>')
    return "".join(parts)


IDEA = ("the idea", "concept", "background", "what is", "overview", "why", "the problem")
LOOK = ("what to look for", "expected", "takeaway", "what you should", "key results", "what you will learn")


def paragraphs(text: str, n=2) -> str:
    out, cur, fence = [], [], False
    for line in text.splitlines() + [""]:
        if line.lstrip().startswith("```"):
            fence = not fence
            continue
        if fence:
            continue
        if line.strip():
            cur.append(line)
        elif cur:
            if not cur[0].lstrip().startswith(("#", "|", "<", "!")):
                out.append("\n".join(cur))
            cur = []
        if len(out) >= n:
            break
    return "\n\n".join(out)


def add_labs(lib: Library, src: dict, base: Path):
    track, section, repo = src["track"], src["section"], src["repo"].rstrip("/")
    assets = (src.get("assets") or f"{repo}/raw/main/").rstrip("/") + "/"
    lib.credit(track, src)
    for spec in src["files"]:
        spec = {"glob": spec} if isinstance(spec, str) else spec
        for path in sorted(base.glob(spec["glob"])):
            rel = path.relative_to(base).as_posix()
            _, text = front_matter(path.read_text(encoding="utf-8"))

            def resolve(href, asset=False, rel=rel):
                if not href or is_external(href):
                    return href
                target = posixpath.normpath(posixpath.join(posixpath.dirname(rel), href.split("#")[0]))
                if asset:
                    target = posixpath.normpath(posixpath.join(posixpath.dirname(rel).replace("docs", "", 1).strip("/"), href)) \
                        if src.get("assets") else target
                    return assets + target
                kind = "tree" if (base / target).is_dir() else "blob"
                return f"{repo}/{kind}/main/{target}"

            name = path.parent.name if path.name == "README.md" and path.parent != base else src["title"]
            pieces = split_h2(text) if spec.get("split") else [("", text)]
            for i, (head, chunk) in enumerate(pieces):
                if spec.get("split") and not chunk.strip():
                    continue
                title = head or first_heading(chunk, name.replace("_", " "))
                body = f"## {head}\n{chunk}" if head else chunk
                lid = lib.lesson(f"{src['id']}:{rel}" + (f"#{i}" if spec.get("split") else ""), track, section, title,
                                 render_md(body, resolve), url=f"{repo}/blob/main/{rel}", source=src["id"])
                if path.name != "README.md" or path.parent == base:
                    continue
                secs = split_h2(chunk)
                idea = next((t for h, t in secs if h.lower().startswith(IDEA)), secs[0][1])
                gist = paragraphs(idea)
                if gist:
                    lib.card(f"{lid}:idea", track, section, f"<p>What is the core idea of <strong>{esc(title)}</strong>?</p>",
                             render_md(gist, resolve), label=src["title"], lesson=lid)
                look = next((t for h, t in secs if h.lower().startswith(LOOK)), None)
                if look:
                    items = re.findall(r"^\s*(?:[-*]|\d+\.)\s+(.+)$", look, re.M)[:5]
                    answer = "\n".join(f"- {x}" for x in items) if items else paragraphs(look, 1)
                    if answer:
                        lib.card(f"{lid}:look", track, section, f"<p>What should you observe in <strong>{esc(title)}</strong>?</p>",
                                 render_md(answer, resolve), label=src["title"], lesson=lid)


ADAPTERS = {
    "problems": add_problems, "playground": add_playground, "algos": add_algos, "deepmath": add_deepmath,
    "systemlegos": add_systemlegos, "gpukernels": add_gpukernels, "vllm": add_vllm, "deck": add_deck, "labs": add_labs,
}


def build(config: dict, include_private: bool) -> tuple[dict, list[str]]:
    lib = Library(config)
    notes = []
    for src in config["sources"]:
        if not include_private and not src.get("public", True):
            notes.append(f"skip {src['id']}: private")
            continue
        base = (ROOT / src["path"]).resolve()
        if not base.exists():
            notes.append(f"skip {src['id']}: {base} not found")
            continue
        before = (len(lib.lessons), len(lib.cards), len(lib.problems))
        ADAPTERS[src["type"]](lib, src, base)
        after = (len(lib.lessons), len(lib.cards), len(lib.problems))
        notes.append(f"{src['id']:<13} +{after[0] - before[0]} lessons, +{after[1] - before[1]} cards, "
                     f"+{after[2] - before[2]} problems")
    helpers = (ROOT / "content" / "dc.py").read_text(encoding="utf-8")
    return lib.result(config["title"], config.get("subtitle", ""), helpers), notes


def write(lib: dict, out: Path):
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(lib, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    size = out.stat().st_size / 1e6
    shown = out.relative_to(ROOT) if str(out).startswith(str(ROOT)) else out
    print(f"wrote {shown}: {len(lib['tracks'])} tracks, {len(lib['lessons'])} lessons, {len(lib['cards'])} cards, "
          f"{len(lib['problems'])} problems ({size:.1f} MB, version {lib['version']})")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--web", default=str(WEB_OUT), help="public library for the web app")
    ap.add_argument("--app", default=str(APP_OUT), help="full library bundled into the Mac app")
    ap.add_argument("--include-private", action="store_true", help="also put private sources in the web library")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()
    config = json.loads((ROOT / "sources.json").read_text(encoding="utf-8"))

    web, notes = build(config, include_private=args.include_private)
    app, app_notes = build(config, include_private=True)
    if not args.quiet:
        for n in app_notes:
            print("  " + n)
    write(web, Path(args.web))
    write(app, Path(args.app))
    skipped = [n for n in notes if "private" in n]
    if skipped and not args.quiet:
        print("  web library leaves out: " + ", ".join(n.split()[1].rstrip(":") for n in skipped))


if __name__ == "__main__":
    sys.exit(main())
