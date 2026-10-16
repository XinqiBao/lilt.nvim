# Developing Lilt

Ordinary plugin users need only Neovim. Development uses
[mise](https://mise.jdx.dev/) for the executables pinned in [mise.toml](mise.toml):
Neovim, StyLua, Selene, and Python. The explicit Aqua backends use upstream
release binaries, including Neovim's historical 0.11.0 assets. Linux x86-64
installation and verification are exercised in CI. Upstream assets also cover
macOS; other platforms are not CI targets.

From the repository root:

```sh
mise trust
mise install
mise exec -- python -m venv .venv
.venv/bin/python -m pip install -r tests/requirements.txt
mise exec -- .venv/bin/python tests/run.py
```

A standard virtual environment is enough for this small UI harness; no Python
project packaging or additional dependency manager is needed. The test-only
requirements pin pynvim and its transitive dependencies. Python is never a plugin
runtime dependency. Equivalent executables on `PATH` work without mise too.

`tests/run.py` runs formatting, static analysis, and all five suites, prints tool
versions, isolates Neovim's XDG directories, disables personal init/Shada files,
and bounds each subprocess to 60 seconds. It accepts `--nvim /path/to/nvim`.
Tests use temporary files and an embedded Neovim; no display server is needed.
The UI notification loop also has a deadline and reports the screen on assertion
failures. Positive hint checks poll for the visible float; absence checks wait
through the relevant delay.

The minimum technical requirement is **Neovim 0.11.0**, because Ghost uses
`virt_lines_overflow='scroll'`. CI runs the same verification entry point on that
exact minimum and the stable version pinned in mise.toml. Update that one pin
when advancing the stable CI target. To exercise the minimum locally:

```sh
mise install aqua:neovim/neovim@0.11.0
mise exec aqua:neovim/neovim@0.11.0 -- .venv/bin/python tests/run.py
```

Individual suites remain directly runnable from the root:

```sh
mise exec -- nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' -l tests/compare.lua
mise exec -- nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' -l tests/headless.lua
mise exec -- nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' -l tests/lifecycle.lua
mise exec -- nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' -l tests/cache.lua
mise exec -- .venv/bin/python tests/ui.py /path/to/nvim
```

Comparison examples and generated short inputs check semantic ranges and
invariants without duplicating the algorithm. Headless integration exercises
native edits, undo/redo, saving, reload, window ownership, and retained buffers.
Lifecycle regressions exercise actual E36 failures and final-window restoration.
Cache checks compare rendered results against fresh computations through row
shifts, replacement, reload, and reopening. Attached UI tests check actual redraw
grids, highlights, layouts, resizing, and delayed hint cancellation.

Format Lua with `mise exec -- stylua lua plugin tests`. Selene uses Lua 5.1 and a
small declaration of Neovim's `vim` global; LuaLS is optional editor tooling.
Hosted checks are in [Verify](https://github.com/XinqiBao/lilt.nvim/actions/workflows/verify.yml).

## Focused performance check

```sh
mise exec -- nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' -l tests/benchmark.lua
```

This diagnostic warms the comparison with five early mismatches, then with every
nonblank sample row mismatched. It reports the median of 15 first-row edits and
the comparison call count. It has no timing assertions and is excluded from the
required suites. On one Linux x86-64 run with Neovim 0.12.5, the medians changed
from approximately 22 / 166 ms before row reuse to 5.3 / 5.2 ms afterwards. The
15 edits required 15 comparisons instead of 600 in both cases. These numbers
characterize that workload and machine, not a latency guarantee.

## Reading check

Load the plugin normally, or try the checkout without personal configuration:

```sh
nvim --clean --cmd "set runtimepath^=$PWD" -c 'runtime plugin/lilt.lua' -c LiltGhost
```

Copy a few lines, make an omission and a replacement, and pause on an error.
Correct it using native operators, undo, and redo. Switch views, browse the Split
reference independently, and rearrange it. Narrow Ghost while typing and choose
Split to read clipped text. Save, reload, close, and reopen; inspect the file and
unrelated editor windows. Test reading comfort in your preferred colorscheme;
automation cannot establish that preference.

The README image is a capture of a real attached Neovim 0.12.6 UI grid with the
default dark theme, rendered in DejaVu Sans Mono. It includes actual authored text,
reference decorations, and highlight colors; no simulated plugin UI is used.
There is no media-generation dependency or CI job.

For bug reports, include Neovim version, dimensions, exact text/keys, expected and
actual behavior, and whether writing, undo history, or unrelated state changed.
