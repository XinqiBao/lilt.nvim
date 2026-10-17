# Developing Lilt

Ordinary plugin users need only **Neovim 0.11.0 or newer**. For development,
[mise](https://mise.jdx.dev/) pins StyLua, Selene, and uv in
[mise.toml](mise.toml). It deliberately leaves Neovim on your own `PATH`.
[uv](https://docs.astral.sh/uv/) manages the test-only Python interpreter in
[.python-version](.python-version) and the isolated `.venv`; mise does not manage
Python. No Python package or build backend is needed.

From the repository root, with your own Neovim installed:

```sh
mise trust
mise install
mise exec -- uv venv --managed-python
mise exec -- uv pip sync --require-hashes tests/requirements.txt
mise exec -- .venv/bin/python tests/run.py
```

The first setup downloads Python if needed. The same setup commands run in CI.
For daily checks, use the last command; repeat `uv pip sync` after pulling a
changed lock file. To rebuild from scratch, remove `.venv` and repeat setup.
Python is never a plugin runtime dependency. Equivalent auxiliary executables on
`PATH` also work without mise.

`tests/requirements.in` declares the direct test dependency. The generated
`tests/requirements.txt` locks it and its transitive dependencies with artifact
hashes. Change the input and regenerate the lock with:

```sh
mise exec -- uv pip compile --python-version 3.14 --generate-hashes tests/requirements.in -o tests/requirements.txt
```

Add `--upgrade` when deliberately updating already locked dependencies. Commit
both files together. Do not edit the generated lock or install dependencies with
a second package manager.

`tests/run.py` runs formatting, static analysis, and all five suites, prints tool
versions, isolates Neovim's XDG directories, disables personal init/Shada files,
and bounds each subprocess to 60 seconds. It accepts `--nvim /path/to/nvim`.
Tests use temporary files and an embedded Neovim; no display server is needed.
The UI notification loop also has a deadline and reports the screen on assertion
failures. Positive hint checks poll for the visible float; absence checks wait
through the relevant delay.

The minimum is **Neovim 0.11.0**, because Ghost uses
`virt_lines_overflow='scroll'`. CI independently installs `v0.11.0` and Neovim's
moving `stable` release, then runs the same verification entry point on each.
The setup action logs the download target; the runner prints the actual Neovim
version. Neither target comes from mise. CI covers Linux x86-64; other platforms
are not CI targets. To exercise either release locally, unpack its official
[release archive](https://github.com/neovim/neovim/releases) outside the checkout
and select its executable for that run:

```sh
mise exec -- .venv/bin/python tests/run.py --nvim /path/to/nvim-linux-x86_64/bin/nvim
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

For bug reports, include Neovim version, dimensions, exact text/keys, expected and
actual behavior, and whether writing, undo history, or unrelated state changed.

## Presentation assets

PNG, GIF, JPEG, and WebP images use Git LFS via [.gitattributes](.gitattributes).
Install [Git LFS](https://git-lfs.com/), then run `git lfs install` and
`git lfs pull` to work on them. Add images normally with `git add`; check
`git lfs ls-files` and `git lfs fsck` before committing. Do not migrate old history.
Normal pushes upload LFS objects through the pre-push hook.

The plugin and tests do not read these images. To clone without downloading
them, use `GIT_LFS_SKIP_SMUDGE=1 git clone ...`; CI leaves checkout's LFS option
disabled. Fetch assets only when working on presentation.

[demo.tape](doc/demo.tape) records a real Neovim terminal: progressive input,
a typo, the delayed hint, correction with `r`, and continued typing across a
physical line break. It generates both [demo.gif](doc/demo.gif) and the
[Ghost screenshot](doc/ghost.png). The capture uses the default dark colorscheme
and DejaVu Sans Mono, with only display options adjusted. The checked-in assets
were recorded with Neovim 0.12.5 and VHS 0.12.1.

Recording is optional, outside the test environment and CI. Install
[VHS](https://github.com/charmbracelet/vhs), its ttyd and FFmpeg dependencies, and
the font. VHS also downloads Chromium on its first run. From the repository root:

```sh
vhs doc/demo.tape
```

If the host blocks Chromium's sandbox, VHS supports `VHS_NO_SANDBOX=true`; this
was needed on the Linux capture host.

Review the GIF's typing, hint, correction, loop, and text readability before
committing; a successful recording does not establish visual quality.
