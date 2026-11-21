# Online source adapters

Discover online browses content categories and searches participating sources
together. Each source advertises the categories and operations it supports;
browse-only sources remain available without joining search. Source adapters
own source semantics; shared acquisition owns temporary storage, identity reuse,
cancellation and publication. There is no user provider registration. The
`catalog` setup option overrides Gutenberg's Gutendex server only.

| Source | Discovery | Acquisition |
| --- | --- | --- |
| [Project Gutenberg](works.md#online-acquisition) | Popular, newest, poetry, short stories, title/author search through Gutendex | EPUBs marked public domain in the USA, from its PGLAF mirror |
| [Unglue.it](sources/unglueit.md) | Popular/new EPUB feeds; eligible English copies, with explicit copy choices | Advertised direct EPUBs with recognized per-copy rights |
| [PoetryDB](sources/poetrydb.md) | Random poetry, poet groups and title/author search | One poem as native text; original full JSON retained |

Online requests require curl on PATH; acquiring EPUBs also requires Pandoc
3.1.1+. PoetryDB needs only curl. Saved library works remain available offline
without either tool.

## Discover layout

Discover keeps each work on one row, giving titles priority and using spare
space for muted authors. Narrow lists truncate with an ellipsis; open Work
information for complete metadata. Native `/` searches visible text; `s`
searches the catalogs by title or author.

These layout examples use controlled catalog data and gruvbox, rendered from
native Neovim redraw grids with the fonts named in each image. They illustrate
normal and narrow layouts; they are not live catalog or terminal screenshots.

![Discover at 80 columns: one row per work with titles and muted authors](../assets/discover-normal.png)

[View the narrow, 64-column example](../assets/discover-narrow.png).

## Internal contract

`lua/lilt/online/providers.lua` explicitly constructs the installed providers
through `list(catalog)`.
Each module under `online/providers/` supplies `id`, official display `name`,
`browse` and `prepare(entry, directory, callback)`. Gutenberg exposes
`new(catalog)` to bind its existing catalog override. `browse` is a table of
optional category functions `(cursor, callback)`. Search is an optional
`search(text, cursor, callback)` function; group expansion is an optional
`expand(query, callback)` function. An absent operation means unsupported,
rather than a successful empty response. There is no provider menu.

| Category ID | Label | Gutenberg | Unglue.it | PoetryDB |
| --- | --- | --- | --- | --- |
| `explore` | Explore | Most downloaded | Popular EPUBs | Random poems |
| `poetry` | Poetry | Poetry topic | — | Random poems |
| `short_stories` | Short stories | Short stories topic | — | — |
| `recent` | Recently listed | Descending catalog IDs | New EPUBs | — |
| `poets` | Browse poets | — | — | Author groups |

Gutenberg and PoetryDB support title/author search. Unglue.it supports browsing
and copy-group expansion only. PoetryDB expands exact author groups. Category
IDs and labels use the fixed vocabulary above; callers display supported ones.

Each operation returns a cancellation function and completes with
`callback(err, page)`. The initial cursor is `nil`; a returned `next` cursor is
opaque to callers and passed to the same category or search operation. A page
contains `entries`, optional `next`, and optional honest `title`, `count` or
`empty` explanation. Group expansion can also return `previous` and remains a
single-source page. Counts must describe the selection honestly: filtered feeds
retain eligible results versus raw records in adapter page metadata and omit
unknown eligible totals. These source titles/counts provide adapter context;
they are not permanent rows or headings in unified results. Random batches
offer another sample, without implying exhaustive pagination or a total.

Entries are either `{kind='group', id, label, query}` or work entries with
`kind='work'`, `title`, `authors`, `source={provider,id,url}`, `supported`, and
`availability`. Optional manifest bibliography and adapter-private fields may
also be present. A work may supply `label` to distinguish acquisition copies
while keeping its original `title`. UI passes work entries intact to preparation
and never interprets their private fields. Group IDs are stable within a provider:
PoetryDB uses the exact author name, and Unglue.it the official work URL. Group
queries go unchanged to that provider's `expand` function. Groups push their own
pages; back returns to the preserved results.

The discovery coordinator accumulates category/search results from eligible
sources and deduplicates exact provider/type/identity only. Works use
`source.provider/id`; groups use the provider and group `id`. It does not merge
works inferred to be the same across sources or invent a combined catalog total.

`prepare` receives an absent output directory inside a shared-owned temporary
parent. It returns a cancellation function and completes with
`callback(err, prepared)`. All prepared results have:

```lua
{
  manifest = { version = 1, title = '...', source = { ... }, units = { ... } },
  snapshot = {},       -- source-owned JSON-compatible provenance envelope
  attribution = {},    -- readable source credit/license lines
  import_warnings = {},
}
```

The adapter writes reference files and retains original source artifacts in that
directory. `manifest.source.file` points to the original artifact. Shared
acquisition checks provider/id against the selected entry, writes final
`lilt.json`, `SOURCE.json` and `README.txt`, validates, and installs through
`library.add`. Adapters never receive the library root or chosen directory name
and must not install, overwrite, or allocate a second acquisition staging tree.
The shared entry point is `acquire.acquire(root, provider, entry, callback, name)`;
`acquire.existing(root, entry)` looks up provider/id without downloading.

Callbacks run on Neovim's main loop once unless cancelled. Cancel functions
suppress delivery and release subprocess/request resources. Shared acquisition
owns staging cleanup even after partial initialization or failure.

## Materialization helpers

`require('lilt.online.materialize')` provides two concrete helpers. `metadata`
contains manifest bibliography/source fields, not a provider entry or snapshot.
Both helpers return the prepared envelope above with empty snapshot/attribution;
the adapter supplies those source facts before delivering its result.

- `epub(url, directory, metadata, options, callback)` returns `cancel()` and calls
  `callback(err, prepared)`. It checks Pandoc, downloads through the bounded
  request primitive, retains `SOURCE.epub`, converts local input, and sets
  `manifest.source.file`. Options are `filter` and `plain_quotes` only.
- `text(lines, directory, metadata)` returns `prepared` synchronously or raises
  an error. It creates one `001.txt` unit and records `plain_quotes=false`.
  Rows preserve spaces, Unicode punctuation and blank entries, including final
  blank rows. Invalid UTF-8, NUL and embedded CR/LF are rejected. Exact readback
  is checked; a leading BOM that the work reader strips is rejected. The adapter
  retains original JSON and sets `manifest.source.file` before completion.

Source provider/id identify the selected work/copy independently of personal
directory spelling. Returned identity must match selection. Source URLs and
rights are readable offline; raw provenance belongs in retained artifacts and
SOURCE.json, not in the manifest. Gutenberg retains its existing
`{catalog_url, entry}` snapshot envelope; new adapters use documented concrete
envelopes and retain original OPDS/JSON responses.

`source.version` optionally preserves a supplied acquisition/file revision;
shared information and README label it Source version. It does not change reuse
identity or imply a bibliographic edition.
Optional `source.title` is the advertised acquisition title, shown as Source copy
title in shared information and README. It also leaves identity unchanged.
Publication dates never stand in for ambiguous feed-update dates. Description
is plain text only; adapters omit marked-up descriptions rather than adding an
HTML interpretation layer.
