# Preparing a Lilt work

A work is a self-contained directory with a `lilt.json` manifest and plain UTF-8
reference files. It can hold a poem, essay, novel, or any ordered collection of
reading units. JSON uses Neovim's built-in parser; Lilt needs no TOML dependency.

For example, prepare this directory:

```text
winter-letters/
├── lilt.json
├── opening.txt
└── letters/
    └── 02.txt
```

`lilt.json`:

```json
{
  "title": "Winter Letters",
  "author": "A. Writer",
  "units": [
    { "path": "opening.txt", "title": "The first letter" },
    { "path": "letters/02.txt", "title": "The reply" }
  ]
}
```

`opening.txt` might contain:

```text
The snow arrived before your letter.
I left the lamp beside the window.

Tomorrow I will write again.
```

A single poem needs only `lilt.json` and one text file, with one entry in `units`.

The manifest accepts exactly these fields:

- `title`: required nonempty single-line string.
- `author`: optional nonempty single-line string.
- `units`: required nonempty array, in reading order. Each object has a required
  `title` and `path`. Titles follow the same rule as the work title.
- `path`: unique, relative reference-file path using `/`. No empty components,
  `.`, `..`, backslashes, colons, control characters, or absolute paths. Every
  component must exist within the work; symlinks are unsupported. The manifest
  itself cannot be a reading unit.

JSON comments, trailing commas, and unknown fields are rejected. Text files must
be UTF-8 without NUL bytes. A UTF-8 BOM and CRLF line endings are accepted. Empty
reference files are allowed, though usually not useful. Include source and
attribution information in a separate README when appropriate; Lilt does not
infer provenance, licensing, or public-domain status.

## Text preparation

Prepare physical lines for comfortable reading in an editor. Preserve paragraph
breaks as blank lines. Manuscripts must follow those physical rows, including
blank rows: Lilt compares by row, not by reflowed paragraph. Do not reformat or
replace references after transcription begins, insert unrelated notes in a
manuscript, or expect Lilt to repair extra/missing rows. There is no migration or
cross-line alignment. Comparison uses UTF-8 codepoints, not full grapheme layout.

For an AI assistant, a suitable request is: “Prepare this permitted source as a
self-contained Lilt work following doc/works.md. Preserve the text and paragraph
breaks, choose readable physical line lengths, record the actual source and
license in README.md, and validate the directory. Do not invent source claims.”

## Validation

From Neovim with Lilt on the runtime path:

```lua
local work = require('lilt.work').validate('/path/to/winter-letters')
print(work.title, #work.units)
```

Validation checks the entire manifest and all reference bodies, reporting errors
with their paths. Adding through `:Lilt` validates the staged copy before
publishing it. Discovery reads manifests and inspects paths without opening
reference bodies; opening a reading unit validates that selected text.

## Personal library and sharing

The library contains ordinary user-owned files; its configurable location and
XDG default are described in the [README](../README.md#start-reading):

```text
<library>/
├── references/
│   └── winter-letters/          # manifest, reference text, attribution
└── manuscripts/
    └── winter-letters/
        ├── opening.txt         # your writing, created by :w
        └── letters/
            └── 02.txt
```

Each work directory name must be unique, nonhidden, and contain no backslash,
colon, or control character. Add a prepared directory through `:Lilt` →
**Add local work…**, then enter its path. Lilt validates and copies the whole
work, including attribution files, into `references/`. It does not keep an
external link. Symlinks and special files anywhere in the copied directory are
rejected. Existing reference directories or manuscript trees with that work
name are never merged or replaced. Failed copies are cleaned up before they
become visible. One invalid work in the library does not hide valid works;
the picker reports manifest/path errors. Invalid reference text is reported
when opening that unit; discovery does not scan its body.

Installation copies into a hidden staging directory, validates that copy,
rechecks name collisions, then publishes it with a same-directory rename. This
keeps partial copies out of discovery; it is not a crash-durable transaction or
a lock against concurrent external changes. An interrupted process can leave a
hidden `.lilt-*` directory under `references/`; after stopping that import, it
can be removed. Ordinary failures attempt cleanup and report any cleanup error.

You can also place a valid work directory directly beneath `references/`.
Discovery reads the filesystem; there is no registry. Share or archive only that
work directory, never its corresponding `manuscripts/` tree. External Git or sync
tools can manage the library; Lilt performs no synchronization or Git operations.
Rename work directories or unit paths only before starting transcription: those
paths determine manuscript association.

Unit progress uses **saved** manuscript rows divided by reference rows, rounded
down to an integer percentage. Counts scan file bytes in bounded chunks without
constructing arrays of text. A missing manuscript displays `—`; an empty saved
file has zero rows. An empty reference uses a denominator of one. Blank rows
count, a final newline does not add a row, and values above 100% are allowed.
Progress is a navigation hint, not a correctness check. A file-counting error
displays `?` for that unit without hiding its siblings; selecting it reports the
error. Unsaved edits appear in the loaded buffer but do not affect the displayed
saved percentage.

Native `:w` creates parent directories for the manuscript's current name, including
a name chosen with `:saveas`. Using `:saveas` does not change the reading unit's
library association: later selection still derives the original manuscript path.
An explicit `:write other/path.txt` is an ordinary Neovim export; create that
other path's parents yourself.
