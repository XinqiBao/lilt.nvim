# Review notes

Lilt is a small Neovim plugin for reading literature by retyping it. Read
[usage](../README.md) and [current findings](findings.md) for its copying
contract, alignment policy, API rationale, evidence, and known limitations.

| File | Responsibility |
| --- | --- |
| `plugin/lilt.lua` | Three commands; no typing mappings |
| `lua/lilt/init.lua` | Small public interface |
| `lua/lilt/session.lua` | Reference snapshot, authoritative buffer, view switching, shared lifecycle and per-window option restoration |
| `lua/lilt/compare.lua` | Within-line UTF-8 alignment and paired byte ranges, with no UI decisions |
| `lua/lilt/view/ghost.lua` | Pending suffixes, virtual future rows, manuscript feedback, and delayed local hints |
| `lua/lilt/view/split.lua` | Protected reference resources, initial layout, and feedback in both panes |
| `lua/lilt/render.lua` | Shared decoration namespace and cleanup |
| `samples/alice.txt` | Fixed prepared passage; changing layout can invalidate manuscripts |
| `tests/compare.lua` | Concrete alignment contract |
| `tests/headless.lua` | Real native editing, state integrity, and lifecycle |
| `tests/ui.py` | Attached redraw/highlight evidence, native input, layouts, resizing, and hints |

Useful review questions are whether ambiguous unfinished text receives a
predictable interpretation, whether hint lifetimes remain scoped to their view,
and whether resource cleanup preserves unrelated editor state. Compare both
reference and manuscript byte ranges; Unicode indexes are not byte offsets.
Window ownership must follow IDs after native rearrangement. Restored options
must come from the affected window's snapshot.

Ghost's forward-reading limit and fixed physical-line copying are intentional.
There is no custom navigation through future virtual lines, automatic mode
switching, reflow, cross-line alignment, correction, or progress scoring. Split
remains a separate native reading experience. Assess visual comfort through
actual reading rather than treating automated rendering checks as preference
validation.

Run the three commands in [README](../README.md); current counts and tested
versions have one home in [findings](findings.md#verification). For reproducible
feedback include version, window dimensions, exact keys, expected/actual text
or display, and whether writing, undo history, or unrelated state changed.
