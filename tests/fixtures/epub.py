"""Build a tiny, inspectable EPUB from source for offline acquisition tests."""

from pathlib import Path
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile


def write_epub(path):
    with ZipFile(path, "w", compression=ZIP_DEFLATED) as archive:
        archive.writestr("mimetype", "application/epub+zip", compress_type=ZIP_STORED)
        archive.writestr("META-INF/container.xml", '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''')
        # Manifest/ZIP order differs from spine order: reading follows the spine.
        archive.writestr("book.opf", '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="id">lilt-test-letters</dc:identifier>
    <dc:title>Test Letters</dc:title><dc:language>en</dc:language>
    <meta property="dcterms:modified">2026-10-18T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="reply" href="reply.xhtml" media-type="application/xhtml+xml"/>
    <item id="book" href="book.xhtml" media-type="application/xhtml+xml"/>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
  </manifest>
  <spine><itemref idref="book"/><itemref idref="reply"/></spine>
</package>''')
        archive.writestr("reply.xhtml", Path(__file__).with_name("reply.html").read_bytes())
        archive.writestr("book.xhtml", Path(__file__).with_name("gutenberg.html").read_bytes())
        archive.writestr("nav.xhtml", '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Contents</title></head><body><nav epub:type="toc"><ol>
<li><a href="book.xhtml#first">The letter — 第一封信</a></li>
<li><a href="reply.xhtml#second">A reply</a></li>
</ol></nav></body></html>''')
