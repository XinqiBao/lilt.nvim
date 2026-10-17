local api = vim.api
local online = require('lilt.online')
local work = require('lilt.work')
local prep = require('lilt.gutenberg')
local root = vim.fn.tempname()
local home = root .. '/library'
local system, notify, input = vim.system, vim.notify, vim.ui.input
local requests, jobs, messages = {}, {}, {}
local mode, held = 'ok', false
local fixture = '\239\187\191'
  .. table.concat(vim.fn.readfile('tests/fixtures/gutenberg.txt', 'b'), '\r\n')
local function entry(id, title)
  return {
    id = id,
    title = title or 'Test Letters',
    authors = { { name = 'A. Writer' } },
    subjects = { 'Letters -- Fiction' },
    languages = { 'en' },
    copyright = false,
    media_type = 'Text',
    formats = {
      ['text/plain; charset=utf-8'] = 'https://www.gutenberg.org/ebooks/' .. id .. '.txt.utf-8',
    },
  }
end
local function body(url)
  if not url:find('/books/', 1, true) then
    return fixture
  end
  local results = { entry(11), entry(12, 'A second work') }
  results[2].copyright = true
  if url:find('search=', 1, true) then
    results = {}
  end
  if url:find('page=2', 1, true) then
    results = { entry(13, 'Another page') }
  end
  return vim.json.encode({
    count = #results,
    results = results,
    next = not url:find('page=2', 1, true) and 'https://untrusted.invalid/?page=2' or vim.NIL,
  })
end
vim.notify = function(message)
  messages[#messages + 1] = message
end
vim.system = function(args, _, callback)
  if mode == 'spawn-error' then
    error('cannot start curl')
  end
  local path, url
  for i, arg in ipairs(args) do
    if arg == '--output' then
      path = args[i + 1]
    end
    if arg == '--url' then
      url = args[i + 1]
    end
  end
  assert(args[1] == 'curl' and path and url, 'use argument-vector curl with a private output')
  assert(
    vim.tbl_contains(args, '--max-filesize') and vim.tbl_contains(args, '=https'),
    'bounded HTTPS requests'
  )
  requests[#requests + 1] = url
  local job = { path = path, killed = false }
  jobs[#jobs + 1] = job
  function job:kill()
    self.killed = true
  end
  function job.finish()
    local text = mode == 'invalid-json' and '{bad'
      or mode == 'invalid-text' and '\255'
      or mode == 'no-markers' and 'An incomplete download.'
      or body(url)
    local file = assert(io.open(path, 'wb'))
    file:write(text)
    if mode == 'oversized' then
      file:seek('set', 12 * 1024 * 1024)
      file:write('x')
    end
    file:close()
    callback({ code = mode == 'network-error' and 22 or 0, stderr = 'HTTP 503' })
  end
  if not held then
    vim.schedule(job.finish)
  end
  return job
end
local function wait_for(condition, message)
  assert(vim.wait(2000, condition, 5), message or 'async completion timed out')
end
local function call(start)
  local result
  start(function(err, value)
    result = { err = err, value = value }
  end)
  wait_for(function()
    return result ~= nil
  end)
  return result.err, result.value
end
local function keys(text)
  api.nvim_feedkeys(api.nvim_replace_termcodes(text, true, false, true), 'xt', false)
  vim.wait(10, function()
    return false
  end)
end
local function lines()
  return api.nvim_buf_get_lines(0, 0, -1, false)
end
local function choose(label)
  for i, line in ipairs(lines()) do
    if line:find(label, 1, true) then
      api.nvim_win_set_cursor(0, { i, 0 })
      keys('l')
      return
    end
  end
  error('missing picker item: ' .. label .. '\n' .. table.concat(lines(), '\n'))
end
local function no_staging()
  assert(
    #vim.fn.glob(home .. '/references/.lilt-*', false, true) == 0,
    'installation staging leaked'
  )
  for _, job in ipairs(jobs) do
    assert(not vim.uv.fs_stat(job.path), 'download file leaked')
  end
end
local function run()
  local source = work.read('tests/fixtures/gutenberg.txt')
  local prepared = prep.prepare(source, 'Test Letters')
  assert(
    #prepared == 3 and prepared[2].title == 'CHAPTER I. The letter',
    'chapters, front matter, and TOC'
  )
  local text = table.concat(prepared[2].lines, '\n')
  assert(
    text:find('    Little Lamb, who made thee?\n    Dost thou know who made thee?\n\n', 1, true),
    'verse and stanza boundaries'
  )
  assert(text:find('“Café, 文学, and a rabbit 🐇,”', 1, true), 'Unicode fidelity')
  assert(text:find('CHORUS', 1, true), 'embedded capitals must stay inside chapters')
  assert(
    table.concat(prepared[3].lines, '\n'):find('  north    south', 1, true),
    'table indentation'
  )
  for _, row in ipairs(prepared[2].lines) do
    assert(vim.fn.strwidth(row) <= 80, 'prose wrapping')
  end
  local original_body, prepared_body, inside = {}, {}, false
  for _, row in ipairs(source) do
    if row:find('*** END OF', 1, true) then
      inside = false
    end
    if inside then
      original_body[#original_body + 1] = row
    end
    if row:find('*** START OF', 1, true) then
      inside = true
    end
  end
  for _, unit in ipairs(prepared) do
    vim.list_extend(prepared_body, unit.lines)
  end
  assert(
    table.concat(original_body):gsub('%s', '') == table.concat(prepared_body):gsub('%s', ''),
    'preparation must preserve every non-whitespace byte in order'
  )
  local verse = prep.prepare(source, 'Poetry', true)
  local long_line = fixture:match('(The snow arrived[^\r\n]+)')
  assert(
    vim.fn.strwidth(long_line) > 80 and vim.tbl_contains(verse[2].lines, long_line),
    'cataloged verse keeps even long lines'
  )
  local start_marker = '*** START OF THE PROJECT GUTENBERG EBOOK TEST ***'
  local end_marker = '*** END OF THE PROJECT GUTENBERG EBOOK TEST ***'
  for _, bad in ipairs({
    {},
    { 'no markers' },
    { start_marker, start_marker, 'text', end_marker },
    { start_marker, 'text', end_marker, end_marker },
    { start_marker, end_marker },
    { end_marker, 'text', start_marker },
    { start_marker, '\0', end_marker },
  }) do
    assert(not pcall(prep.prepare, bad, 'Bad'), 'unsafe boundaries/control characters accepted')
  end
  local many = { '*** START OF THIS PROJECT GUTENBERG ETEXT LETTERS ***' }
  for i = 1, 650 do
    many[#many + 1] = i % 10 == 0 and '' or 'Row ' .. i
  end
  many[#many + 1] = '*** END OF THIS PROJECT GUTENBERG ETEXT LETTERS ***'
  local parts = prep.prepare(many, 'Letters')
  assert(#parts == 2 and #parts[2].lines >= 80, 'long texts need useful parts, without tiny tails')

  local err, page = call(function(cb)
    online.catalog(online.default_catalog, {}, cb)
  end)
  assert(not err and #page.books == 2 and page.more, 'popular catalog')
  local book = page.books[1]
  assert(book.supported and not page.books[2].supported, 'copyright/format availability')
  err, page = call(function(cb)
    online.catalog(online.default_catalog, { search = 'café & `x`', page = 2 }, cb)
  end)
  assert(not err and #page.books == 1 and not page.more, 'pagination')
  assert(
    requests[#requests]:find('search=caf%C3%A9%20%26%20%60x%60&page=2', 1, true),
    'encode query as data'
  )
  for _, failure in ipairs({ 'network-error', 'invalid-json', 'oversized', 'spawn-error' }) do
    mode = failure
    err = call(function(cb)
      online.catalog(online.default_catalog, {}, cb)
    end)
    assert(err, 'catalog failure must be reported')
  end
  local executable = vim.fn.executable
  vim.fn.executable = function()
    return 0
  end
  err = call(function(cb)
    online.catalog(online.default_catalog, {}, cb)
  end)
  vim.fn.executable = executable
  assert(err and err:find('requires curl', 1, true), 'missing curl has an actionable error')
  mode, held = 'ok', true
  local delivered = false
  local cancel = online.catalog(online.default_catalog, {}, function()
    delivered = true
  end)
  local job = jobs[#jobs]
  cancel()
  job.finish()
  vim.wait(20, function()
    return false
  end)
  assert(
    job.killed and not delivered and not vim.uv.fs_stat(job.path),
    'cancel and late completion cleanup'
  )
  held = false
  for _, failure in ipairs({ 'network-error', 'invalid-text', 'no-markers' }) do
    mode = failure
    err = call(function(cb)
      online.acquire(home, book, cb)
    end)
    assert(
      err and not vim.uv.fs_stat(home .. '/references/gutenberg-11'),
      'failed acquisition published a work'
    )
    no_staging()
  end
  mode = 'ok'
  local copy = vim.uv.fs_copyfile
  vim.uv.fs_copyfile = function()
    error('disk failure')
  end
  err = call(function(cb)
    online.acquire(home, book, cb)
  end)
  vim.uv.fs_copyfile = copy
  assert(err and err:find('disk failure', 1, true), 'conversion/install disk failure')
  no_staging()

  -- The actual entry point, picker, preparation, library and reading session.
  local lilt = require('lilt')
  for _, invalid in ipairs({
    'http://example.org',
    'https:///',
    'https://user:password@example.org',
    'https://example.org/?key=value',
  }) do
    assert(
      not pcall(lilt.setup, { catalog = invalid }),
      'catalog configuration must be an HTTPS base without credentials/query'
    )
  end
  lilt.setup({ library = home, catalog = 'https://catalog.example.test/api/' })
  lilt.open()
  choose('Discover online')
  assert(requests[#requests] == 'https://catalog.example.test/api/books/', 'custom Gutendex base')
  keys('hq')
  lilt.setup({ catalog = online.default_catalog })
  lilt.setup({ library = home })
  lilt.open()
  choose('Discover online')
  assert(
    lines()[1]:find('Search title or author', 1, true),
    'browsing starts with real popular results: ' .. vim.inspect(lines()) .. vim.inspect(messages)
  )
  choose('More results')
  assert(lines()[7]:find('Another page', 1, true), 'navigate additional results')
  assert(
    requests[#requests] == online.default_catalog .. '/books/?page=2',
    'never follow foreign pagination URL'
  )
  keys('h')
  assert(
    lines()[7]:find('Test Letters', 1, true),
    'back preserves previous results without requesting again'
  )
  vim.ui.input = function(_, cb)
    cb('no such book')
  end
  keys('ggl')
  assert(table.concat(lines(), '\n'):find('No works found', 1, true), 'empty search')
  keys('h')
  vim.ui.input = function(_, cb)
    cb(nil)
  end
  keys('ggl')
  assert(lines()[7]:find('Test Letters', 1, true), 'search cancellation preserves browsing')
  vim.ui.input = function(_, cb)
    local scratch = api.nvim_create_buf(false, true)
    local prompt = api.nvim_open_win(scratch, true, {
      relative = 'editor',
      row = 1,
      col = 1,
      width = 20,
      height = 1,
      style = 'minimal',
    })
    api.nvim_win_close(prompt, true)
    api.nvim_buf_delete(scratch, { force = true })
    cb(nil)
  end
  keys('ggl')
  assert(
    lines()[7]:find('Test Letters', 1, true),
    'floating input override preserves picker lifetime'
  )
  choose('second work')
  assert(lines()[1]:find('Unavailable', 1, true), 'unsupported works explain the limitation')
  keys('h')
  choose('Test Letters')
  assert(
    table.concat(lines(), '\n'):find('https://www.gutenberg.org/ebooks/11', 1, true),
    'inspect source before download'
  )
  mode = 'network-error'
  choose('Acquire and read')
  assert(lines()[1]:find('retry', 1, true), 'download failure offers retry')
  mode = 'ok'
  keys('l')
  assert(lines()[2]:find('CHAPTER I.', 1, true), 'acquisition proceeds directly to reading units')
  local installed = work.validate(home .. '/references/gutenberg-11')
  assert(
    installed.source.id == '11' and installed.source.provider == 'Project Gutenberg',
    'portable provenance'
  )
  assert(
    table.concat(vim.fn.readfile(installed.root .. '/SOURCE.txt', 'b'), '\n') == fixture,
    'original and license retained verbatim'
  )
  local original = table.concat(work.read(installed.units[2].reference), '\n')
  local path = home .. '/manuscripts/gutenberg-11/002.txt'
  keys('jl')
  assert(api.nvim_buf_get_name(0) == path, 'ordinary durable manuscript')
  keys('iA saved line.<Esc>')
  vim.cmd.write()
  local manuscript = api.nvim_get_current_buf()
  lilt.split()
  lilt.ghost()
  lilt.close()
  lilt.open()
  keys('l')
  assert(lines()[2]:match('%d+%%$'), 'saved progress available')
  keys('jl')
  assert(
    api.nvim_get_current_buf() == manuscript and lines()[1] == 'A saved line.',
    'resume acquired work'
  )
  lilt.close()
  local count = #requests
  err, installed = call(function(cb)
    online.acquire(home, book, cb)
  end)
  assert(
    not err and installed.name == 'gutenberg-11' and #requests == count,
    'duplicates reuse stable copy without a download'
  )
  assert(
    table.concat(work.read(installed.units[2].reference), '\n') == original,
    'duplicate acquisition cannot change references'
  )
  assert(vim.fn.readfile(path)[1] == 'A saved line.', 'acquisition cannot overwrite manuscripts')
  local collision = root .. '/collision'
  vim.fn.mkdir(collision .. '/manuscripts/gutenberg-11', 'p')
  err = call(function(cb)
    online.acquire(collision, book, cb)
  end)
  assert(err and #requests == count, 'orphan manuscripts block acquisition before downloading')
  require('lilt.library').add(collision, 'examples/tyger')
  assert(
    work.validate(collision .. '/references/tyger').title,
    'existing local work remains compatible'
  )
  vim.fn.mkdir(root .. '/local/gutenberg-11', 'p')
  vim.fn.writefile({ 'Local reference' }, root .. '/local/gutenberg-11/text.txt')
  local local_manifest = {
    title = 'Unrelated local work',
    units = { { title = 'Text', path = 'text.txt' } },
  }
  vim.fn.writefile({ vim.json.encode(local_manifest) }, root .. '/local/gutenberg-11/lilt.json')
  require('lilt.library').add(root .. '/local-library', root .. '/local/gutenberg-11')
  err = call(function(cb)
    online.acquire(root .. '/local-library', book, cb)
  end)
  assert(err and #requests == count, 'same-name local work cannot be mistaken for a duplicate')
  assert(
    vim.fn.readfile(root .. '/local-library/references/gutenberg-11/text.txt')[1]
      == 'Local reference',
    'local reference unchanged'
  )

  lilt.open()
  choose('Discover online')
  choose('More results')
  choose('Another page')
  held = true
  choose('Acquire and read')
  local pending_requests = #requests
  keys('lll')
  assert(#requests == pending_requests, 'repeated selection cannot start concurrent downloads')
  job = jobs[#jobs]
  keys('h')
  job.finish()
  vim.wait(20, function()
    return false
  end)
  assert(
    job.killed and not vim.uv.fs_stat(home .. '/references/gutenberg-13'),
    'cancelled acquisition must not install'
  )
  held = false
  keys('hhhq')

  -- Retry and close are real picker transitions, including a late download.
  mode = 'network-error'
  lilt.open()
  choose('Discover online')
  assert(lines()[1]:find('retry', 1, true), 'recoverable network error page')
  mode = 'ok'
  keys('l')
  assert(lines()[7]:find('Test Letters', 1, true), 'retry succeeds')
  keys('hhq')
  held = true
  lilt.open()
  choose('Discover online')
  assert(lines()[1]:find('Loading catalog', 1, true), 'nonblocking progress')
  job = jobs[#jobs]
  keys('hq')
  job.finish()
  vim.wait(20, function()
    return false
  end)
  assert(
    job.killed and not pcall(api.nvim_get_autocmds, { group = 'LiltPicker' }),
    'closing cancels and releases picker resources'
  )
  held = false
  no_staging()
  print('Lilt online: catalog, cancellation, fidelity, installation and discover-to-reading passed')
end
local ok, err = xpcall(run, debug.traceback)
vim.system, vim.notify, vim.ui.input = system, notify, input
pcall(require('lilt').close)
vim.fn.delete(root, 'rf')
if not ok then
  io.write(err .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
