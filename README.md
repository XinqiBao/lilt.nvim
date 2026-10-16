# lilt.nvim

**Read at your own rhythm.**

A small Neovim plugin for reading literature by retyping it. Ghost and Split
share one ordinary editable manuscript buffer. There are no timed exercises,
scores, typing mappings, automatic corrections, or runtime dependencies.

Requires **Neovim 0.11+**. From this repository, launch with an isolated config:

```sh
nvim --clean --cmd "set runtimepath^=$PWD" -c 'runtime plugin/lilt.lua' -c LiltGhost
```

Use `-c LiltSplit` to start in Split. Inside Neovim:

| Command | Action |
| --- | --- |
| `:LiltGhost` | Start or switch to Ghost |
| `:LiltSplit` | Start or switch to Split |
| `:LiltClose` | Close reading windows; retain the manuscript |

Start typing with `i`. Retype the prepared physical line breaks, including blank
paragraph rows. Motions, operators, search, undo, redo, and writing remain native
Vim operations. Comparison never modifies your writing.

**Ghost** shows your actual text, a subdued pending reference suffix at each
real line's end, and virtual future reference lines. Earlier unfinished suffixes
stay visible. Missing characters receive a subtle underline on the next real
character; they never insert placeholders or shift your text. Extra characters
remain exactly as typed. Future reference text cannot be navigated or searched:
Ghost is for forward copying. Use Split to browse ahead.

Pause on an error in Normal Mode for about 250 ms to see a compact **Expected /
Typed** hint, usually showing the affected word. An omission attaches to the next
real character. Moving away, editing, entering Insert Mode, leaving the window,
or switching views dismisses the hint. It never takes focus or offers corrections.

**Split** shows an ordinary protected reference buffer beside the manuscript
when both panes can comfortably fit the prepared width (151 columns for this
sample). Otherwise it places the reference above the manuscript. Both panes wrap
at narrow widths. Reference progress and errors reflect the same comparison as
the manuscript. Navigation and search are independent; use native `<C-w>` commands
to move between or rearrange windows.

Resizing **never switches views or rearranges Split**. Ghost recommends at least
75 usable columns for this passage. Narrower windows may clip pending text;
native horizontal scrolling cannot reliably reveal it with a short authored
prefix. Choose Split explicitly when helpful.

| Meaning | Presentation / default highlight link |
| --- | --- |
| Equal | Normal foreground, including authored reference spans in Split |
| Pending | `LiltPending` → `Comment` |
| Replace | `LiltError` → `DiagnosticError`, in both Split panes |
| Extra | `LiltExtra` → `DiagnosticWarn`, on actual authored text |
| Missing | `LiltMissing` → `DiagnosticUnderlineWarn`, on reference spans in Split or the next real Ghost character |

These semantic groups respect user overrides and colorschemes. Error foregrounds
avoid relying on `SpellBad`, which can be nearly invisible in some themes.

Comparison aligns UTF-8 codepoints **within each physical row**. It separates
internal omissions from an untyped pending suffix: `beat` against `beautiful`
means matching `bea`, missing `u`, matching `t`, pending `iful`. Ambiguous text
uses deterministic edit-distance rules; it cannot know typing intent. For
example, `little bird` against `little little bird` can appear as replacements
and pending text rather than a whole-word omission. See the concise
[comparison contract and findings](doc/findings.md).

The reference is immutable during a session. The bundled passage is the opening
of Lewis Carroll's *Alice's Adventures in Wonderland*, chapter I (1865),
public-domain text prepared at up to 74 display columns with UTF-8 punctuation.
This maximum is a content convention, independent of window size. **Prepared
physical lines are part of the copying contract. Changing their layout can
invalidate correspondence with existing manuscripts.** There is no reflow,
paragraph alignment, cross-line realignment, or punctuation normalization.
Extra/missing line breaks shift subsequent row comparisons. Complex grapheme
layout and arbitrary tab/wide-character alignment are outside this English-text
scope.

Sessions open in a separate tab. Closing or reopening retains the same listed
manuscript and undo history for this Neovim process. **Save with `:write
/path/to/manuscript.txt` before quitting.** Only authored text enters the file.
Find retained writing in `:ls` / `:buffer N`; explicitly wipe it with `:bwipeout`
(or `:bwipeout!` to discard changes) to start fresh. There is no automatic saving
or cross-process session restoration. Closing an owned window or replacing its
buffer ends the session; unrelated windows and buffers remain intact.

Run verification from the repository root:

```sh
nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' -l tests/compare.lua
nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' -l tests/headless.lua
python3 tests/ui.py
```

Only the attached-UI test needs Python and development-only `pynvim`. Pass an
alternative executable as `python3 tests/ui.py /path/to/nvim`. Current evidence,
API rationale, limitations, and manual reading checks are in
[findings](doc/findings.md); [review notes](doc/review.md) map the implementation.
