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
  cmd = { "Lilt", "LiltGhost", "LiltSplit", "LiltClose" },
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

Run `:Lilt`. Choose a library work, then a chapter. For a first try, choose
**Example: Alice (temporary manuscript)**. Press `i` and copy the reference,
pressing Enter at its physical line breaks, including blank paragraph rows.
Your usual motions, operators, search, and undo work on what you have typed;
comparison never changes it.

To build your collection, choose **Add local work…** and enter a prepared work
directory. Lilt validates and copies it into `~/Lilt/references/`, then offers its
chapters. The source directory can be moved or deleted afterwards. Existing work
names are never overwritten. See [Preparing a Lilt work](doc/works.md) for the
small JSON manifest, text preparation, validation, attribution, and sharing.
There is no online search or document conversion.

No configuration is required. To choose another library directory:

```lua
require("lilt").setup({ library = "~/Books/Lilt" })
```

For lazy.nvim, put the same setting in `opts = { library = "~/Books/Lilt" }`.

| Command | Action |
| --- | --- |
| `:Lilt` | Browse works, add a local work, or try Alice |
| `:LiltGhost` | Resume or switch to Ghost; try Alice if nothing is retained |
| `:LiltSplit` | Resume or switch to Split; try Alice if nothing is retained |
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

For library works, **save with `:w`**. Each chapter opens a normal named buffer
under `~/Lilt/manuscripts/<work>/<unit-path>`. Parent directories are created on
write; opening a chapter does not create a manuscript file. Quit normally, then
run `:Lilt` and select the same chapter in a later Neovim process to continue.
Chapter percentages count saved lines, including blank rows; `—` means no saved
manuscript. Unsaved edits are not included in progress.

Both views share that manuscript. Switching chapters or using `:LiltClose`
retains loaded buffers and their native undo histories. Find them with `:ls` and
`:buffer N`. Closing a session does not save; modified hidden manuscripts still
block an ordinary `:qall`. Use `:w` to save or normal Neovim commands to explicitly
discard changes. Lilt has no autosave or separate save command.

The Alice example uses an unnamed editable buffer and needs no writable library
or plugin directory. Its writing is retained only for this Neovim process. Save
it manually with `:write /path/to/alice-manuscript.txt` if desired; the example
picker does not automatically resume that file. To make Alice durable in the
library, add the plugin's `samples/` directory as a local work.

Reading opens in a separate tab. Closing an owned window or replacing its buffer
ends the session. Unrelated windows and buffers survive.

## Current limits

- Copy its physical line breaks. Extra or missing rows shift subsequent
  comparisons; there is no reflow or cross-line alignment. Keep references and
  their paths stable after starting; unrelated notes and reformatting are
  unsupported. Punctuation matters.
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
