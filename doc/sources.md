# Online source adapters

Discover online selects a source before entering its menu or browser. Source
adapters own source semantics; shared acquisition owns temporary storage,
identity reuse, cancellation and publication. There is no federated search or
user provider registration. The `catalog` setup option overrides Gutenberg's
Gutendex server only.

## Internal contract

`lua/lilt/online/providers.lua` explicitly constructs the installed providers
through `list(catalog)`.
Each module under `online/providers/` supplies `id`, official display `name`,
`menu`, `browse(query, callback)` and `prepare(entry, directory, callback)`.
Gutenberg exposes `new(catalog)` to bind its existing catalog override.

Menu rows have `{label, query, input?}`. An input row opens native search editing
and places submitted text in `query.search`; other query fields are opaque to
the UI. Cancelled or empty input preserves the current location.

`browse` completes with `callback(err, page)` and returns a cancellation function.
A page contains `title`, `entries`, optional `next`/`previous` queries, optional
known `count`, and optional `empty` explanation. Counts must describe the shown
selection honestly: filtered feeds should explain eligible results versus raw
records in their page title and omit unknown eligible totals.

Entries are either `{kind='group', label, query}` or work entries with
`kind='work'`, `title`, `authors`, `source={provider,id,url}`, `supported`, and
`availability`. Optional manifest bibliography and adapter-private fields may
also be present. A work may supply `label` to distinguish acquisition copies
while keeping its original `title`. UI passes work entries intact to preparation
and never interprets their private fields. Groups push locations; continuation
replaces the current page. Back returns to the parent group/menu.

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
