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
  "version": 1,
  "title": "Winter Letters",
  "authors": ["A. Writer"],
  "units": [
    { "path": "opening.txt", "title": "The first letter" },
    { "path": "letters/02.txt", "title": "The reply" }
  ]
}
```

The manifest accepts exactly these fields:

- `version`: optional format version; when present, must be `1`. Lilt writes it
  in generated works.
- `title`: required nonempty single-line string, preserving the full source title.
- `authors`, `translators`, `languages`, `subjects`, `bookshelves`: optional arrays
  of nonempty single-line strings. Use source-provided names and language codes;
  do not infer missing bibliographic details. Empty arrays are allowed.
- `description`: optional plain text, allowing paragraph newlines and tabs;
  other control characters are rejected. This is source-supplied text, not HTML.
- `rights`, `publisher`, `published`: optional nonempty single-line source facts.
  Rights describe the source's claim; they do not establish universal permission.
  Publication text retains supplied precision; ambiguous feed-update dates are
  omitted. `rights_url` optionally links to an HTTP(S) license or rights notice.
- `source`: optional object with `provider`, `id`, and `url` strings. All three
  must be nonempty single-line strings; `url` must be an HTTP(S) URL. This is
  portable attribution, not a download or synchronization instruction. `provider`
  is a lowercase machine identifier such as `gutenberg`, starting with a letter
  and containing only ASCII letters, digits and hyphens. Optional `file` names
  an existing relative source file, with the same path rules as reference files.
  Optional `version` is a nonempty single-line acquisition revision supplied by
  the source. It is shown as Source version, not inferred as a bibliographic
  edition. Only provider/ID identify an existing library copy.
  Optional `title` is the source's nonempty single-line advertised acquisition
  title, labeled Source copy title; it is not a personal alias or inferred edition.
- `preparation`: optional record of applied text processing. `wrap_columns` is
  an optional positive integer; `plain_quotes` is an optional boolean. Editing
  this record does not reconvert references.
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
acquisition records provenance and keeps the original artifact named by `source.file`.
Generated and installed manifests use two-space indentation, sorted object keys,
literal UTF-8 and a final newline. Array order is preserved. Personal directory
names, saved progress and last-opened state do not belong in this manifest.

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
  authors = { "Author" }, -- optional; other bibliographic arrays are accepted too
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

Pandoc parses/renders XHTML; bundled [SLAXML](../lua/lilt/vendor/README.md) reads XML
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

Add a prepared directory through `:Lilt` → **Add local work…**, then enter its
path. The next input offers the full source title as an editable directory name
and previews the normalized result. Enter accepts; Escape cancels without
installing anything. Names must be unique; collisions leave the input editable.
The Picker keeps the official title and authors. Press `i` from the reading-unit
page for Work information, including the actual directory and recorded text
preparation. The original input is not added to book metadata.

Directory spelling follows these rules:

- ASCII capitals become lowercase; non-ASCII letters and combining marks remain.
- Straight/curly apostrophes are removed. Whitespace, underscores, punctuation
  and emoji become single hyphens, trimmed at both ends.
- The title portion is limited to 120 UTF-8 bytes at a codepoint boundary.
- Works with a source append its normalized provider and ID, for example
  `Little Women` becomes `little-women-gutenberg-37106`. No usable title characters
  falls back to the source suffix. Unsourced works need a usable name.
- Reserved portable names such as `con` and `com1` are rejected. No automatic
  `-2` suffix or semantic title/subtitle splitting is performed.

The source provider and ID identify an installed source entry independently of
the directory name. Adding that entry again opens the existing copy; multiple
installed matches are reported as ambiguous. A new spelling does not install a
second copy. Unsourced works are distinguished by their directory names.

Lilt validates and copies the whole
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
Discovery reads the filesystem; there is no registry. Share a prepared text by
sharing its reference work directory. For a personal backup or Git repository,
retain both `references/` and `manuscripts/` to preserve writing and progress.
Lilt performs no synchronization or Git operations. Changing metadata never
renames directories. After transcription begins, a directory rename must move
both corresponding trees, with their buffers closed. Keep unit paths and
reference line layout stable: those determine manuscript association and comparison.

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

Choose **Discover online…**, select a source, then choose a source-specific browse
or search action. Catalogs stay separate. Groups open a deeper list; next/previous
page replace the current list. Back restores the parent group or source menu,
then source selection. Failed requests offer retry; leaving cancels pending work.
Empty or cancelled search input preserves the current page.

Shared acquisition stages each new work, checks selected provider/ID against the
prepared source, validates all files, and checks names and identity again before
installation. The directory name is independent of the source's official title.
Matching provider/ID always reopens the saved copy without refreshing references.
Source-specific contracts and internal adapter signatures are in
[Online source adapters](sources.md).

### Project Gutenberg

Lilt uses [Gutendex](https://gutendex.com/), Gareth Johnson's
[open source catalog API](https://github.com/garethbjohnson/gutendex), for discovery.
Gutendex serves Project Gutenberg metadata; it does not supply Lilt's downloaded
texts. Those come from Gutenberg's designated
[PGLAF mirror](https://www.gutenberg.org/MIRRORS.ALL). Project Gutenberg's
volunteers provide the digitized literary works and source credits.
Acquired works become ordinary library works with your chosen normalized name
and a `-gutenberg-<id>` suffix, available offline.
Acquiring one again opens the existing copy; references and manuscripts are never
updated or overwritten. Each copy records its source in `lilt.json` and
`README.txt`, and retains the original download, credits, and license in
`SOURCE.epub`. `SOURCE.json` preserves the raw catalog entry and its catalog URL,
including source fields that Lilt does not model. The manifest retains author and
translator names, languages, subjects, bookshelves and actual preparation settings.
Supplied descriptions, rights/license URLs, publisher/publication facts and source
versions are optional metadata. Absent or ambiguous facts are omitted. Rights are
the source's claim, not a universal licensing assertion.
These are acquisition snapshots, not live metadata synchronization.

Work information uses the saved manifest offline. It shows recorded bibliographic
and source fields, followed by local directory/preparation facts, omitting absent
fields. Online work details use the current catalog; they do not describe or
refresh an installed edition. The information page lists the path to SOURCE.json
when retained, for access to the fuller raw catalog snapshot; original source and
README attribution/license paths are also listed. Missing or older
snapshots do not block reading, and the page does not infer their age.

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
