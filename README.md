# lilt.nvim

**Read at your own rhythm.**

Read literature by retyping it in Neovim. Lilt places the passage beside your
writing and offers quiet feedback as you go. Your manuscript is an ordinary
buffer: use your own editing habits, undo, redo, and saving. There are no scores,
timed exercises, typing mappings, or automatic corrections.

![Real Neovim: Ghost typing, a typo hint and correction, then independent browsing in Split](assets/demo.gif)

In Ghost, the subdued reference recedes as you type. Pause on a mistake in
Normal mode for a local hint, then correct it with ordinary editing commands.
Switch to Split to browse ahead without moving your manuscript.

![Split View: protected reference above the same manuscript, with separate pane labels](assets/split.png)

## Install

Requires **Neovim 0.11.0 or newer**. No runtime dependencies or `setup()` call.

With [lazy.nvim](https://github.com/folke/lazy.nvim), add this plugin spec:

```lua
{
  "XinqiBao/lilt.nvim",
  cmd = { "LiltGhost", "LiltSplit", "LiltClose" },
}
```

With [vim-plug](https://github.com/junegunn/vim-plug), add this inside your
`plug#begin()` / `plug#end()` block, run `:PlugInstall`, and restart Neovim:

```vim
Plug 'XinqiBao/lilt.nvim'
```

Other plugin managers work too. No particular Neovim configuration or distribution
is required.

## Start reading

Run `:LiltGhost`, press `i`, and copy the reference. Press Enter at its line
breaks, including blank paragraph rows. Your usual motions, operators, search,
and undo work on what you have typed; comparison never changes it.

| Command | Action |
| --- | --- |
| `:LiltGhost` | Open or switch to Ghost |
| `:LiltSplit` | Open or switch to Split |
| `:LiltClose` | Close the session; retain your manuscript |

**Ghost** blends the remaining reference into your writing and displays future
lines below it. Earlier unfinished lines stay visible. Mistakes receive subtle
highlights; pause on one in Normal mode for about 250 ms to see an Expected /
Typed hint. Moving, editing, or leaving the window dismisses it. Future reference
lines are virtual: use Split to navigate or search ahead.

**Split** opens a protected reference pane beside your manuscript when both fit,
or above it at narrower widths. The panes wrap and scroll independently. Use
native `<C-w>` commands to move or resize them. Resizing preserves your chosen
view and layout. Requesting the active view again focuses the manuscript and
keeps your layout and reference position.

## Keep your writing

**Save with `:write /path/to/manuscript.txt` before quitting.** The file contains
only what you typed. Lilt does not save automatically or restore a session across
Neovim processes.

The reading session opens in a separate tab. Both views share one manuscript;
closing and reopening retains it and its undo history for this Neovim process.
Find retained writing with `:ls` and `:buffer N`. To start fresh, wipe that buffer
with `:bwipeout` (`:bwipeout!` discards unsaved changes).

Closing an owned window or replacing its buffer ends the session. Unrelated
windows and buffers survive.

## Current limits

- The bundled passage is the opening of Lewis Carroll's *Alice's Adventures in
  Wonderland*. There is currently no content selector.
- Copy its physical line breaks. Extra or missing rows shift subsequent
  comparisons; there is no reflow or cross-line alignment. Punctuation matters.
- Ghost works best with **75 usable columns** for this sample. Narrower windows
  can clip reference text, and a short manuscript limits native scrolling. Split
  provides the full, browsable reference.
- Comparison works with UTF-8 codepoints. Repeated text can have ambiguous
  alignments; feedback cannot infer your intent. Complex graphemes and arbitrary
  tab or wide-character layout are outside the bundled English passage's scope.

## Appearance

Highlights follow your colorscheme and respect explicit overrides:

| Feedback | Highlight group / default link |
| --- | --- |
| Untyped reference | `LiltPending` → `Comment` |
| Replacement | `LiltError` → `DiagnosticError` |
| Extra authored text | `LiltExtra` → `DiagnosticWarn` |
| Missing text | `LiltMissing` → `DiagnosticUnderlineWarn` |

Equal text uses the normal foreground. For an omission, Ghost underlines the
next real character; Split marks the missing reference text.

[Development and verification](DEVELOPING.md) · [Design contracts](doc/design.md)

Plugin code is [MIT licensed](LICENSE). The public-domain literary work is
[attributed separately](samples/README.md).
