# Current alignment contract

`compare.line` returns coalesced Equal, Pending, Replace, Extra, and Missing
spans with zero-based, exclusive reference and manuscript byte ranges, plus
an aligned reference coverage boundary and pending suffix. Comparisons use
UTF-8 codepoints, never byte positions as character indexes.

Each physical row uses semi-global Levenshtein alignment: all manuscript
characters are consumed; the remaining reference suffix costs nothing and is
Pending. Internal reference deletions are Missing. An exact leading prefix is
fixed first. Among minimum-cost paths, prefer more equal characters, then a
coverage endpoint nearest the manuscript's character length, then the earlier
endpoint. Remaining ties use Equal, Replace, Extra, Missing in that order.
This preserves an already matching prefix and makes repeated-character choices
reproducible without hidden typing history.

This is a text-derived interpretation, not inferred intent. For example,
`little bird` against `little little bird` is cheaper as three replacements
within the second word followed by pending text than as seven omissions.
Trailing wrong characters can change interpretation as more text arrives.
There is no cross-row alignment, normalization, or word-aware diff.

The following records the **superseded positional prototype** and its original
experiments. Rendering/lifecycle refinements will be documented with their final
verification below.

# Reading prototype findings

Ghost is practical as a **forward-copying experiment** when the prepared lines
fit the window. It does not satisfy unrestricted browsing of a fully printed
page. Split should remain an independent mode: it provides the simpler, native
reading experience and a reliable way to inspect the reference ahead of writing.

## Design and investigation

The manuscript is an ordinary listed, initially unnamed Neovim buffer with
`bufhidden=hide`. It contains only authored characters and authored line breaks.
The reference is loaded once per session from the bundled UTF-8 file. Comparison
and extmarks are derived from the buffer; there is no Lua manuscript mirror.

The implementation uses approach A:

- Each real row is compared with the reference row at the same physical index.
- The pending suffix is **inline virtual text at actual EOL**, independent of
  cursor position. Authored characters occupy their normal buffer positions.
- All reference rows after actual EOF are one `virt_lines` extmark below the
  final real row, including paragraph blanks. Rendering is rebuilt from the
  current buffer after changes; stale anchors are not treated as alignment.
- Errors are highlight ranges with UTF-8 byte boundaries. Correct characters
  need no extra highlight, retaining the user's normal foreground.

An embedded Neovim UI experiment rendered 24 reference rows over a one-line
empty buffer. After native typing and Enter, the first pending suffix remained
visible and the second virtual row became a real row without displacing later
reference rows. Cursor movement did not change pending text. This is materially
different from a prompt which only renders at the cursor.

The important constraints are native ones. Virtual lines are not buffer lines:
`G`, search, and motions operate on authored text. In the experiment, repeated
Ctrl-E stopped at the final real row (topline 2 with two authored rows); it could
not scroll freely into the 22 future rows. Neovim can render them in the
viewport, but attaching more rows does not make them fully navigable. The
prototype makes **no claim that every future line can be brought into view in
Ghost before writing**. Split exposes all of them in an ordinary buffer.

Horizontal scrolling was also tested on a 32-column UI. Inline pending text
extends beyond EOL, but native `zl` is constrained by actual cursorable text.
A short authored prefix cannot reliably expose a long pending suffix. With
long authored lines, `virt_lines_overflow='scroll'` makes future rows share the
window's horizontal offset. `nowrap` preserves rows, but cannot solve the short
prefix case. Consequently Ghost requires the longest prepared reference line
plus one cursor cell (75 columns here). Requests and resize events below that
width select wrapped Split, with an explanation in the manuscript statusline.
Widening leaves Split active until explicitly changed. There is no clipping
policy disguised as a supported narrow Ghost layout.

Approach B was tested with six preallocated physical blank rows. Native Enter
inserted a seventh row; `dd` shifted subsequent rows, and undo restored the
native structure. `o` inserts rather than consumes a placeholder, and native
Backspace can join rows. Keeping fixed slots would require replacing structural
editing operations and distinguishing genuinely authored blank lines from
placeholders. Blank rows serialize as real newlines and are indistinguishable
from deliberately typed paragraph separators without additional authoritative
state. Converting them on view switching or writing would also disturb the undo
model. This cost is larger than the benefit; approach B was rejected.

A protected printed buffer plus a separate editing surface would put the cursor
in a different document from the visible manuscript, requiring input routing.
Split already offers the honest version of that separation, so a third editor
surface was not built.

Neovim **0.11** is the minimum. Public API documentation for v0.10.4 includes
inline virtual text but lacks `virt_lines_overflow`; v0.11.0 and v0.11.5 include
it. This option materially improves consistent horizontal scrolling of future
rows. The actual suites ran on 0.11.5 and 0.12.5; 0.11.0 itself was not run.
Other APIs used include `nvim_buf_attach`, `nvim_buf_set_extmark`, ordinary
window/buffer APIs, and user commands/autocmds. No private rendering APIs,
decoration provider, custom editor, or key interception is used.

## Comparison and editing contract

Comparison is physical-row and Unicode-codepoint positional matching. For
reference `abc`, authored `ax` displays `axc`, with `x` marked wrong and `c`
pending. Authored `ac` displays `acc`: its second character is wrong at position
2 and the reference's third character is still pending. This apparent repetition
is the documented positional rule, not duplicated virtual rows. Extra authored
characters remain real and are marked wrong. A substitution does not shift
layout; a missing/extra character shifts matching through the rest of its row.
There is no normalization, edit distance, punctuation substitution, or correction.

Blank lines separate paragraphs in the sample. Physical breaks within a
paragraph are preparation layout, but the matcher still expects those exact
breaks. Enter early leaves the unfinished preceding suffix visible and begins
comparison with the next reference row. Added/deleted newlines shift comparisons
of subsequent authored rows. Blank surplus lines have no glyph to highlight;
missing newlines have no separate indicator. The reference does not realign to
follow the meaning of the writing. Use Split when the merged display is confusing.

| Interaction | Assessment |
| --- | --- |
| Insert, Backspace within a line, Enter, Esc | Native; exercised in actual Neovim |
| `ciw`, `x`, `dw`, `.`, repeated edits of earlier words | Native; exercised; changed lengths follow the positional rule |
| Undo / Ctrl-R | Native; buffer changes and refreshed feedback exercised |
| `o`, `dd`, Backspace across a line boundary | Native text edits; exercised; row alignment shifts without repairs |
| Searching, motions, selection, yanking | Operate on authored buffer contents; pending characters are not included |
| Navigating/editing future pending characters | Unsupported in Ghost; not cursorable text |
| Scrolling beyond authored EOF | Limited in Ghost; use Split for free reference browsing |
| Horizontal scroll of long authored rows | Native; future rows share offset; may hide reference at the left |
| Tabs, wide characters, combining characters, invalid UTF-8 | Outside prepared-English layout contract; no cell/grapheme alignment guarantee |
| Correct curly quotes/apostrophes, em dashes, ellipses | Codepoint matching and byte ranges tested; curly quotes also tested on rendered screen |
| Automatic reflow / semantic paragraph alignment | Unsupported; would change this comparison contract |

The prototype does not restrict line-changing keys because preserving native
editing is preferable to repairing user text behind their back. It therefore
cannot promise a fixed printed-page layout across arbitrary structural edits.
Ordinary forward copying with one Enter per prepared row preserves the row
layout. The reference glyph at an incorrect authored position is replaced by
the actual input; use Split to inspect the original glyph.

## Split, ownership, and lifecycle

Split places reference above writing. A 90-column geometry experiment gave
45-column windows side by side, versus 90-column windows with an above/below
split. Above/below preserves prepared reading width on ordinary terminals at
the expense of vertical space. Both Split windows wrap with `linebreak` at
narrow widths. The reference is `modifiable=false`, `readonly=true`, and
unlisted; protection is against accidental edits, not deliberate option changes.
There is no diff mode or synchronized scrolling.

A new tab isolates plugin window options from the original layout. The plugin
owns two window handles at most, a session autocmd group, a rendering namespace,
and the temporary reference buffer. Switching to Ghost deletes the Split
reference window and buffer; closing removes all session marks/autocmds and
reference resources. The manuscript persists intentionally. One Lua attachment
belongs to the manuscript's lifetime and is dormant outside a session; switching
or reopening does not add attachments. Neovim detaches it on unload/reload, so
`BufReadPost` reattaches while a session is active. Reload via `:edit!` was tested.

Closing a reading window/tab ends the session. If an owned window is repurposed
to another buffer, cleanup restores its inherited options and keeps that
window. Extra user-created windows are retained. If the last editor window
cannot close, its original local options are restored and the manuscript stays
visible. Original windows/buffers, global options, and mappings are not changed.

## Verification and remaining uncertainty

On both Neovim **0.11.5** (downloaded release) and **0.12.5** (local installation):

- `tests/compare.lua`: 26 assertions for deterministic codepoint comparison,
  pending suffixes, mismatch ranges, and UTF-8 byte offsets.
- `tests/headless.lua`: 131 assertions, using real native key feeds, buffer and
  extmark inspection. Includes empty/correct/incorrect/missing/extra characters,
  punctuation, paragraph blanks, structural edits, earlier edits, undo/redo,
  repeated switches, exact file serialization, reload, reopening, explicit wipe,
  manual closure, repurposed windows, extra windows, and final-window restoration.
- `tests/ui.py`: 40 assertions against actual attached UI redraw grids and
  highlight state, with native `nvim_input`. Includes complete initial viewport,
  actual errors, preceding suffix persistence, later rows, cursor independence,
  Unicode quotes, completed document, scrolling across the real/virtual boundary,
  horizontal offset, resize while typing, continuing Insert Mode in narrow Split,
  independent reference browsing, repeated fallback, and cleanup.

The Python harness uses public Neovim RPC/UI APIs and `pynvim`; it is a test-only
dependency. No generated screenshots, downloaded binaries, or experiment scripts
are stored in the repository. A terminal launch smoke check exercised the exact
README invocation with an absolute runtime path, typing, view switching, and
closing. It does not establish comfort over a long reading session.

Unverified: extended human reading comfort, arbitrary user mappings/autocmds,
other colorschemes and terminal palettes, mouse interactions, very small terminal
heights, and complex Unicode. `Comment` and `SpellBad` inherit the colorscheme;
some themes make errors much louder than intended. Owners can override the two
semantic groups. Large works were not benchmarked: rebuilding all derived marks
on each change is intentional for this 40-line sample, not a performance claim.

### Manual reading check

1. Launch the README command in an 80-column or wider terminal. Type the first
   two lines with a substitution and with Enter before finishing a line. Confirm
   the earlier suffix stays readable and future rows stay in place.
2. Edit the earlier word using `ciw`; try `x`, `dw`, `.`, undo, and redo. Compare
   the actual writing in Split. Missing characters should cause positional
   mismatch, never content repair.
3. Copy several paragraphs, scrolling back to unfinished earlier rows. Try
   `o`, `dd`, and joining lines. Confirm text is ordinary and compare the shifted
   rows with the printed reference.
4. Browse ahead in Split with `<C-w>k`, search, and `G`; return to writing with
   `<C-w>j`. Switch repeatedly and confirm writing and undo remain intact.
5. Shrink below 75 columns while in Insert Mode. Confirm wrapped Split appears
   and typing continues. Enlarge and explicitly return using `:LiltGhost`.
6. Save a manuscript, close, reopen, then close its tab manually. Inspect `:ls`
   and the saved file: there should be only authored text. Repeat with your
   preferred colorscheme, and spend time reading to assess error subtlety and
   above/below split comfort.

## Recommendation

Keep Ghost experimental until forward-only reference access and exact physical
row copying are accepted as deliberate interaction rules. Stable future rows
and native typing coexist here; unrestricted printed-page browsing and arbitrary
structural editing do not. If those rules are unacceptable, prefer Split as the
primary mode rather than growing Ghost into a custom editor.

Before extending this prototype, revisit only three decisions: acceptance of
Ghost's navigation/line-break contract, the visibility/subtlety of inherited
pending and error highlights, and how an ordinary saved manuscript is selected
and resumed. Split should remain independently available regardless of Ghost's
future. Its native reference browsing is useful in its own right.
