# SLAXML

`slaxml.lua` is [SLAXML 0.8](https://github.com/Phrogz/SLAXML), by Gavin Kistner,
under the [MIT license](LICENSE.slaxml). It runs only inside Pandoc and supplies
namespace-aware XML parsing for EPUB package/navigation metadata. Neovim does
not load it. No additional runtime executable is required.

The upstream file is formatted with the repository's StyLua configuration;
its behavior is unchanged. Selene excludes this third-party Lua 5.1/5.2 code.
Upstream source SHA-256 before formatting:
`4e736768c061407609741baea1ebbe15e6b53cab5920defea5d7ed3b3c16c35e`.

SLAXML does not resolve external entities. It is a metadata parser, not an EPUB
validator; the adapter checks balanced names/namespaces and limits XML size and
nesting. XHTML body rendering remains Pandoc's responsibility.
