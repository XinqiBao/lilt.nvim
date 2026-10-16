# lilt.nvim

**Read at your own rhythm.**

A quiet Neovim plugin for reading literature by retyping it. Your writing lives
in an ordinary buffer, with native editing, undo, redo, and saving. Reference
text and gentle comparison feedback help you keep your place. There are no
scores, timed exercises, typing mappings, or automatic corrections.

![Ghost view: authored text followed by subdued reference text](doc/ghost.png)

## Install

Requires **Neovim 0.11+**. No runtime dependencies or setup call.

For [lazy.nvim](https://github.com/folke/lazy.nvim), add this plugin spec:

```lua
{
  "XinqiBao/lilt.nvim",
  cmd = { "LiltGhost", "LiltSplit", "LiltClose" },
}
```

Other plugin managers work too: install `XinqiBao/lilt.nvim` normally.

## Read

| Command | Action |
| --- | --- |
| `:LiltGhost` | Open or switch to Ghost |
| `:LiltSplit` | Open or switch to Split |
| `:LiltClose` | Close the session; retain your manuscript |

Start with `:LiltGhost`, press `i`, and type. Copy the reference's physical line
breaks, including blank paragraph rows. Use your usual motions, operators,
search, and undo. Comparison never changes your text.

**Ghost** places the remaining reference beside your writing and below its last
line. Earlier unfinished lines stay visible. Mistakes receive subtle highlights;
pause on one in Normal mode for about 250 ms to see an Expected / Typed hint.
Moving, editing, or leaving the window dismisses it. Future virtual lines cannot
be navigated or searched; use Split to browse ahead.

**Split** puts a protected reference pane beside your manuscript when both fit
comfortably, or above it at narrower widths. The panes scroll independently and
wrap. Native `<C-w>` commands can move, resize, or rearrange them. Resizing never
switches views or rearranges the layout. Requesting the active view again keeps
your layout and reference position, and focuses the manuscript.

Sessions open in a separate tab and share **one manuscript buffer**. Closing and
reopening retains it and its undo history for this Neovim process. Closing an
owned window or replacing its buffer ends the session. Unrelated windows and
buffers survive.

**Save with `:write /path/to/manuscript.txt` before quitting.** The file contains
only what you typed. Find retained writing in `:ls` and `:buffer N`. Wipe the
manuscript with `:bwipeout` to start fresh (`:bwipeout!` discards unsaved changes).
There is no automatic saving or restoration across Neovim processes.

## Reading notes

The available passage is the opening of Lewis Carroll's *Alice's Adventures in
Wonderland*. There is currently no content selector. Its prepared physical lines
are fixed: extra or missing line breaks shift subsequent comparisons. There is
no reflow, punctuation normalization, or cross-line alignment.

Comparison aligns UTF-8 codepoints within each row. Internal omissions differ
from an untyped suffix: `beat` against `beautiful` omits `u`, matches `t`, and
leaves `iful` pending. Ambiguous repeated text gets a deterministic interpretation;
it cannot reveal typing intent. Complex graphemes and arbitrary tab/wide-character
layout are outside the bundled English passage's scope.

Ghost is most comfortable with **75 usable columns** for this sample. Narrower
windows can clip pending text, and a short authored prefix limits native
horizontal scrolling. Choose Split when helpful; its reference is fully browsable.

| Feedback | Highlight group / default link |
| --- | --- |
| Untyped suffix | `LiltPending` → `Comment` |
| Replacement | `LiltError` → `DiagnosticError` |
| Extra authored text | `LiltExtra` → `DiagnosticWarn` |
| Missing text | `LiltMissing` → `DiagnosticUnderlineWarn` |

Equal text uses the normal foreground. Ghost underlines the next real character
at an omission; Split marks the missing reference text. Highlight groups respect
colorschemes and explicit user overrides.

[Development and verification](DEVELOPING.md) · [Design contracts](doc/design.md)

Plugin code is [MIT licensed](LICENSE). The public-domain literary work is
[attributed separately](samples/README.md).
