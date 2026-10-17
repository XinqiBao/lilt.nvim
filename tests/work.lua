local work = require('lilt.work')
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/chapters', 'p')
local function manifest(value)
  vim.fn.writefile({ vim.json.encode(value) }, root .. '/lilt.json')
end
local function rejects(value, pattern)
  manifest(value)
  local ok, err = pcall(work.load, root)
  assert(not ok and tostring(err):find(pattern), tostring(err))
end
local function run()
  vim.fn.writefile({ 'Second', '', 'row' }, root .. '/chapters/02.txt')
  vim.fn.writefile({ 'First — café' }, root .. '/text.txt')
  local data = {
    title = 'A work',
    units = {
      { path = 'chapters/02.txt', title = 'Second first' },
      { path = 'text.txt', title = 'First second' },
    },
  }
  manifest(data)
  local loaded = work.load(root)
  assert(loaded.title == 'A work' and loaded.units[1].path == 'chapters/02.txt', 'manifest order')
  assert(
    vim.deep_equal(work.read(loaded.units[1].reference), { 'Second', '', 'row' }),
    'physical rows'
  )
  assert(work.read(loaded.units[2].reference)[1] == 'First — café', 'UTF-8 text')
  rejects({}, 'object')
  rejects({ title = ' ', units = data.units }, 'title')
  rejects({ title = 'Work', units = {} }, 'nonempty array')
  rejects({ title = 'Work', units = vim.NIL }, 'nonempty array')
  rejects({ title = 'Work', typo = true, units = data.units }, 'unknown field')
  data.source =
    { provider = 'Project Gutenberg', id = '11', url = 'https://www.gutenberg.org/ebooks/11' }
  manifest(data)
  assert(work.load(root).source.id == '11', 'portable optional provenance')
  for _, source in ipairs({
    {},
    { provider = 'PG', id = '11' },
    { provider = 'PG', id = 11, url = 'https://example.org/' },
    { provider = 'PG', id = '11\n12', url = 'https://example.org/' },
    { provider = 'PG', id = '11', url = 'file:///etc/passwd' },
    { provider = 'PG', id = '11', url = 'https://example.org/', extra = true },
  }) do
    rejects({ title = 'Work', source = source, units = data.units }, 'source')
  end
  data.source = nil
  rejects({ title = 'Work', units = { data.units[1], data.units[1] } }, 'duplicate')
  for _, path in ipairs({
    '../text.txt',
    '/text.txt',
    'chapters/../text.txt',
    'C:/text.txt',
    'a\\b',
    'text.txt/',
    'missing.txt',
    'chapters',
  }) do
    rejects({ title = 'Work', units = { { title = 'Unit', path = path } } }, 'Lilt:')
  end
  assert(vim.uv.fs_symlink(root .. '/text.txt', root .. '/link.txt'))
  rejects({ title = 'Work', units = { { title = 'Unit', path = 'link.txt' } } }, 'symlink')
  vim.fn.writefile({ '{ broken' }, root .. '/lilt.json')
  assert(not pcall(work.load, root), 'malformed JSON accepted')
  manifest({ title = 'Work', units = { { title = 'Unit', path = 'text.txt' } } })
  for _, invalid in ipairs({
    '\255',
    '\0',
    '\194',
    '\224\128\128',
    '\237\160\128',
    '\244\144\128\128',
  }) do
    local invalid_file = assert(io.open(root .. '/text.txt', 'wb'))
    invalid_file:write(invalid)
    invalid_file:close()
    assert(work.load(root).title == 'Work', 'discovery must not read reference bodies')
    assert(not pcall(work.validate, root), 'installation accepted invalid text')
    local reading = work.load(root)
    assert(not pcall(work.read_unit, reading, reading.units[1]), 'reading accepted invalid text')
  end
  vim.fn.writefile({ 'A poem 🐇' }, root .. '/text.txt', 'b')
  assert(work.read(work.load(root).units[1].reference)[1] == 'A poem 🐇', 'four-byte UTF-8')
  vim.fn.writefile({}, root .. '/text.txt')
  assert(#work.read(work.load(root).units[1].reference) == 0, 'empty reference')
  local file = assert(io.open(root .. '/text.txt', 'wb'))
  file:write('\239\187\191one\r\n\r\ntwo\r\n')
  file:close()
  assert(vim.deep_equal(work.read(root .. '/text.txt'), { 'one', '', 'two' }), 'BOM and CRLF')

  for _, case in ipairs({
    { '', 0 },
    { '\n', 1 },
    { '\n\n', 2 },
    { 'one', 1 },
    { 'one\n', 1 },
    { 'one\n\n', 2 },
    { 'one\r\n\r\ntwo\r\n', 3 },
    { '\239\187\191', 0 },
    { '\239\187\191one\n', 1 },
    { string.rep('long', 40000) .. '\n' .. string.rep('row\n', 40000) .. 'tail', 40002 },
  }) do
    local counted = assert(io.open(root .. '/text.txt', 'wb'))
    counted:write(case[1])
    counted:close()
    assert(work.count_lines(root .. '/text.txt') == case[2], 'physical line count: ' .. case[2])
    assert(#work.read(root .. '/text.txt') == case[2], 'reading and counting disagree')
  end
  local reading = work.load(root)
  vim.fn.delete(root .. '/text.txt')
  assert(
    vim.uv.fs_symlink(root .. '/chapters/02.txt', root .. '/text.txt'),
    'replace reference with symlink'
  )
  assert(
    not pcall(work.read_unit, reading, reading.units[1]),
    'opening must recheck symlink boundary'
  )
  local sample = work.load('examples/alice')
  assert(
    sample.author == 'Lewis Carroll' and sample.units[1].path == 'alice.txt',
    'sample manifest'
  )
  local examples, errors = work.discover('examples')
  assert(#examples > 0 and #errors == 0, 'bundled works must be discoverable')
  for _, example in ipairs(examples) do
    work.validate(example.root)
  end
  print('Lilt work: manifests, ordering, paths and UTF-8 passed')
end
local ok, err = xpcall(run, debug.traceback)
vim.fn.delete(root, 'rf')
if not ok then
  io.write(err .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
