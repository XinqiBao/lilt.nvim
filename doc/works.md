# Preparing a Lilt work

A work is a self-contained directory with a `lilt.json` manifest and plain UTF-8
reference files. It can hold a poem, essay, novel, or any ordered collection of
reading units.

Example layout:

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

The manifest accepts exactly these fields:

- `title`: required nonempty single-line string.
- `author`: optional nonempty single-line string.
- `source`: optional object with `provider`, `id`, and `url` strings. All three
  must be nonempty single-line strings; `url` must be an HTTP(S) URL. This is
  portable attribution, not a download or synchronization instruction.
- `units`: required nonempty array, in reading order. Each object has a required
  `title` and `path`. Titles follow the same rule as the work title.
- `path`: unique, relative reference-file path using `/`. No empty components,
  `.`, `..`, backslashes, colons, control characters, or absolute paths. Every
  component must exist within the work; symlinks are unsupported. The manifest
  itself cannot be a reading unit.

JSON comments, trailing commas, and unknown fields are rejected. Text files must
be UTF-8 without NUL bytes. A UTF-8 BOM and CRLF line endings are accepted. Empty
reference files are allowed, though usually not useful. Include source and
attribution and license information in a separate README when appropriate;
`source` alone does not establish licensing or public-domain status. Online
acquisition records provenance and keeps the original distribution in `SOURCE.txt`.

## Text preparation

Prepare physical lines for comfortable reading in an editor. Preserve paragraph
breaks as blank lines. Manuscripts must follow those physical rows, including
blank rows: Lilt compares by row, not by reflowed paragraph. Do not reformat or
replace references after transcription begins, insert unrelated notes in a
manuscript, or expect Lilt to repair extra/missing rows. There is no migration or
cross-line alignment. Comparison uses UTF-8 codepoints, not full grapheme layout.

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
XDG default are described in the [README](../README.md#configuration):

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

## Online acquisition

Lilt uses [Gutendex](https://gutendex.com/), Gareth Johnson's
[open source catalog API](https://github.com/garethbjohnson/gutendex), for discovery.
Gutendex serves Project Gutenberg metadata; it does not supply Lilt's downloaded
texts. Those come from Gutenberg's designated
[PGLAF mirror](https://www.gutenberg.org/MIRRORS.ALL). Project Gutenberg's
volunteers provide the digitized literary works and source credits.
Acquired works become ordinary library works named `gutenberg-<id>`, available offline.
Acquiring one again opens the existing copy; references and manuscripts are never
updated or overwritten. Each copy records its source in `lilt.json` and
`README.txt`, and retains the original download, credits, and license in
`SOURCE.txt`.

Only works cataloged as public domain in the USA with plain text are supported.
Public-domain status varies by country; check your local law before downloading
or sharing. The plugin's MIT license does not relicense acquired texts.
[Project Gutenberg's license](https://www.gutenberg.org/policy/license.html) and
[permission guidance](https://www.gutenberg.org/policy/permission.html) explain
redistribution and use of its registered trademark. Keep the original credits
and license in `SOURCE.txt` with a shared work, and review those terms when
sharing prepared units. Lilt is an independent client, not an endorsed Project
Gutenberg or Gutendex product.

New acquisitions cataloged solely as English convert curly double quotes
(`“ ”`) to `"` and curly single quotes/apostrophes (`‘ ’`) to `'` for keyboard
input. Other punctuation, spelling, and accents are retained. Non-English,
multilingual, and unknown-language works keep their source punctuation.
`SOURCE.txt` always retains the original bytes; `README.txt` records preparation.
Existing acquisitions and local imports are not converted.

Source editions vary: Lilt preserves indentation, wraps long unindented lines,
and uses recognizable headings and paragraph breaks for units. Poetry/drama
identified by catalog subjects keeps even long lines intact. These layout
heuristics can miss chapter boundaries or wrap long verse embedded in prose.
Plain-text illustration labels and emphasis marks remain; images and EPUB/HTML conversion
are unsupported. Missing text boundaries or invalid encoding fail safely.
Requests have a 45-second timeout and a 12 MiB size limit. Gutendex is a separate,
best-effort service; unavailable catalog entries or mirror files can be retried
later. Its maintainers recommend hosting your own server for long-term use;
set `catalog` to its HTTPS URL (see `:help lilt-setup`).
