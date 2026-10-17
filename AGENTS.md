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
- Use mise for auxiliary tools and uv for the test Python environment; keep the
  developer's Neovim on PATH. Follow DEVELOPING.md for setup and version checks,
  then run `mise exec -- .venv/bin/python tests/run.py`. Add regressions for
  behavior, not assertion counts.
- Track presentation images with Git LFS; keep tests independent of those assets.
