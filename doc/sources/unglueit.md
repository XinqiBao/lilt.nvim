# Unglue.it

Unglue.it offers anonymous [OPDS catalog feeds](https://unglue.it/api/help).
Inside Discover online, **Explore** includes its popular EPUB feed and
**Recently listed** includes its new EPUB feed. Lilt lists explicitly English
copies with direct HTTPS EPUB acquisitions and a recognized
rights notice. A page may contain no eligible copies; **Load more** remains
available when the feed advertises another page. Unglue.it does not join search
because the documented service has returned search timeouts.
A feed can mix eligible and ineligible works, so its record count is not an
eligible catalog total.

A work with several eligible downloads opens a copy list. Each choice shows
its own rights, supplied version/title and copy number. Those downloads can
be different editions; Lilt does not pick one automatically. A work with one
eligible copy opens its details directly. Saved identity includes the Unglue.it
work and acquisition numbers, independently of your chosen directory name.
The supplied copy title and version are also retained for offline Work
information; neither is an inferred edition description or a personal alias.
Only advertised official download links with those unambiguous identities are
supported. Unknown language or rights, indirect HTML downloads, paid links and
other formats are excluded. The EPUB feed itself can contain those records.

Rights are source claims for the selected acquisition. `PD-US` means public
domain in the United States; Creative Commons notices can restrict reuse.
The feed's short CC labels do not identify a license version. Check the
original notices and applicable law before sharing or reusing a reading copy.
The plugin's software license does not license the books.

Acquisition uses the existing Pandoc EPUB conversion, preserves punctuation
and retains front matter and license text. It applies no Gutenberg filter.
The saved work retains the unchanged `SOURCE.epub`, exact full `SOURCE.opds`
response, selected work/link metadata in `SOURCE.json`, and readable attribution
in `README.txt`. Work-level ISBNs, dates, publishers and descriptions remain in
the raw feed; they are not assigned to the selected EPUB edition. Saved copies
work offline and are reused without replacing a manuscript's reference.

Feeds and downloads can fail or change. Lilt reports errors without installing
a partial copy. Discovery does not guarantee a book's editorial quality or
establish that its edition is absent from another catalog.
