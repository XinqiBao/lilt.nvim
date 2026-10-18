local epub = require('lilt.import.epub')
local work = require('lilt.work')
local filter = vim.fn.getcwd() .. '/pandoc/gutenberg.lua'
local source = assert(vim.env.LILT_TEST_EPUB, 'run through tests/run.py to build the EPUB fixture')
local root = vim.fn.tempname()
local sequence = 0
local function bytes(path)
  local file = assert(io.open(path, 'rb'))
  local value = file:read('*a')
  file:close()
  return value
end
local function converted(path, plain_quotes, source_filter)
  sequence = sequence + 1
  local destination = root .. '/work-' .. sequence
  local result
  epub.prepare(path, destination, {
    title = 'Test Letters',
    plain_quotes = plain_quotes,
    filter = source_filter,
  }, function(err, reading)
    result = { err = err, reading = reading }
  end)
  assert(
    vim.wait(5000, function()
      return result ~= nil
    end, 5),
    'preparation did not complete'
  )
  local units = result.reading and result.reading.units
  for _, unit in ipairs(units or {}) do
    unit.lines = work.read_unit(result.reading, unit)
  end
  if result.err then
    assert(not vim.uv.fs_stat(destination), 'failed conversion left a partial work')
  end
  return result.err, units, result.reading
end
local function run()
  vim.fn.mkdir(root, 'p')
  local checked
  epub.check(function(err)
    checked = { err = err }
  end)
  assert(
    vim.wait(5000, function()
      return checked ~= nil
    end, 5),
    'tool check did not complete'
  )
  assert(not checked.err, tostring(checked.err))
  local original = bytes(source)
  local err, units = converted(source, false, filter)
  assert(not err, tostring(err))
  assert(
    #units == 3 and units[2].title == 'The letter — 第一封信' and units[3].title == 'A reply',
    'units follow EPUB spine order and structural headings, not archive order or captions'
  )
  local text = table.concat(units[2].lines, '\n')
  assert(
    text:find('“Café, 文学, and a rabbit 🐇,”', 1, true),
    'Unicode punctuation fidelity'
  )
  assert(
    text:find('Little Lamb, who made thee?\nDost thou know who made thee?', 1, true)
      and text:find('\n\nGave thee life', 1, true),
    'explicit verse lines and stanza boundaries survive conversion'
  )
  assert(text:find('north    south', 1, true), 'preformatted spacing survives')
  assert(text:find('CHAPTER I. is just prose', 1, true), 'prose resembling a heading stays prose')
  local reply = table.concat(units[3].lines, '\n')
  assert(reply:find('An illustration caption.', 1, true), 'caption text remains in the reference')
  assert(reply:find('A retained footnote.', 1, true), 'footnotes remain readable')
  local all = table.concat(
    vim.tbl_map(function(unit)
      return table.concat(unit.lines, '\n')
    end, units),
    '\n'
  )
  assert(
    not all:find('distribution header', 1, true)
      and not all:find('Full distribution license', 1, true)
      and not all:find('Not a chapter title', 1, true),
    'distribution boilerplate and image placeholders stay out of reading text'
  )
  err, units = converted(source, false)
  assert(not err, tostring(err))
  local unfiltered = {}
  for _, unit in ipairs(units) do
    vim.list_extend(unfiltered, unit.lines)
  end
  unfiltered = table.concat(unfiltered, '\n')
  assert(
    unfiltered:find('distribution header', 1, true)
      and unfiltered:find('Full distribution license', 1, true),
    'without an explicit filter even Gutenberg markers remain ordinary source content'
  )
  err, units = converted(source, true, filter)
  assert(not err, tostring(err))
  reply = table.concat(units[3].lines, '\n')
  assert(
    reply
      :gsub('%s+', ' ')
      :find([['Don't' change — dashes – or …; «文学», ʼ, and café́.]], 1, true),
    'English quote conversion leaves other punctuation and letters intact'
  )
  assert(bytes(source) == original, 'conversion mutated EPUB')

  local samples = vim.fn.fnamemodify(source, ':h')
  local reading
  err, units, reading = converted(samples .. '/nav.epub', false)
  assert(not err, tostring(err))
  local group = assert(reading.toc and reading.toc[1], 'authored navigation retained')
  assert(group.title == 'Collected letters' and not group.unit, 'non-actionable grouping')
  local second, first, alias = unpack(group.children)
  assert(
    second.title == 'Second letter' and first.title == 'First letter',
    'source TOC order and labels'
  )
  assert(
    first.unit ~= second.unit and alias.unit == first.unit,
    'full paths distinguish equal basenames; aliases share units'
  )
  assert(first.unit == reading.units[1], 'navigation order never reorders spine content')
  assert(first.children[1].title == 'Internal section', 'nested section target')
  assert(
    first.children[3].unit
      and table
        .concat(work.read_unit(reading, first.children[3].unit), '\n')
        :find('A retained table', 1, true),
    'table anchors enter at intact table blocks'
  )
  assert(
    first.children[1].unit == first.children[2].unit,
    'inline target enters at intact enclosing paragraph'
  )
  assert(
    #group.children == 3,
    'unlinked leaves, image-only, missing and external targets are omitted'
  )
  assert(
    table.concat(work.read_unit(reading, first.unit), '\n'):find('FIRST PRINTED HEADING', 1, true),
    'TOC label does not rewrite the printed heading'
  )
  all = table.concat(
    vim.tbl_map(function(unit)
      return table.concat(unit.lines, '\n')
    end, units),
    '\n'
  )
  assert(select(2, all:gsub('Opening paragraph', '')) == 1, 'aliases never duplicate body text')
  assert(
    all:find('Before the inline target', 1, true) and all:find('Readable material absent', 1, true),
    'inline prefixes and unlisted text remain intact'
  )
  assert(not all:find('{#', 1, true), 'navigation identifiers stay out of reference text')
  assert(
    not all:find('Nonlinear supplement', 1, true),
    'nonlinear supplements remain outside the reading order'
  )
  for _, mode in ipairs({ 'broken-nav', 'unusable-nav' }) do
    err, units, reading = converted(samples .. '/' .. mode .. '.epub', false)
    assert(not err and reading.toc[1].title == 'NCX collection', 'unusable nav falls back to NCX')
    if mode == 'broken-nav' then
      assert(
        reading.import_warnings and #reading.import_warnings == 1,
        'malformed navigation reports one recoverable import note'
      )
    end
    assert(reading.toc[1].children[1].title == 'NCX internal section', 'NCX nesting retained')
  end
  err, units, reading = converted(samples .. '/unlabelled.epub', false)
  assert(
    not err and reading.toc[1].title == 'Second letter',
    'unlabelled containers retain usable children without invented labels'
  )
  err, units, reading = converted(samples .. '/caption-label.epub', false)
  assert(not err, tostring(err))
  assert(
    reading.toc[1].children[2].title == 'FIRST PRINTED HEADING',
    'a mirrored caption is excluded structurally, without rewriting distinct authored labels'
  )
  assert(
    table.concat(units[1].lines, '\n'):find('Illustration.', 1, true),
    'caption remains body text'
  )
  err, units, reading = converted(samples .. '/long.epub', false)
  assert(not err, tostring(err))
  local chapter = reading.toc[1].children[2]
  assert(
    not chapter.unit and chapter.children[1].title:find('Part 1 of ', 1, true),
    'long sections keep numbered reading parts under their source chapter'
  )
  assert(
    chapter.children[1].unit and chapter.children[2].unit,
    'technical parts resolve to ordinary units'
  )
  local long_alias = reading.toc[1].children[3]
  assert(
    long_alias.unit == chapter.children[1].unit and not long_alias.children,
    'aliases open the first reading part without duplicating the part list'
  )
  err, units, reading = converted(samples .. '/coalesced.epub', false)
  assert(not err, tostring(err))
  group, chapter = reading.toc[1], reading.toc[1].children[2]
  assert(
    group.unit == chapter.children[1].unit and #group.children == 3,
    'adjacent heading-only targets share text without expanding parts at each level'
  )
  assert(
    group.children[3].title == chapter.title and group.children[3].unit == group.unit,
    'repeated source labels and links remain distinct navigation entries'
  )
  assert(
    table.concat(work.read_unit(reading, group.unit), '\n'):find('Collection opening', 1, true),
    'coalescing navigation never discards the earlier printed heading'
  )
  err, units, reading = converted(samples .. '/no-toc.epub', false)
  assert(
    not err and not reading.toc and #units > 0,
    'missing navigation falls back to body headings'
  )

  err = converted('https://example.invalid/book.epub', false)
  assert(
    err and err:find('expected a local EPUB file', 1, true),
    'conversion must reject URLs before Pandoc can fetch them'
  )

  local result
  epub.prepare(source, root, { title = 'Existing directory' }, function(error)
    result = error
  end)
  assert(
    vim.wait(1000, function()
      return result ~= nil
    end, 5),
    'destination collision did not complete'
  )
  assert(result:find('already exists', 1, true), 'existing output must never be overwritten')
  result = nil
  local invalid = root .. '/invalid-metadata'
  epub.prepare(source, invalid, { title = 'Letters', author = '' }, function(error)
    result = error
  end)
  assert(
    vim.wait(5000, function()
      return result ~= nil
    end, 5),
    'invalid work did not complete'
  )
  assert(
    result:find('author', 1, true) and not vim.uv.fs_stat(invalid),
    'invalid output metadata must fail validation and clean the generated work'
  )

  -- Documents without headings still produce usable paragraph-based parts.
  local html = root .. '/unstructured.html'
  local rows = { '<html><body><div id="pg-header">Header</div>' }
  for _ = 1, 150 do
    rows[#rows + 1] = '<p>' .. string.rep('A paragraph of prose. ', 20) .. '</p>'
  end
  rows[#rows + 1] = '<div id="pg-footer">Footer</div></body></html>'
  vim.fn.writefile(rows, html)
  local archive = root .. '/unstructured.epub'
  local built =
    vim.system({ 'pandoc', '--from=html', '--to=epub', '--output=' .. archive, html }):wait()
  assert(built.code == 0, built.stderr)
  err, units = converted(archive, false)
  assert(not err, tostring(err))
  assert(
    #units > 1 and units[1].title == 'Test Letters · 1' and #units[#units].lines >= 80,
    'documents without headings use numbered parts and avoid tiny tails'
  )
  local bad = root .. '/bad.epub'
  vim.fn.writefile({ 'not an EPUB' }, bad)
  err = converted(bad, false)
  assert(err and err:find('EPUB preparation failed', 1, true), 'malformed EPUB must fail')

  vim.fn.writefile({ '<html><body><h1>Text without distribution markers</h1></body></html>' }, html)
  built = vim.system({ 'pandoc', '--from=html', '--to=epub', '--output=' .. archive, html }):wait()
  assert(built.code == 0, built.stderr)
  err, units = converted(archive, false)
  assert(not err and #units == 1, 'ordinary local EPUBs need no Gutenberg markers')
  err = converted(archive, false, filter)
  assert(
    err and err:find('cannot safely locate', 1, true),
    'the acquisition filter must reject uncertain Gutenberg boundaries'
  )
  local system = vim.system
  local completed, killed, output, finish
  vim.system = function(args, options, callback)
    assert(
      args[1] == 'pandoc' and vim.tbl_contains(args, '--sandbox'),
      'isolated converter invocation'
    )
    assert(options.timeout == 45000, 'conversion must have a deadline')
    for _, arg in ipairs(args) do
      output = arg:match('^%-%-output=(.+)$') or output
    end
    finish = callback
    return {
      kill = function()
        killed = true
      end,
    }
  end
  local cancel = epub.prepare(source, root .. '/cancelled', { title = 'Cancelled' }, function()
    completed = true
  end)
  cancel()
  vim.fn.writefile({ '[]' }, output) -- A late process exit may recreate its output.
  finish({ code = 0, stderr = '' })
  assert(
    vim.wait(1000, function()
      return not vim.uv.fs_stat(output)
    end, 5),
    'cancelled converter output leaked'
  )
  assert(
    killed and not completed and not vim.uv.fs_stat(root .. '/cancelled'),
    'cancelled conversion must not deliver or write a work'
  )
  local timeout_error
  epub.prepare(source, root .. '/timed-out', { title = 'Timed out' }, function(error)
    timeout_error = error
  end)
  vim.fn.writefile({ 'partial output' }, output)
  finish({ code = 124, stderr = '' })
  assert(
    vim.wait(1000, function()
      return timeout_error ~= nil
    end, 5),
    'timeout result was not delivered'
  )
  assert(
    timeout_error:find('exceeded 45 seconds', 1, true)
      and not vim.uv.fs_stat(output)
      and not vim.uv.fs_stat(root .. '/timed-out'),
    'timeouts explain the deadline and remove partial output without creating a work'
  )
  for _, version in ipairs({
    { code = 0, stdout = 'pandoc 3.1.1\nFeatures: +server', supported = true },
    { code = 0, stdout = 'pandoc 4.0\n', supported = true },
    { code = 0, stdout = 'pandoc 3.1\n' },
    { code = 0, stdout = 'not pandoc' },
    { code = 127, stdout = 'pandoc 3.8.3\n' },
  }) do
    vim.system = function(args, options, callback)
      assert(vim.deep_equal(args, { 'pandoc', '--version' }), 'check the PATH tool directly')
      assert(options.timeout == 5000, 'tool check must have a deadline')
      callback(version)
      return { kill = function() end }
    end
    checked = nil
    epub.check(function(error)
      checked = { err = error }
    end)
    assert(
      vim.wait(1000, function()
        return checked ~= nil
      end, 5),
      'version check did not complete'
    )
    assert((checked.err == nil) == (version.supported == true), 'Pandoc version/health gate')
  end
  vim.system = system
  print('Lilt EPUB: local works, structure, text fidelity, tool checks and cancellation passed')
end
local ok, err = xpcall(run, debug.traceback)
vim.fn.delete(root, 'rf')
if not ok then
  io.write(err .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
