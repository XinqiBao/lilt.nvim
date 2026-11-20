# lilt.nvim

**Read at your own rhythm.**

Read literature by retyping it in Neovim. No timers, scores, or streaks.
Just you, the words, and the pleasure of typing.

A poem, a page, or a few lines is enough. Pick it up again whenever you like.

![Preview The Tyger and work information, correct a typo in Ghost, and search the reference in side-by-side Split](assets/demo.gif)

Lilt keeps the passage in view and offers quiet feedback as you go. Your writing
stays an ordinary buffer: edit, undo, and save as usual.

## Features

- **Ghost:** untyped text recedes as you type. Pause over a mistake in Normal mode
  for a local hint; correct it with your usual editing commands.
- **Split:** browse or search the complete reference beside your manuscript.
- **Library:** find works online, add a local collection, or try bundled
  examples. Browse source chapter hierarchies and preview text before opening it.
- **Manuscripts:** save and resume chapters as plain text. Switching views or
  chapters preserves unsaved edits and native undo history.

## Install

Requires **Neovim 0.11.0+**. No setup call is required.

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "XinqiBao/lilt.nvim",
  cmd = { "Lilt", "LiltGhost", "LiltSplit", "LiltClose" },
}
```

[vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'XinqiBao/lilt.nvim'
```

## Usage

Run `:Lilt` and choose a work and unit. **Examples** offers an offline first try.
Retype the passage following its physical line breaks, including blank rows.

To build a personal library, choose **Discover online…**, search or browse a
content category, then select a work and choose **Add to library**. For your own texts,
choose **Add local work…** and enter a [prepared work directory](doc/works.md).
The floating path input supports directory completion with Tab / Shift-Tab; Enter accepts a
completion, then Enter opens the work. Paths may include `~` and spaces.
Adding a new work offers its official title as an editable directory name and
previews the normalized spelling. Provider and source IDs distinguish saved
copies; the library list keeps official titles and authors.

From a work's reading units, press `i` for **Work information**: saved book and
source details, directory, and recorded text preparation. This page works
offline; online details describe the current catalog, which can differ from
your saved copy. `h` / Backspace returns to the same reading unit.

The Picker uses native line motions. Enter / `l` selects an action, `h` /
Backspace goes back, and `q` / Esc quits. Shortcuts appear beside their actions.

| Command | Action |
| --- | --- |
| `:Lilt` | Open the library Picker |
| `:LiltGhost` | Switch the active reading to Ghost |
| `:LiltSplit` | Switch the active reading to Split |
| `:LiltClose` | Close the presentation; retain your writing |

### Save and resume

- **Library works:** use `:w`. In a later Neovim process, select the same work and
  unit through `:Lilt` to resume. Percentages count saved lines, not correctness;
  unsaved edits are excluded.
- **Examples:** manuscripts are temporary. Add an example directory as a local
  work for persistent progress.

Lilt does not autosave. Closing a session retains unsaved writing.

## Configuration

The library follows
[XDG data directory conventions](https://specifications.freedesktop.org/basedir/latest/).
To override its location:

```lua
require("lilt").setup({
  library = "~/Books/Lilt",
})
```

## Online sources

- **curl** for online discovery and downloads;
  [Pandoc 3.1.1+](https://pandoc.org/installing.html) also for EPUB acquisition.
  PoetryDB needs only curl. Both use `PATH`; local reading needs neither.
- [Project Gutenberg](https://www.gutenberg.org/) uses the searchable
  [Gutendex](https://gutendex.com/) catalog and its designated PGLAF text mirror.
  Acquired works remain available offline.
- [Unglue.it](doc/sources/unglueit.md) supplies popular/new EPUB feeds. Lilt
  lists eligible English copies with explicit rights and lets you choose among
  multiple downloads. Original EPUBs, catalog snapshots and notices are retained.
- [PoetryDB](doc/sources/poetrydb.md) offers author browsing and title/author
  search. Each poem becomes one plain-text unit with its original JSON retained.

Discover combines participating sources in one list, with a source label beneath
each result. **Load more** appends another batch; **Retry failed** retries failed
sources while keeping successful results. Search covers Gutenberg and PoetryDB;
Unglue.it contributes through browsing. Back returns to the category choices.
Source details, supplied rights and descriptions remain readable offline;
original downloads and source records are retained. See [online sources](doc/sources.md).

Check copyright in your country before downloading or sharing. EPUB acquisitions
retain `SOURCE.epub`; PoetryDB retains `SOURCE.poetrydb.json`. Source credits and
rights remain with the saved work; see [sources and redistribution
terms](doc/works.md#online-acquisition). Lilt is an independent client; Project
Gutenberg is a registered trademark. The plugin’s [MIT license](LICENSE) applies
to its code, separately from literary texts. Each bundled example records its
source and preparation in its own README.

## Further reading

- `:help lilt` — controls, library location, configuration, appearance, and limits.
- [Preparing a work](doc/works.md) — manifests, text layout, importing, and sharing.
- [Development](DEVELOPING.md) · [Design contracts](doc/design.md).
