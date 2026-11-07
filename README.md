# Datacom · crack the interview

Interview prep in one place: lessons, flash cards and a Python runner for algorithms, Python and data
(batch and streaming), system design, ML and transformers, deep math, GPU kernels, training and inference.
There's a Mac app and a web app you can install on your phone. Both read the same `library.json`.

| Track | Comes from |
| --- | --- |
| Algorithms | the problem bank here, plus `~/code/algos` (patterns, data structures, cheat sheets, quiz) |
| Python & Data | problem bank: batch Python, pandas, NumPy, SQL (sqlite3), streaming |
| System Design | `~/code/systemlegos` |
| ML & Transformers | problem bank: ML fundamentals, attention, norms, sampling, BPE |
| Deep Math | `~/code/deepmath` |
| GPU Kernels | `~/code/gpukernels`, plus kernel-thinking problems |
| Training | problem bank, `distillation`, `llm_rl`, `quantization`, `hstuapp` (Mac only) |
| Inference | problem bank, `vllm_labs`, `nanogpt-kv-cache` |
| GenAI certification | `ncp_genl` (Mac only) |

## Use it

**Phone.** Open the GitHub Pages site, then Chrome ⋮ → *Install app* (Safari: Share → *Add to Home Screen*).
Code runs in the browser with [Pyodide](https://pyodide.org) (Python 3.12, with numpy, pandas and sqlite3
loaded on first import), in a worker, so Stop always works. Lessons and cards work offline. Python works
offline after its first run. Some corporate networks block the `.zip` and `.whl` files Pyodide downloads;
use another network there, or the Mac app.

**Mac.** `./scripts/build_app.sh && open build/Datacom.app`. Code runs with your own `python3` (whatever your
Terminal finds, or set an interpreter in Settings), so your installed packages, torch included, are available.
*File ▸ Rebuild Library from Repos* (⇧⌘R) re-reads every source repo, so edits to `~/code/algos` and the rest
show up without rebuilding the app.

**Progress** stays on each device: card marks, read lessons, solved problems, your code and saved snippets.
*Export* on one device and *Import* on the other. Imports merge, so nothing is lost.

## Code

- **Problems**: 130 problems with tests. Each run executes your code, then the tests one statement at a time,
  and reports every failure with its line. A problem counts as solved when every test passes.
- **Playground**: any Python. Start from a template (scratchpad, live streaming pipeline, pandas batch job,
  loops vs NumPy, sqlite3) or a lesson's ▶ Try button, then save it as a snippet.
- `dc.py` helpers are importable everywhere: `check`, `stream`, `clickstream`, `ticks`, `sensor`, `orders`,
  `table`, `Timer`, `ListNode`/`TreeNode` builders.

## Add or change content

- Problems live in `content/problems/<track>/*.md`, one `## Title` per problem:

  ````markdown
  ## Two Sum
  > difficulty: Easy | tags: hash map | leetcode: 1

  Prompt in Markdown.

  ```python starter
  def two_sum(nums, target):
      pass
  ```

  ```python solution
  ...
  ```

  ```python tests
  check(two_sum([2, 7, 11, 15], 9), [0, 1])
  ```
  ````

- Other sources and how their files map to tracks and sections are configured in `sources.json`.

Then:

```bash
python3 tools/check_problems.py      # every reference solution passes, every starter fails
python3 tools/build_library.py       # web/library.json (public) + the Mac app's library (with private decks)
node tools/smoke_web.mjs             # headless Chrome at phone size, incl. all solutions in Pyodide
python3 -m http.server -d web 8080   # try the web app locally
```

`web/library.json` is committed, and pushing to `main` publishes `web/` to GitHub Pages
(`.github/workflows/pages.yml`). Private sources (`"public": false` in `sources.json`) only go into the Mac
app's library, which is git-ignored.
