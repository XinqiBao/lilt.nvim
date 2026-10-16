# Comparison and reading findings

The manuscript is the single authoritative editable Neovim buffer. Reference
text is a session snapshot; all decorations and comparisons derive from those
two sources. There is no Lua manuscript mirror, typing interception, or content
repair. Full redraw after edits remains intentional for the short prepared lines.

## Alignment contract

`compare.line` returns coalesced Equal, Pending, Replace, Extra, and Missing
spans with zero-based, exclusive reference and manuscript byte ranges, plus
an aligned reference coverage boundary and pending suffix. Comparisons use
UTF-8 codepoints, never byte positions as character indexes. Extra spans have
zero reference width; Missing and Pending have zero manuscript width.

Each physical row uses semi-global Levenshtein alignment: all manuscript
characters are consumed; the remaining reference suffix costs nothing and is
Pending. Internal reference deletions are Missing. An exact leading prefix is
fixed first. Among minimum-cost paths, prefer more equal characters, then a
coverage endpoint nearest the manuscript's character length, then the earlier
endpoint. Remaining ties use Equal, Replace, Extra, Missing in that order.
This preserves an already matching prefix and makes repeated-character choices
reproducible without hidden typing history. The dynamic-programming table uses
O(reference length × manuscript length) time and space after the exact prefix.

Examples: `beau` / `beautiful` leaves `tiful` pending; `beat` omits `u`, matches
`t`, and leaves `iful` pending. `beatiful` has the same omission with no pending
suffix; `beauutiful` has one extra `u` after the exact prefix. `bold` / `cold`
replaces `c` with `b` and matches `old`.

This is a text-derived interpretation, not inferred intent. `little bird`
against `little little bird` is cheaper as three replacements within the second
word followed by pending text than as seven omissions. Trailing wrong characters
can change interpretation as more text arrives. No edit-distance method uniquely
identifies user intent. The chosen rules favor local corrections and predictable
prefixes over word-level inference.

Physical rows correspond literally. An early Enter leaves the preceding suffix
pending and starts the next reference row. Added/deleted line breaks shift later
comparisons. Blank surplus lines have no glyph to emphasize. There is no Unicode
normalization, grapheme engine, automatic reflow, or cross-row alignment. Prepared
line layout is part of the content contract: changing it can invalidate existing
manuscripts. Its maximum width is independent of current window dimensions.

## View behavior and APIs

Ghost uses inline virtual text at actual EOL and one `virt_lines` mark for all
reference rows after real EOF, including paragraph blanks. Pending text on
previous real rows remains visible. The coverage endpoint determines the suffix;
omitted reference characters never become inline placeholders. Extra authored
text remains visible, so Ghost does not preserve reference columns after errors.
Missing spans underline their next real character. Every Missing span precedes
an authored character because a trailing omission is Pending.

Neovim virtual lines are not buffer rows. `G`, search, scrolling, and selection
operate on authored text. A short real prefix also limits horizontal scrolling
into a long inline suffix. Ghost therefore recommends the longest prepared line
plus one cursor cell (75 columns for the sample). Narrow Ghost stays Ghost;
clipping is a documented limitation. Split permits unrestricted reference browsing.

Split creates a protected, unlisted scratch reference buffer and decorates its
actual text. Equal spans retain normal foreground; Pending is subdued; Replace
and Missing receive semantic emphasis. Extra text is highlighted only in the
manuscript. The reference is `modifiable=false`, `readonly=true`; this prevents
accidental changes, not deliberate option overrides. It has no Vim Diff Mode,
cursor synchronization, or scroll binding.

Initial Split orientation uses two comfortable prepared-line widths plus a
separator (151 columns here). Reference starts at the left when wide enough,
otherwise above. Both windows wrap with `linebreak`. There are no resize
callbacks or automatic view changes. Native rearrangement is supported because
ownership follows window IDs rather than screen positions.

Ghost hints use a 250 ms one-shot `vim.defer_fn` timer, cursor/mode events, and
shared alignment spans. Word context is projected through that alignment;
whitespace includes neighboring words. Long excerpts are clipped around the
selected difference at UTF-8 boundaries. The two-line, nonfocusable float uses
`nvim_open_win(..., false, ...)` and a scratch buffer. Missing spans associate
only with the immediately following real character. Equal/Pending text alone
never triggers a hint. Timers are stopped on invalidation; generation, active
view lifetime, window, buffer, changedtick, mode, and cursor checks reject stale
callbacks. Float cleanup is scheduled out of `on_lines` textlock. There is no
polling or tooltip framework. Very narrow windows can clip hint text too.

Neovim **0.11+** remains required for `virt_lines_overflow='scroll'`, which makes
future reference rows share native horizontal scrolling. Inline virtual text
exists in 0.10, but its API lacks this option. All APIs are public; there are no
decoration providers or custom layout/input engines.

## Ownership and lifecycle

`session.lua` owns the reference snapshot, retained manuscript, active view,
buffer attachment, session autocmds, and editor-state cleanup. `view/ghost.lua`
owns Ghost decoration, presentation, and hints. `view/split.lua` owns the
protected reference buffer/window, initial layout, and both panes' decorations.
`compare.lua` contains only alignment semantics. `render.lua` retains the shared
decoration namespace and clearing operation; `init.lua` exposes three methods
used by the commands in `plugin/lilt.lua`.

A separate session tab isolates the original layout. Closing an owned window,
repurposing either owned window, or wiping the active manuscript ends the
session. Reference resources, hint resources, extmarks, and autocmd groups are
released; the manuscript and its undo tree persist unless explicitly wiped.
Extra user-created windows are retained. A repurposed or final surviving window
restores options saved for that exact window; a reference window never receives
the manuscript window's snapshot. A single Lua attachment follows the manuscript
lifetime and is dormant outside sessions. `BufReadPost` reattaches after reload.
Scheduled lifecycle checks are scoped to their original session.

The reference buffer is a private session resource: keeping it in another user
window does not extend its lifetime. Deliberately overriding reference protection
or suppressing lifecycle autocmds is unsupported. Arbitrary user autocmd
interactions are not promised; ordinary native window, tab, editing, reload,
write, and undo operations are exercised.

## Verification

On Neovim **0.11.5** and **0.12.5**, using the commands in [README](../README.md):

- `tests/compare.lua`: 33 assertions with concrete alignments for all categories,
  partial internal omissions, repeated characters/words, ambiguity, blank and
  completed lines, UTF-8 punctuation, byte boundaries, and deterministic output.
- `tests/headless.lua`: 155 assertions exercising native edits, Enter, operators,
  structural edits, undo/redo, exact serialization, reload, retained buffers,
  repeated switches, reference progress/protection, independent cursors, native
  rearrangement, window replacement/closure, active wipe, unrelated buffers and
  windows, per-window restoration, autocmd cleanup, and extmark cleanup.
- `tests/ui.py`: 94 assertions against actual attached redraw grids, highlight
  attributes, and native input. Covers Ghost placement without duplicate virtual
  rows/placeholders, all semantic feedback, both Split layouts and resize
  stability, independent browsing, hint delay/cancellation/context/lifetime,
  no focus stealing, stale callbacks, dark/light default theme rendering,
  explicit highlight overrides, and resource cleanup.

A terminal smoke check also exercised the README launch, native typing, an
omission hint, Ghost/Split switching, writing only authored text, and closing.
The UI harness uses public RPC/UI APIs and development-only `pynvim`. No generated
screenshots, downloaded executables, or temporary experiments are tracked. The
0.11.0 minimum is based on public API availability; that exact patch version was
not run. No hosted CI workflows are configured.

Unverified: extended human reading comfort, arbitrary mappings/autocmds, mouse
use, very small terminal heights, complex Unicode, all third-party colorschemes,
and large works. Default dark/light rendering was checked; Gruvbox itself was
not exercised. Diagnostic foreground links improve visibility over the old
SpellBad-only link, but user palette preferences remain personal.

## Historical prototype experiments

The positional prototype at `bbdcb75` established native manuscript editing and
Ghost's real-row/virtual-future model. Its comparison, SpellBad error link,
above/below-only Split, and automatic narrow-window fallback are superseded.
The original 26 comparison, 131 headless, and 40 UI assertions passed on 0.11.5
and 0.12.5 before refinement.

The attached-UI experiment displayed 24 reference rows over one real empty row.
Native Enter promoted a future row to real text without moving later rows;
previous pending suffixes survived. Ctrl-E stopped near real EOF, confirming
that virtual future rows cannot supply unrestricted browsing.

Preallocating six real blank rows was rejected: Enter and `o` insert new rows,
`dd` removes them, Backspace joins them, and undo preserves native structure.
Blank placeholders serialize as real newlines and cannot be distinguished from
authored paragraph breaks without a second source of truth. Repairing them would
require intercepting editing or damaging the undo model. Likewise, routing input
to a separate hidden manuscript would undermine native editing; Split supplies
the ordinary visible separation instead.

## Manual reading check

1. Launch the README command at 80+ columns. Copy two rows with an error and an
   early Enter. Confirm previous suffixes and virtual future rows remain visible.
2. Try missing, extra, and replacement characters in an earlier word with `ciw`,
   `x`, `dw`, `.`, undo, and redo. Pause on an error in Normal Mode; check the
   hint, then enter Insert Mode and correct it yourself.
3. Switch to Split. Inspect progress, browse/search independently, and rearrange
   windows using native commands. Compare initial layout at 90 and 160 columns.
4. Narrow Ghost while typing. Confirm it stays Ghost and preserves actual input;
   explicitly choose Split to read clipped reference text.
5. Write a manuscript, reload it, switch repeatedly, close and reopen, then close
   the session tab manually. Inspect the file, undo tree, and unrelated windows.
6. Spend time reading with your preferred theme. Assess error visibility, hint
   usefulness, and comfort; automation cannot establish those preferences.
