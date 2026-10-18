local library = require('lilt.library')
local function list(root)
  return require('lilt.work').discover(root .. '/references')
end
local root = vim.fn.tempname()
local source = root .. '/source/a-work'
local home = root .. '/library'
local function run()
  vim.fn.mkdir(source .. '/chapters', 'p')
  vim.fn.writefile({ 'One', '', 'Three' }, source .. '/chapters/01.txt')
  vim.fn.writefile({}, source .. '/empty.txt')
  vim.fn.writefile({ 'Source attribution' }, source .. '/README.md')
  vim.fn.writefile({
    vim.json.encode({
      title = 'A Work',
      units = {
        { title = 'Opening', path = 'chapters/01.txt' },
        { title = 'Empty', path = 'empty.txt' },
      },
    }),
  }, source .. '/lilt.json')
  assert(#list(home) == 0, 'missing library must be empty')
  local added = library.add(home, source)
  assert(added.name == 'a-work' and #added.units == 2, 'installed work metadata')
  assert(vim.fn.readfile(added.root .. '/README.md')[1] == 'Source attribution', 'copy attribution')
  assert(not pcall(library.add, home, source), 'duplicate must not overwrite')
  -- Observe actual opens: discovery must not read even installed reference bodies.
  local original_open = io.open
  -- selene: allow(incorrect_standard_library_use)
  io.open = function(path, ...)
    assert(not path:match('%.txt$'), 'discovery opened a reference body: ' .. path)
    return original_open(path, ...)
  end
  local discovered, discovery_errors = list(home)
  -- selene: allow(incorrect_standard_library_use)
  io.open = original_open
  assert(#discovered == 1 and #discovery_errors == 0, 'metadata-only discovery')
  vim.fn.writefile({ '\255' }, source .. '/chapters/01.txt', 'b')
  assert(
    not pcall(library.add, root .. '/invalid-library', source),
    'install must validate reference bodies'
  )
  assert(
    vim.fn.isdirectory(root .. '/invalid-library/references/a-work') == 0,
    'invalid text was published'
  )
  vim.fn.delete(root .. '/source', 'rf')
  local works, errors = list(home)
  assert(#works == 1 and #errors == 0, 'copy must be independent of source')
  local unit = works[1].units[1]
  assert(library.progress(home, added, unit) == nil, 'missing manuscript indicator')
  local path = library.manuscript(home, added, unit)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  vim.fn.writefile({}, path)
  assert(library.progress(home, added, unit) == 0, 'empty saved manuscript')
  vim.fn.writefile({ 'One' }, path)
  assert(library.progress(home, added, unit) == 33, 'partial percentage')
  vim.fn.writefile({ 'One', '', 'Three', 'Four' }, path)
  assert(library.progress(home, added, unit) == 133, 'over 100 percent')
  local empty = added.units[2]
  vim.fn.writefile({}, library.manuscript(home, added, empty))
  assert(library.progress(home, added, empty) == 0, 'empty reference denominator')
  vim.fn.writefile({ 'Extra' }, library.manuscript(home, added, empty))
  assert(library.progress(home, added, empty) == 100, 'extra text on empty reference')

  -- Fail after staging has received at least one file, using a real unsupported
  -- filesystem entry rather than a mocked copy operation.
  local bad = root .. '/bad-work'
  vim.fn.mkdir(bad, 'p')
  vim.fn.writefile({ 'text' }, bad .. '/a.txt')
  vim.fn.writefile(
    { vim.json.encode({ title = 'Bad', units = { { title = 'Text', path = 'a.txt' } } }) },
    bad .. '/lilt.json'
  )
  assert(vim.uv.fs_symlink(bad .. '/a.txt', bad .. '/z-link'), 'create copy failure fixture')
  assert(not pcall(library.add, home, bad), 'unsupported entry must fail import')
  assert(
    vim.fn.isdirectory(home .. '/references/bad-work') == 0,
    'failed import must not be visible'
  )
  assert(#vim.fn.glob(home .. '/references/.lilt-*', false, true) == 0, 'staging must be cleaned')
  vim.fn.delete(bad .. '/z-link')
  local copyfile = vim.uv.fs_copyfile
  vim.uv.fs_copyfile = function()
    error('unexpected copy failure')
  end
  local copied, copy_error = pcall(library.add, home, bad)
  vim.uv.fs_copyfile = copyfile
  assert(
    not copied and tostring(copy_error):find('unexpected copy failure', 1, true),
    'installation must report an unexpected copy exception'
  )
  assert(
    vim.fn.isdirectory(home .. '/references/bad-work') == 0
      and #vim.fn.glob(home .. '/references/.lilt-*', false, true) == 0,
    'unexpected exceptions must clean staging without publishing'
  )
  vim.fn.mkdir(home .. '/manuscripts/bad-work', 'p')
  assert(
    not pcall(library.add, home, bad),
    'orphan manuscripts must prevent accidental reassociation'
  )
  assert(not pcall(library.add, bad .. '/nested', bad), 'recursive import must be rejected')
  vim.fn.mkdir(home .. '/references/broken', 'p')
  vim.fn.mkdir(home .. '/references/bad:name', 'p')
  works, errors = list(home)
  assert(#works == 1 and #errors == 2, 'invalid works and names must not hide valid works')
  print('Lilt library: discovery, copy/cleanup, collisions and saved progress passed')
end
local ok, err = xpcall(run, debug.traceback)
vim.fn.delete(root, 'rf')
if not ok then
  io.write(err .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
