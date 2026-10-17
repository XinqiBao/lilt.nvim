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
local work = require('lilt.work').load('/path/to/winter-letters')
print(work.title, #work.units)
```

Loading validates the entire manifest and all referenced files, reporting an
error for malformed input. Adding through `:Lilt` performs the same validation.
