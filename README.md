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
**Examples** → **Alice’s Adventures in Wonderland (sample)** → its reading unit.
Press `i` and copy the reference, pressing Enter at its physical line breaks,
including blank paragraph rows.
Your usual motions, operators, search, and undo work on what you have typed;
comparison never changes it.

To build your collection, choose **Add local work…** and enter a prepared work
directory. Lilt validates and copies it into the library’s `references/`, then
offers its chapters. The source directory can be moved or deleted afterwards. Existing work
names are never overwritten. See [Preparing a Lilt work](doc/works.md) for the
small JSON manifest, text preparation, validation, attribution, and sharing.
There is no online search or document conversion.

The picker is a centered float: `j/k` move, `Enter` or `l` selects, and `h`,
`Esc`, or `q` goes back (or closes at the library page). Native `gg/G` works too.
Selecting a work shows its ordered reading units and saved progress. Long titles
are clipped to fit; the picker resizes with the terminal.

The library defaults to `${XDG_DATA_HOME:-$HOME/.local/share}/lilt/` on Linux and
macOS; an unset or relative `XDG_DATA_HOME` uses the fallback. Loading or browsing
creates no directories.

No configuration is required. To choose another library directory:

```lua
require("lilt").setup({ library = "~/Books/Lilt" })
```

For lazy.nvim, put the same setting in `opts = { library = "~/Books/Lilt" }`.

| Command | Action |
| --- | --- |
| `:Lilt` | Browse works, add a local work, or try Examples |
| `:LiltGhost` | Switch the active reading to Ghost |
| `:LiltSplit` | Switch the active reading to Split |
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
under `<library>/manuscripts/<work>/<unit-path>`. Parent directories are created on
write; opening a chapter does not create a manuscript file. Quit normally, then
run `:Lilt` and select the same chapter in a later Neovim process to continue.
Chapter percentages count saved lines, including blank rows; `—` means no saved
manuscript. Unsaved edits are not included in progress.

Both views share that manuscript. Switching chapters or using `:LiltClose`
retains loaded buffers and their native undo histories. Find them with `:ls` and
`:buffer N`. Reopen reading content through `:Lilt`; Ghost/Split only switch an
active presentation. Closing a session does not save; modified hidden manuscripts still
block an ordinary `:qall`. Use `:w` to save or normal Neovim commands to explicitly
discard changes. Lilt has no autosave or separate save command.

Bundled examples are ordinary works under `examples/`. Choose **Examples**, then
a work and reading unit, even when there is only one:

- [Alice](examples/alice/): a novel excerpt with wrapped prose and paragraph breaks.
- [The Tyger](examples/tyger/): Blake's short verse lines and six stanzas.
- [Fables](examples/fables/): two brief Aesop selections for trying unit navigation.

Each unit gets an unnamed editable manuscript, reused within this Neovim process. Wiping that buffer starts
fresh; nothing is written into the plugin installation. Save manually with
`:write /path/to/file.txt` if desired (create its parents first). The example
still reuses that buffer in this process, but does not automatically reopen the
saved file in a later process. To make Alice durable in the library, add the
plugin's `examples/alice/` directory as a local work.

Reading opens in a separate tab. Closing an owned window or replacing its buffer
ends the session. Unrelated windows and buffers survive.

## Current limits

- Follow the reference’s physical line breaks. Extra or missing rows shift
  subsequent comparisons; there is no reflow or cross-line alignment. Keep references and
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

Plugin code is [MIT licensed](LICENSE). Literary texts are public domain in the
United States and in life-plus-70 jurisdictions; each example's README records
its attribution, source, and preparation.
