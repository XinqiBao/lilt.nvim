# Design contracts

The ordinary listed manuscript buffer is the only authored-text authority.
Reference text is a session snapshot. Comparisons, highlights, hints, and virtual
lines are disposable derived state. Lilt never intercepts typing or repairs text.

`work.lua` parses self-contained JSON works, discovers immediate work
directories, validates selected reference text, and counts physical rows.
An optional `toc` refers to those units through a separate local navigation tree.
Aliases share the unit object; grouping has no manuscript or progress of its own.
Discovery reads manifests and checks file metadata only. Installation validates
all reference bodies in the staged copy; opening a unit rechecks its path and
validates that text. JSON uses Neovim's built-in parser without vendored code.

`library.lua` installs local copies through hidden staging and derives manuscript
paths and saved progress. `init.lua` holds configuration and command entry
points. `picker.lua` coordinates local work/unit navigation and retains only
example buffer handles. `picker/discover.lua` owns online navigation; it uses
the `online/` modules without involving reading views. `picker/ui.lua` owns the
scratch float, selection, page stack, search editor, and request lifetime.

Menu rows distinguish informational text from actions. Native line movement
reaches every row, including headings, metadata, and blank separators; gg/G
reach the first/last line. Only actions activate and receive cursor-line
highlighting. Menus initially prefer an action; information pages start at
the title so identity and availability can be inspected before acquisition.
New pages reset the shared window's scroll. Returning, cancelling search, and
resizing retain the cursor item and its wrapped-line offset (clamped when text
reflows). Work-information, online bibliographic fields and Discover result
titles/authors wrap completely, including unspaced UTF-8 and URLs. Local work and
unit labels remain bounded. Duplicate local titles show directory names only
when needed to distinguish them. Unit percentages report saved rows.

`picker/information.lua` formats shared bibliographic/source facts as inert page
items. Online details label current catalog metadata and retain their acquisition
actions. Local unit pages expose Work information with i, using only the saved
manifest, followed by local directory and recorded preparation settings. Back
restores the selected unit and viewport. Optional SOURCE.json is exposed by file
location without parsing arbitrary provider fields, network requests or schema
expansion. Viewing information never changes references, metadata or manuscripts.

Action-local shortcut keys are displayed with their labels and active only on
that page. Pending acquisition disables actions; pending catalog requests keep
search and navigation available so a new query can replace the request.
q/Escape exits from any menu, while h/Backspace goes back. Escape in a
search/name/path editor cancels only that input.

Unit selection automatically previews a local reference excerpt. The UI owns a
single passive float through `picker/preview.lua`; it never receives focus or
mappings. Wide terminals place it beside the unit list; narrower terminals with
enough height place it below. Very small terminals keep only the list. The list
and preview form one centered layout, and resizing retains the selected unit.
There is no separate preview page or reading/navigation state.

Preview reads the selected reference through `work.read_unit`, keeps only the
last selection's text, and puts at most one viewport of physical rows in the
protected scratch buffer. Source paths and UTF-8 still receive the normal
validation. Read failures appear in the preview without notification spam and
leave navigation usable. Leaving the unit list releases the preview resources.
Moving onto information replaces the excerpt with a prompt to select a unit.
It never opens a manuscript or comparison. Online details never download text
for previews.

Catalog search, local paths and directory naming edit one line in the existing
float and preserve the page behind it until submission. Prompt callers own
validation and completion semantics. Local paths use Neovim's directory
completion through Tab / Shift-Tab and expand tilde/environment variables
without interpreting filename glob characters. Enter accepts a visible
completion before submitting; Escape cancels the input and restores selection.
Invalid paths stay editable with feedback. There is no global UI override.
Discover immediately opens Explore with Search (s) and Browse categories (b)
above the content heading. The category menu includes only supported categories.
Selecting the current category retains the feed without a request; changing it
replaces the browse layer. Search pushes one layer above browse; query edits
replace that search layer. Back restores the exact browse selection and viewport.
Choosing a category from search returns to browse before applying the category.
Back from browse returns directly to the library; category/query edits do not
accumulate history. Results keep complete wrapped titles/authors. A muted short
source label (Gutenberg, Unglue.it, PoetryDB) aligns right on the first visual row.
The whole page omits hints when fewer than 48 display columns would remain for
content after the action indent, source column and two-column gap. Each page
reserves the participating sources' widest hint before requesting results, so
later peers cannot reflow earlier entries at a fixed width. Continuation
rows retain the same item identity. Short names belong to presentation; official
names and source identities remain in Work information. Groups end in › to
advertise expansion; copy labels remain source-supplied.
Load more appends a batch, while Retry failed requests only failed sources.
Both actions are omitted while a batch is in flight. Groups push a provider's
own page with Previous/Next actions; work details add one level and acquired units
use the shared local flow. Returning restores result selection and viewport.

Progress appears only in the always-visible footer: Loading for the entire initial
batch (including partial arrivals), Loading more for explicit paging, Retrying
for failure recovery. Cancelled incomplete sources show Paused at the heading.
Footer navigation adapts to available width; failed settled batches include an
r retry hint even in
28-column terminals. Progress stays visible when paging from the bottom of long
lists, without duplicating the heading or following scroll position. Partial
successes stay usable; failures remain summarized
near the content heading with complete source causes in scrollable rows. Empty completed
searches say No matching works found; failures say Could not complete search
rather than claiming zero matches. Empty browse batches can still offer Load more.
Search shows one muted Some collections are browse-only note. No cross-provider
ranking or combined catalog totals are inferred. Local discovery errors wrap
completely so native scrolling reaches the full cause.

`name.lua` converts a user-chosen title into directory spelling; it knows neither
library files nor UI. `picker/name.lua` supplies editable official-title defaults,
previews spelling, and checks collisions through `library.available`. Input is a
directory preference, not bibliographic metadata. Source suffixes distinguish
editions; `library.find_source` identifies installed entries by provider/ID rather
than reconstructing paths from mutable titles. Ambiguous source matches fail
explicitly. Publication rechecks both names and identity. Original titles and
author arrays remain in `lilt.json`; installed directories never follow metadata
edits automatically.

`json.lua` writes deterministic, indented UTF-8 JSON using native scalar encoding;
Neovim 0.11 does not support native encoder indentation. Conversion and installation
format manifests without changing array order or reference bodies. Acquisition
also retains the complete catalog record in `SOURCE.json`; modeled metadata and
preparation settings are snapshots, never instructions to refresh a reading copy.

`online/providers.lua` explicitly lists source adapters. Optional capabilities,
group/work entries and opaque continuation cursors use the small contract in
[sources.md](sources.md). `online/catalog.lua` validates Gutendex metadata for
the Gutenberg adapter. `online/materialize.lua` shares bounded EPUB download and
local conversion, or writes exact plain-text rows without Pandoc.
`online/acquire.lua` owns staging, checks returned identity against selection,
persists metadata/attribution, and delegates publication to `library.add`.
Adapters own source semantics and original artifacts; they never see the library
root or personal directory name. EPUB sources use `online/request.lua` for bounded,
cancellable requests.
The optional manifest `source` records portable attribution; a matching
provider/id permits reopening an existing copy without fetching or changing its
reference edition. Colliding local works and orphan manuscripts block acquisition.

The picker owns each asynchronous request's cancellation function. Back, leaving
the picker, and editor exit cancel it; callbacks also check page/picker lifetime.
Requests use argument-vector curl, HTTPS-only redirects, time/size limits and
owned temporary files. `online/discovery.lua` coordinates independent provider
cursors, progressive results, exact identity deduplication and failure retries.
It has no UI or acquisition dependencies. Picker requests wrap its updates and
completion in the existing page generation. Input retains the running request;
updates never replace its buffer or focus. Navigation invalidates callbacks before
cancelling and updates cached results to offer resumption without stale Loading.
Stable result items preserve selection and scroll as peers finish. Activating
Load more or Retry failed retains the existing result boundary while the action
is hidden. Group continuation replaces only its source's current page.
There is no background polling, persistent catalog cache, or remote reading state.

`import/epub.lua` is a local-file converter: `prepare(input, destination,
options, callback)` produces a validated, ordinary work with `lilt.json` and
numbered reference files in a new directory. It knows neither URLs, Gutendex,
library installation nor manuscript paths. Metadata comes from the caller;
`source` is optional ordinary manifest attribution. The destination's parent must
exist; existing destinations are refused. Failed validation removes only output
created by this conversion. The input is unchanged.

`pandoc/epub.lua` reads the local container with Pandoc's ZIP API and bundled
SLAXML for package/nav/NCX XML. It sends each linear spine XHTML document through
Pandoc's HTML reader with EPUB extensions, preserving full-path/fragment identity
before combining documents. It never fetches or extracts resources. Source
navigation is metadata, separate from the body. Unsupported spine resource types
fail explicitly; nonlinear resources are excluded.

`pandoc/units.lua` resolves navigation after source cleanup: usable nav takes
precedence over NCX; otherwise structural headings supply units. Grouping,
linked parents, aliases and different source labels survive in an optional local
`toc`. Empty, missing or removed targets produce no action. Inline/table targets
enter at the enclosing block, never cut text apart. Units remain ordered by
spine, nonoverlapping, and independently accessible when absent from the TOC.
Long sections divide near 300 rows at paragraph breaks, avoiding tiny tails;
TOC chapters group their numbered reading parts. Coalesced heading-only targets
share a unit; the target nearest the body owns its part list once, while other
entries open the first part and retain their source children. The Picker displays
one indented list, caps indentation on narrow terminals, and appends unlisted units.

There is no chapter-name matching, locale keyword list or plain-text fallback.
Caption spans mirrored in a heading's navigation label are excluded from that
label and retained in body text. Presentation attributes/identifiers never enter
rendered references. Prose wraps at 72 columns; explicit verse/preformatted
breaks remain. CSS-only layout can differ. Images are omitted without fetching
assets; notes, tables and readable source contents remain text. Malformed
navigation falls back with import notes; it does not hide readable body text.

Source cleanup is a separate Pandoc filter, `pandoc/gutenberg.lua`, supplied only
by acquisition. It requires exactly one marked distribution header and footer;
ordinary local EPUBs need neither marker. Original credits/license remain in the
archive owned by acquisition. The writer does not change punctuation. After
parsing, the converter optionally replaces four curly quote characters in
reference lines before writing and validating them. Acquisition enables that
policy only for English-only catalog entries. Local conversion defaults to
preserving punctuation. Unit labels, other punctuation, existing references and
manuscripts are not rewritten.

Acquisition first reuses an existing copy, then checks the PATH executable with
`pandoc --version` (5-second deadline) before downloading. Missing, broken or older
than 3.1.1 tools report installation guidance. Runtime code never invokes mise,
a shell or an installer, and does not cache tool availability across operations.
The independent `import/epub.check(callback)` supports this preflight; direct local
conversion invokes Pandoc without a network preflight.

Download and conversion each have a 45-second deadline. Conversion uses Pandoc's
sandbox and a private output file, checked against 48 MiB before JSON decoding.
Container reads are capped at 48 MiB total; metadata XML at 4 MiB and 64 levels.
These are validation bounds, not a subprocess memory quota.
The request's download expires when its callback returns; acquisition first
copies it to private staging. Once conversion succeeds, acquisition moves that
input into the work as SOURCE.epub, writes provenance, then calls `library.add`.
Cancellation terminates the active check/download/conversion, removes private
files and suppresses queued callbacks. Conversion errors never publish a partial
library work. Opening existing copies checks neither curl nor Pandoc. Reading
views have no dependency on any conversion module or tool.

Gutendex offers popular/newest ordering, title/author search, subjects and
pagination without credentials. The public host has no documented rate quota or
availability guarantee. Lilt requests only user-selected pages and files. The
configurable HTTPS base also supports self-hosting as its documentation
recommends. Gutenberg's human-facing search is not scraped, following its
[access policy](https://www.gutenberg.org/policy/robot_access.html);
file downloads use its designated mirror.

There is one active reading session. Selecting another unit closes its
presentation and retains the previous ordinary buffer; file-backed units reuse
Neovim's buffer registry. Examples reuse an ordinary temporary buffer per
reference path within the process. The picker keeps only their buffer handles;
a wiped buffer is replaced on selection. Neither view knows about manifests,
library paths, installation, or persistence.

Closing preserves unsaved edits with `bufhidden=hide`, so ordinary quit/delete
protections continue to apply. Closing forgets the reading session; only `:Lilt`
chooses content. Ghost/Split commands switch an active presentation and otherwise
direct the user to `:Lilt`. There is no durable session or cursor registry;
saved files are the only persistent reading state.

## Boundaries and lifecycle

`manuscript.lua` prepares ordinary named or temporary buffers, reusing Neovim's
buffer registry for files and creating parents on native writes. Filetype and
typing options are initialized once; resuming preserves the buffer's settings.
Lilt uses native buffer options for its writing environment and does not manage
third-party completion plugins. `session.lua`
accepts an explicit manuscript buffer and reference snapshot; it coordinates
buffer attachment, view changes, and window-option restoration. Ghost owns its
presentation, hint timer, float, and autocmds. Split owns its reference buffer and
window. `compare.lua` is independent of Neovim UI; `render.lua` supplies the shared
namespace and clearing operation. Commands in `plugin/lilt.lua` call the small
public interface in `lua/lilt/init.lua`.

Ownership follows window IDs across native rearrangement. Before presentation
changes, options are saved against the window being changed. A native split
inherits its source window's options, so Split restores the manuscript window
before creating the reference window, then applies presentation to both. This
keeps Lilt's own quiet options and statusline out of the new window's baseline.
Assigning a buffer can reset window-local options; reapply presentation while
retaining the editor baseline captured before that assignment.
Repurposed or final surviving windows restore their pre-presentation editor
options. A repurposed focused window keeps focus; closing an owned window
returns to the origin when it survives. Global options and unrelated windows
are not managed by Lilt.

Opening and switching have one recovery boundary: if initialization fails, the
session terminates, partial resources are released, and the original error is
re-raised. Window creation can allocate resources before reporting failure;
cleanup must cover that partial initialization. It retains the ordinary
manuscript and its native undo tree. Reconstructing the previous view is
unnecessary. Repeated requests for a valid active view focus the manuscript and
keep its resources and layout.

Closing or repurposing either owned window, or wiping the manuscript, ends the
session. A surviving final reference window displays the retained manuscript.
Extra user-created windows survive. The private reference buffer is deleted even
if displayed elsewhere; deliberate overrides of its protection or suppression of
lifecycle autocmds are outside the contract.

Buffer attachments are dormant outside sessions. Reload detaches Lua callbacks;
`BufReadPost` reattaches them and refreshes presentation. Deferred lifecycle checks
and reload callbacks check session identity. Ghost invalidates timers by view
lifetime and generation, then checks window, buffer, changedtick, mode, and cursor
before showing a hint. Float destruction is scheduled outside `on_lines` textlock.

## Comparison

The authoritative range contract is beside `compare.line` in the implementation.
Its paired UTF-8 byte ranges let both views decorate the same alignment. Ghost
relies on one-to-one replacement codepoints when projecting hint context across
different byte widths, and on omissions preceding real authored text. Only the
untyped reference suffix is Pending.

The alignment fixes an exact prefix, then uses semi-global Levenshtein distance:
consume all authored characters while allowing a free reference suffix.
Identical inputs always yield identical results, regardless of edit history.
Ambiguous repeated words can align as replacements plus pending text
rather than a whole-word omission. That policy is deterministic, not an inference
of intent or a promise to preserve every tie-breaking choice forever.

After the exact prefix, comparison takes O(reference length × authored length)
time and space. Session retains at most one comparison per current row, keyed by
both reference and authored text. Every draw reads the real buffer and reuses
only identical row/text pairs. Rebuilding that small cache drops removed rows;
row insertion or deletion automatically invalidates changed pairs. Switching
views reuses it, closing discards it, and reload follows the same text checks.
There is no global cache, edit replay, or parallel manuscript model. Full
presentation redraw remains simple; work preparers should keep individual units
to a manageable size.

## Presentation rationale

Ghost places inline pending suffixes at real EOL and future rows in virtual
lines. Virtual lines are not navigable buffer rows: motions, search, selection,
and scrolling remain native authored-text operations. Missing reference text
never becomes an inline placeholder. Physical blank placeholders were rejected
because native Enter, `o`, `dd`, joining, undo, and saving cannot distinguish them
from authored paragraph breaks without a second text model.

Ghost therefore favors forward copying; Split supplies independent browsing in
an ordinary protected buffer. Split chooses orientation once using two prepared
line widths plus a separator. Native resizing and rearrangement own the layout
afterwards. There are no resize callbacks, automatic view changes, cursor
synchronization, or custom navigation engines.

Hint context is projected through existing alignment spans. Word boundaries keep
it local; whitespace errors include neighbors. Long context is clipped at UTF-8
boundaries around the selected error. Hints never take focus or correct writing.
