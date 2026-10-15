# Reading prototype review brief

This repository contains a runnable experiment in reading literature by
retyping it in Neovim. Review whether the interaction is dependable and whether
its explicit compromises are acceptable before extending the plugin. This is
not a completed ebook platform or an approval of Ghost as the primary mode.

## Start here

Read [usage](../README.md), then [technical findings](findings.md). The findings
are the authoritative account of the experiments, comparison contract, editing
restrictions, version rationale, verification evidence, and manual checks.

From the repository root, with Neovim 0.11+:

```sh
nvim --clean --cmd "set runtimepath^=$PWD" -c 'runtime plugin/lilt.lua' -c LiltGhost
```

Try `:LiltSplit`, `:LiltGhost`, and `:LiltClose`. Use native Insert mode and
`:write /path/to/manuscript.txt` to save. Closing retains the manuscript within
the current process; there is no cross-process session selection or restoration.

## Implementation map

| File | Responsibility / review question |
| --- | --- |
| `plugin/lilt.lua` | Three commands; no typing mappings or editor emulation |
| `lua/lilt/compare.lua` | Physical-row, codepoint-position comparison; byte ranges for errors |
| `lua/lilt/render.lua` | Derive highlights, EOL pending suffixes, and all future virtual rows from the real buffer |
| `lua/lilt/init.lua` | One session and retained manuscript; view switching, windows, buffer attachment, autocmds, cleanup |
| `samples/alice.txt` | Fixed-width, 40-line passage; blank paragraph separators; public-domain source attribution in README |
| `tests/compare.lua` | Comparison contract, including missing/extra characters and punctuation |
| `tests/headless.lua` | Real Neovim editing, undo/redo, serialization, reload, switching, and lifecycle |
| `tests/ui.py` | Attached UI redraw and highlight assertions, native input, scrolling and resize behavior |

Only the actual manuscript buffer is authoritative for authored text. Reference
text is a session snapshot. Both views share the same manuscript and undo tree;
there is no placeholder conversion or parallel Lua copy of the writing.

## Decisions to assess

1. **Ghost's scope.** Pending text remains visible on earlier and future rows,
   but virtual future rows cannot be freely browsed or searched. The current
   recommendation is experimental forward copying; Split remains independently
   available for full reference browsing. Is this a sufficient reading experience?
2. **Physical lines versus paragraphs.** Reference line breaks are layout, yet
   comparison expects the prepared physical rows. Enter must be typed at those
   breaks. Extra/missing newlines shift subsequent comparisons; missing/extra
   characters shift the rest of their row. The plugin preserves these edits and
   does not realign them. Judge whether this deterministic contract is usable,
   rather than assuming paragraph-level equivalence is implemented.
3. **Width and fallback.** Ghost requires 75 usable columns for this passage.
   Narrowing selects wrapped, above/below Split while preserving Insert mode and
   writing. Returning to Ghost is explicit. Assess the mode change and the loss
   of vertical space, including the statusline explanation in real use.
4. **Lifecycle and isolation.** Inspect ownership and event ordering in
   `init.lua`, especially deferred callbacks, manual window closure, buffer
   replacement/reload, and last-window handling. Tests cover several paths,
   but do not establish correctness under every user autocmd or split option.
5. **Reading comfort.** Pending/error groups inherit `Comment`/`SpellBad`.
   Automated tests establish glyph placement and feedback, not the quality of
   those colors across themes or comfort over a long reading session.

## Reproduce verification

```sh
nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' -l tests/compare.lua
nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' -l tests/headless.lua
python3 tests/ui.py
```

The UI harness needs development-only `pynvim`; the plugin has no runtime
dependencies. Pass a Neovim executable to the UI test for version-specific runs.
Expected counts are 26 comparison, 131 editing/lifecycle, and 40 UI assertions.
All three suites passed on Neovim 0.11.5 and 0.12.5. The 0.11.0 minimum is based
on public API availability; that exact patch version was not exercised.

Remaining uncertainty includes long reading sessions, arbitrary user mappings
and autocmds, other terminal palettes, mouse use, very small heights, complex
Unicode, and large-document performance. The sample is prepared English; there
is no grapheme layout engine, automatic reflow, or automatic saving.

For review feedback, distinguish reproducible defects from accepted prototype
limits and interaction decisions worth revisiting. Include the Neovim version,
window dimensions, exact keys, expected/actual text or display, and whether the
writing, undo history, or unrelated editor state changed. No catalogs, format
converters, statistics, synchronization, or general UI framework are in scope.
