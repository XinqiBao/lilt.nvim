# Design contracts

The ordinary listed manuscript buffer is the only authored-text authority.
Reference text is a session snapshot. Comparisons, highlights, hints, and virtual
lines are disposable derived state. Lilt never intercepts typing or repairs text.

`work.lua` parses self-contained JSON works, discovers immediate work
directories, validates selected reference text, and counts physical rows.
Discovery reads manifests and checks file metadata only. Installation validates
all reference bodies in the staged copy; opening a unit rechecks its path and
validates that text. JSON uses Neovim's built-in parser without vendored code.

`library.lua` installs local copies through hidden staging and derives manuscript
paths and saved progress. `init.lua` holds configuration and command entry
points. `picker.lua` coordinates local work/unit navigation and retains only
example buffer handles. `picker/discover.lua` owns online navigation; it uses
the `online/` modules without involving reading views. `picker/ui.lua` owns the
scratch float, selection, page stack, search editor, and request lifetime.

Menu rows distinguish informational text from actions. Movement skips headings;
native scrolling can still inspect metadata on short terminals. Detail text is
bounded and wraps with the window. Duplicate local titles show directory names
only when needed to distinguish them. Unit percentages report saved rows.
Action-local shortcut keys are displayed with their labels and active only on
that page; busy pages disable actions. q/Escape exits from any menu, while
h/Backspace goes back. Escape in the search editor cancels only the input.

A unit preview replaces the list in the same float with protected reference
text, starts at the beginning, and supports native scrolling/search. Back restores
the list selection and viewport. A side pane would narrow both documents and
need focus/resize rules; an always-visible lower pane would shorten the list.
The on-demand document avoids those costs. Preview reads the selected local
reference through `work.read_unit`; it never opens a manuscript or comparison.
Online details never download text for previews.

Catalog search edits one line in the existing float and preserves the results
behind it until submission. Native `vim.ui.input` supplies the local directory
prompt, preserving path completion; there is no global UI override. Queries,
presets and pagination replace the Discover page. Previous/Next are explicit
page actions. Work details add one level; acquired units use the shared local
flow. Returning from details restores the loaded result selection and viewport
without a request.

`online/catalog.lua` queries Gutendex and validates catalog metadata.
`online/acquire.lua` downloads UTF-8 plain text from Gutenberg's listed PGLAF
mirror, prepares an ordinary work, and delegates validation and publication to
`library.add`. Both use `online/request.lua` for bounded, cancellable requests.
The optional manifest `source` records portable attribution; a matching
provider/id permits reopening an existing copy without fetching or changing its
reference edition. Colliding local works and orphan manuscripts block acquisition.

The picker owns each asynchronous request's cancellation function. Back, leaving
the picker, and editor exit cancel it; callbacks also check page/picker lifetime.
Requests use argument-vector curl, HTTPS-only redirects, time/size limits and
owned temporary files. Only the current catalog page remains on the page stack;
there is no background polling, persistent catalog cache, or remote reading state.

`online/gutenberg.lua` prepares source text without network or installation
side effects. It requires unambiguous distribution markers and preserves all body
text, including front matter, contents, notes, and illustration labels. Credits
and the license survive in the verbatim original. Preparation preserves layout
and wraps only long unindented lines without tabular spacing, except in works
cataloged as poetry/drama. Recognizable section headings and isolated capitals
provide unit titles; extra blank padding before headings avoids treating
blank-separated contents entries as chapters. Compact or unrecognized layouts
fall back to paragraph-based parts. After chapter/act structure begins, embedded
capitals stay inside that structure. Sections divide near 300 physical rows at
paragraph breaks, avoiding tiny tails. Unit-edge blank padding is omitted. These
are plain text heuristics, not semantic reconstruction of an EPUB.

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
buffer registry for files and creating parents on native writes. `session.lua`
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
