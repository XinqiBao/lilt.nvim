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
- `toc`: optional nonempty navigation tree, described below.
- `units`: required nonempty array, in reading order. Each object has a required
  `title` and `path`. Titles follow the same rule as the work title.
- `path`: unique, relative reference-file path using `/`. No empty components,
  `.`, `..`, backslashes, colons, control characters, or absolute paths. Every
  component must exist within the work; symlinks are unsupported. The manifest
  itself cannot be a reading unit.

An optional `toc` preserves navigation independently of reading order:

```json
"toc": [
  {
    "title": "Part I",
    "children": [
      { "title": "The first letter", "path": "opening.txt" },
      { "title": "The reply", "path": "letters/02.txt" }
    ]
  }
]
```

Each entry has a `title` and a `path`, nonempty `children`, or both. Paths must
name entries in `units`; multiple navigation entries may share a unit. Nesting is
limited to 64 levels. The Picker displays the tree on one page, followed by any
units absent from it. Manuscripts and saved progress still belong to unit paths.
Works without `toc` use the ordinary unit list.

JSON comments, trailing commas, and unknown fields are rejected. Text files must
be UTF-8 without NUL bytes. A UTF-8 BOM and CRLF line endings are accepted. Empty
reference files are allowed, though usually not useful. Include source and
attribution and license information in a separate README when appropriate;
`source` alone does not establish licensing or public-domain status. Online
acquisition records provenance and keeps the original distribution in `SOURCE.epub`.

## Text preparation

Prepare physical lines for comfortable reading in an editor. Preserve paragraph
breaks as blank lines. Manuscripts must follow those physical rows, including
blank rows: Lilt compares by row, not by reflowed paragraph. Do not reformat or
replace references after transcription begins, insert unrelated notes in a
manuscript, or expect Lilt to repair extra/missing rows. There is no migration or
cross-line alignment. Comparison uses UTF-8 codepoints, not full grapheme layout.

## Convert a local EPUB

With [Pandoc 3.1.1+](https://pandoc.org/installing.html) on `PATH`, convert an EPUB
without network access:

```lua
require("lilt.import.epub").prepare("/path/book.epub", "/path/new-work", {
  title = "Book title",
  author = "Author", -- optional
  plain_quotes = true, -- optional; default preserves source punctuation
}, function(err, work)
  assert(not err, err)
  print(work.root)
end)
```

The input must be an existing local file; URLs are not accepted. The destination
must not exist and its parent must exist. Conversion creates
`lilt.json` and numbered UTF-8 reference files, validates the complete work, and
removes its output on failure. The input EPUB is unchanged. The returned function
cancels conversion. Add the resulting directory through **Add local work…**;
conversion does not install it or touch manuscripts. Retain your source EPUB and
any required credits/license separately.

Navigation uses EPUB 3 `toc nav`, then EPUB 2 NCX, resolving local paths and
anchors against the cleaned text. Source labels and nesting are retained;
unlinked groups need usable children. Missing, external, image-only, and removed
targets are omitted. Without usable navigation, body headings remain the fallback.
Without navigation or headings, units use the work title. Text before the first
heading is labeled `Front matter`.
Unlisted text stays available under **Other reading units**. A target inside a
paragraph or table opens the unit containing that intact block.

The linear spine determines body order; navigation aliases never duplicate text.
Long sections get numbered reading parts beneath their source chapter. Entries
sharing an opening unit list its parts once; aliases open the first part. Repeated
source labels and links are retained. Labels can differ from printed headings.
When a label reproduces a heading with a marked illustration caption, that
caption is excluded from the label and kept in the reference. EPUB identifiers
and styling attributes are excluded from rendered text. Prose wraps at 72 columns;
explicit verse/preformatted breaks remain.
Images are omitted. CSS-only layout and imperfect source editing can still limit
the result. Nonlinear resources are excluded; unsupported spine resource types
fail conversion explicitly.

Pandoc parses/renders XHTML; bundled [SLAXML](../pandoc/vendor/README.md) reads XML
package/navigation metadata. No separate XML tool is required. Malformed navigation
falls back to available structure; returned `work.import_warnings` reports that
fallback. Acquired copies retain these notes in `README.txt`.

`plain_quotes` changes only `“ ” ‘ ’` in reference text to keyboard quotes after
parsing. It does not rewrite unit labels or other punctuation. Local conversion
makes no language assumption.

Source cleanup is opt-in: `filter = "/path/source-filter.lua"` passes a Pandoc Lua
filter supplied by the caller. No filter or source detection is enabled by
default; Gutenberg's distribution markers are required only by its acquisition
filter. The scripts in `pandoc/` run inside Pandoc, not Neovim.

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
`SOURCE.epub`.

Only works cataloged as public domain in the USA with EPUB are supported.
Public-domain status varies by country; check your local law before downloading
or sharing. The plugin's MIT license does not relicense acquired texts.
[Project Gutenberg's license](https://www.gutenberg.org/policy/license.html) and
[permission guidance](https://www.gutenberg.org/policy/permission.html) explain
redistribution and use of its registered trademark. Keep the original credits
and license in `SOURCE.epub` with a shared work, and review those terms when
sharing prepared units. Lilt is an independent client, not an endorsed Project
Gutenberg or Gutendex product.

New acquisitions cataloged solely as English convert curly double quotes
(`“ ”`) to `"` and curly single quotes/apostrophes (`‘ ’`) to `'` for keyboard
input. Other punctuation, spelling, and accents are retained. Non-English,
multilingual, and unknown-language works keep their source punctuation.
`SOURCE.epub` always retains the original bytes; `README.txt` records preparation.
Existing acquisitions and local imports are not converted.

New acquisitions require [Pandoc 3.1.1+](https://pandoc.org/installing.html) on
`PATH`. Lilt runs `pandoc --version` before downloading, rejecting missing,
unusable, or older tools with installation guidance. Existing works and prepared
local imports need no Pandoc. See [local conversion](#convert-a-local-epub) for
navigation, text preparation, and rendering limits.

Acquisition supplies a separate Gutenberg filter to remove its marked
distribution header/footer. Unsupported or ambiguous boundaries fail without
installing a partial work. Ordinary local EPUB conversion needs no such markers.
Opening an existing work never downloads or repartitions its references.

Downloads have a 45-second timeout and a 12 MiB size limit. Conversion has its
own 45-second deadline and a 48 MiB prepared-text limit. Gutendex is a separate,
best-effort service; unavailable catalog entries or mirror files can be retried
later. Its maintainers recommend hosting your own server for long-term use;
set `catalog` to its HTTPS URL (see `:help lilt-setup`).
