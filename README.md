# lilt.nvim

**Read at your own rhythm.**

Read literature by retyping it in Neovim. Lilt shows the passage alongside your
writing, with quiet feedback as you go. Your manuscript stays an ordinary buffer:
edit, undo, and save as usual.

![Choose a work, preview its text, type in Ghost, and browse in Split](assets/demo.gif)

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

To build a personal library, choose **Discover online…**, browse or search for a
work, then choose **Acquire and read**. For your own texts, choose **Add local
work…** and enter a [prepared work directory](doc/works.md). The path prompt
supports native directory completion with Tab.

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
  chapter through `:Lilt` to resume. Percentages count saved lines, not correctness;
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

- **curl** for online discovery; [Pandoc 3.1.1+](https://pandoc.org/installing.html)
  for acquiring new works. Both use `PATH`; local reading needs neither.
- [Gutendex](https://gutendex.com/) supplies the searchable catalog. Literary texts
  come from [Project Gutenberg](https://www.gutenberg.org/) through its designated
  PGLAF mirror. Acquired works remain available offline.

Check copyright in your country before downloading or sharing. Downloads retain
the original EPUB, credits, and license in `SOURCE.epub`; see [sources and redistribution
terms](doc/works.md#online-acquisition). Lilt is an independent client; Project
Gutenberg is a registered trademark. The plugin’s [MIT license](LICENSE) applies
to its code, separately from literary texts. Each bundled example records its
source and preparation in its own README.

## Further reading

- `:help lilt` — controls, library location, configuration, appearance, and limits.
- [Preparing a work](doc/works.md) — manifests, text layout, importing, and sharing.
- [Development](DEVELOPING.md) · [Design contracts](doc/design.md).
