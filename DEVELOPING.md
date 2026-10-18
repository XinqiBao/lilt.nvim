# Developing Lilt

Reading needs only **Neovim 0.11.0 or newer**; online discovery also requires
`curl` on `PATH`. For development,
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
mise exec -- uv pip compile --python-version "$(cat .python-version)" --generate-hashes tests/requirements.in -o tests/requirements.txt
```

Add `--upgrade` when deliberately updating already locked dependencies. Commit
both files together. Do not edit the generated lock or install dependencies with
a second package manager.

`tests/run.py` runs formatting, static analysis, and all suites, prints tool
versions, isolates Neovim's XDG directories, disables personal init/Shada files,
and bounds each subprocess to 60 seconds. It accepts `--nvim /path/to/nvim`.
Work/library suites validate real temporary directories, failed-copy cleanup,
and saved progress. Reading checks cover named buffers and unsaved protections;
Picker checks cover XDG configuration, multiple example works/units, back
navigation, temporary manuscripts, and cleanup. The UI suite drives the float
and native input prompt, exercises terminal resizing, and resumes in a second
process.
Tests use temporary files and an embedded Neovim; no display server is needed.
The UI notification loop also has a deadline and reports the screen on assertion
failures. Positive hint checks poll for the visible float; absence checks wait
through the relevant delay.

Online checks replace only the process boundary with controlled catalog/text
fixtures. They cover pagination, native search, failures/retry, cancellation and
late callbacks, text fidelity, provenance, installation, duplicate acquisition,
and the full picker → acquire → Ghost/Split → save → local resume journey.
CI requires no network services. For a live check, choose **Discover online…**,
browse popular/newest and poetry, search an author/title, and acquire prose and
verse. Inspect the units against `SOURCE.txt`, then save and resume through the
library. Use a temporary library to keep live checks separate from personal work.

The minimum is **Neovim 0.11.0**, because Ghost uses
`virt_lines_overflow='scroll'`. CI independently installs `v0.11.0` and Neovim's
moving `stable` release, then runs the same verification entry point on each.
The setup action logs the download target; the runner prints the actual Neovim
version. Neither target comes from mise. CI covers Linux x86-64 and macOS arm64.
To exercise either release locally, unpack its official
[release archive](https://github.com/neovim/neovim/releases) outside the checkout
and select its executable for that run:

```sh
mise exec -- .venv/bin/python tests/run.py --nvim /path/to/nvim-linux-x86_64/bin/nvim
```

Individual suites remain directly runnable from the root:

```sh
mise exec -- nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' -l tests/compare.lua
mise exec -- nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' -l tests/work.lua
mise exec -- nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' -l tests/library.lua
mise exec -- nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' -l tests/reading.lua
mise exec -- nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' -l tests/picker.lua
mise exec -- nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' -l tests/online.lua
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
required suites. Timings characterize the selected workload and machine, not a
latency guarantee. Identical cached rows should require no new comparison;
these 15 first-row edits should each require only one.

## Reading check

Load the plugin normally, or try the checkout without personal configuration:

```sh
nvim --clean --cmd "set runtimepath^=$PWD" -c 'runtime plugin/lilt.lua' -c Lilt
```

Choose Examples → Alice → its reading unit. Copy a few lines, make an omission
and a replacement, and pause on an error.
Correct it using native operators, undo, and redo. Switch views, browse the Split
reference independently, and rearrange it. Narrow Ghost while typing and choose
Split to read clipped text. Add a prepared local work through `:Lilt`, save with
`:w`, quit, and resume the same chapter in a new process. Reload, close, and
reopen; inspect the file and unrelated editor windows. Test reading comfort in your preferred colorscheme;
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

Presentation media and their recording source live in [assets/](assets/).
[demo.tape](assets/demo.tape) generates the single [demo.gif](assets/demo.gif)
from a real Neovim terminal. It shows `:Lilt` → Examples → Alice → its unit,
progressive Ghost typing, a typo and delayed hint, native correction with `r`,
physical line breaks, Split, independent reference search, and a return to Ghost.
At this width Split stacks its panes; wider windows open them side by side.

The capture uses temporary XDG directories, `--clean -i NONE`, the default dark
colorscheme, and DejaVu Sans Mono. It adjusts only display options and never
uses the owner's library. The checked-in GIF is about 34 seconds at 1040 × 550,
recorded with Neovim 0.12.5 and VHS 0.12.1.

Recording is optional, outside the test environment and CI. Install
[VHS](https://github.com/charmbracelet/vhs), its ttyd and FFmpeg dependencies, and
the font. VHS also downloads Chromium on its first run. From the repository root:

```sh
vhs assets/demo.tape
```

If the host blocks Chromium's sandbox, VHS supports `VHS_NO_SANDBOX=true`; this
was needed on the Linux capture host.

Review the GIF's navigation, typing, hint, correction, pane transitions,
independent browsing, loop, and text readability before committing; a successful
recording does not establish visual quality. Keep temporary frames and playback
files outside the checkout. Engineering contracts stay in
[doc/design.md](doc/design.md); `doc/` follows Neovim's documentation convention.
