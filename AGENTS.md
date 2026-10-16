# Project guidance

- Keep the real manuscript buffer authoritative. Preserve native editing,
  undo/redo, saving, and the established Ghost/Split reading experience.
- Session coordinates lifecycle; views own presentation resources. Cleanup must
  handle partial initialization and restore editor options in surviving windows.
  Native splits inherit options: never snapshot Lilt's presentation as a baseline.
- Keep comparison independent of Neovim UI. Its paired UTF-8 byte-range contract
  is documented beside `compare.line`; Ghost relies on paired replacement
  codepoints. Caches are session-local disposable derived data.
- Preserve `samples/alice.txt` line layout; changing it shifts manuscripts.
- Use the tools in `mise.toml`. Run `mise exec -- .venv/bin/python tests/run.py`
  after installing `tests/requirements.txt`; see DEVELOPING.md for minimum-version
  checks and individual suites. Add regressions for behavior, not assertion counts.
