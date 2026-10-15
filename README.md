# lilt.nvim

**Read at your own rhythm.**

A small Neovim prototype for reading by retyping literature. Two views share
one ordinary editable manuscript buffer. There are no timers, scores, typing
mappings, or runtime dependencies.

Requires **Neovim 0.11+**. From this repository, launch with an isolated config:

```sh
nvim --clean --cmd "set runtimepath^=$PWD" -c 'runtime plugin/lilt.lua' -c LiltGhost
```

Use `-c LiltSplit` instead to start in Split View. Inside Neovim:

| Command | Action |
| --- | --- |
| `:LiltGhost` | Start or switch to Ghost |
| `:LiltSplit` | Start or switch to Split |
| `:LiltClose` | Close reading windows; retain the manuscript |

Start typing with `i`. Insert characters and press Enter at the prepared physical
line breaks, including blank paragraph rows. Esc, motions, operators, undo, and
redo act on your actual writing. A wrong character never blocks typing.

**Ghost** displays pending suffixes and future lines in `LiltPending` (linked to
`Comment`). Correct writing uses the normal foreground; mistakes use `LiltError`
(linked to `SpellBad`). Future text is virtual: you cannot move into, search, or
freely scroll through it. Use Split to browse ahead. This is an experimental
forward-copying mode, with limits described in [the findings](doc/findings.md).

**Split** places a protected reference above your manuscript. Both windows use
ordinary navigation and search. Use `<C-w>k` / `<C-w>j` to move between them; the
reference scrolls independently. Narrow windows wrap. Ghost requires 75 usable
columns for this sample and falls back to Split when narrower; widening does
not automatically switch it back. `:LiltGhost` returns when space permits.

Sessions open in a separate tab. Closing or reopening keeps the same listed
manuscript and undo history for this Neovim process. **Save with `:write
/path/to/manuscript.txt` before quitting.** Pending reference text never enters
the file. After closing, find your writing in `:ls` / `:buffer N`. The prototype
has no automatic saving or cross-process session restoration. Explicitly wipe
the manuscript (`:bwipeout`, or `:bwipeout!` to discard changes) after closing to
start fresh. Switching views never converts its contents.

The bundled passage is the opening of Lewis Carroll's *Alice's Adventures in
Wonderland*, chapter I (1865), public-domain text, with curly quotation marks
and physical lines prepared at up to 74 display columns. Blank lines separate
paragraphs; within-paragraph breaks are layout, though this prototype compares
physical rows literally. There is no reflow or automatic realignment.

Run deterministic integration checks from the repository root:

```sh
nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' -l tests/compare.lua
nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' -l tests/headless.lua
python3 tests/ui.py
```

Only the UI test needs Python and `pynvim` (install in a development environment
with `python3 -m pip install pynvim`). An alternative Neovim executable can be
passed as `python3 tests/ui.py /path/to/nvim`. See [findings and manual
checks](doc/findings.md) for the evidence, editing restrictions, and recommendation.

For a focused code review, start with the [review brief](doc/review.md).
