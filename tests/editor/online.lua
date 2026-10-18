local api = vim.api
local catalog = require('lilt.online.catalog')
local acquisition = require('lilt.online.acquire')
local work = require('lilt.work')
local root = vim.fn.tempname()
local home = root .. '/library'
local system, notify = vim.system, vim.notify
local requests, jobs, messages = {}, {}, {}
local mode, held, conversion, tool_check = 'ok', false, nil, nil
local fixture_path = assert(vim.env.LILT_TEST_EPUB, 'run through tests/run.py')
local function read_binary(path)
  local file = assert(io.open(path, 'rb'))
  local bytes = assert(file:read('*a'))
  file:close()
  return bytes
end
local fixture = read_binary(fixture_path)
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
      ['application/epub+zip'] = 'https://www.gutenberg.org/ebooks/' .. id .. '.epub.noimages',
    },
  }
end
local function body(url)
  if not url:find('/books/', 1, true) then
    return fixture
  end
  local results = { entry(11), entry(12, 'A second work') }
  if mode == 'plain-only' then
    results[1].formats = { ['text/plain'] = 'https://example.invalid/text.txt' }
  end
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
vim.system = function(args, opts, callback)
  if args[1] == 'pandoc' then
    if args[2] == '--version' then
      tool_check = { killed = false }
      function tool_check:kill()
        self.killed = true
      end
      function tool_check.finish()
        callback({
          code = mode == 'broken-pandoc' and 127 or 0,
          stdout = mode == 'old-pandoc' and 'pandoc 3.0' or 'pandoc 3.8.3',
        })
      end
      if mode ~= 'hold-tool-check' then
        vim.schedule(tool_check.finish)
      end
      return tool_check
    end
    if mode == 'hold-conversion' then
      conversion = { source = args[#args] }
      for _, arg in ipairs(args) do
        conversion.output = arg:match('^%-%-output=(.+)$') or conversion.output
      end
      function conversion:kill()
        self.killed = true
      end
      function conversion.finish()
        vim.fn.writefile({ '[]' }, conversion.output)
        callback({ code = 0, stderr = '' })
      end
      return conversion
    end
    return system(args, opts, callback)
  end
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
      or mode == 'invalid-epub' and 'An incomplete download.'
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
  local err, page = call(function(cb)
    catalog.fetch(catalog.default_url, {}, cb)
  end)
  assert(not err and #page.books == 2 and page.more, 'popular catalog')
  local book = page.books[1]
  assert(book.supported and not page.books[2].supported, 'copyright/format availability')
  mode = 'plain-only'
  err, page = call(function(cb)
    catalog.fetch(catalog.default_url, {}, cb)
  end)
  assert(
    not err and not page.books[1].supported,
    'plain-text availability must not imply EPUB support'
  )
  mode = 'ok'
  err, page = call(function(cb)
    catalog.fetch(catalog.default_url, { search = 'café & `x`', page = 2 }, cb)
  end)
  assert(not err and #page.books == 1 and not page.more, 'pagination')
  assert(
    requests[#requests]:find('search=caf%C3%A9%20%26%20%60x%60&page=2', 1, true),
    'encode query as data'
  )
  for _, failure in ipairs({ 'network-error', 'invalid-json', 'oversized', 'spawn-error' }) do
    mode = failure
    err = call(function(cb)
      catalog.fetch(catalog.default_url, {}, cb)
    end)
    assert(err, 'catalog failure must be reported')
  end
  local executable = vim.fn.executable
  vim.fn.executable = function()
    return 0
  end
  err = call(function(cb)
    catalog.fetch(catalog.default_url, {}, cb)
  end)
  vim.fn.executable = executable
  assert(err and err:find('requires curl', 1, true), 'missing curl has an actionable error')
  mode, held = 'ok', true
  local delivered = false
  local cancel = catalog.fetch(catalog.default_url, {}, function()
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
  local request_count = #requests
  vim.fn.executable = function(name)
    return name == 'pandoc' and 0 or executable(name)
  end
  err = call(function(cb)
    acquisition.acquire(home, book, cb)
  end)
  vim.fn.executable = executable
  assert(
    err and err:find('requires Pandoc', 1, true) and #requests == request_count,
    'missing conversion tool must explain installation before downloading'
  )
  for _, failure in ipairs({ 'old-pandoc', 'broken-pandoc' }) do
    mode = failure
    err = call(function(cb)
      acquisition.acquire(home, book, cb)
    end)
    assert(
      err and err:find('3.1.1', 1, true) and #requests == request_count,
      'unusable tools must fail before any download'
    )
  end
  mode = 'hold-tool-check'
  delivered = false
  cancel = acquisition.acquire(home, book, function()
    delivered = true
  end)
  cancel()
  tool_check.finish()
  vim.wait(20, function()
    return false
  end)
  assert(
    tool_check.killed and not delivered and #requests == request_count,
    'cancelling preflight must suppress a late success before downloading'
  )
  for _, failure in ipairs({ 'network-error', 'invalid-epub' }) do
    mode = failure
    err = call(function(cb)
      acquisition.acquire(home, book, cb)
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
    acquisition.acquire(home, book, cb)
  end)
  vim.uv.fs_copyfile = copy
  assert(err and err:find('disk failure', 1, true), 'conversion/install disk failure')
  no_staging()

  mode = 'hold-conversion'
  delivered = false
  cancel = acquisition.acquire(root .. '/cancel-converter', book, function()
    delivered = true
  end)
  wait_for(function()
    return conversion ~= nil
  end, 'conversion did not start')
  assert(vim.uv.fs_stat(conversion.source), 'conversion needs its own surviving source copy')
  cancel()
  conversion.finish()
  wait_for(function()
    return not vim.uv.fs_stat(conversion.output)
  end, 'late converter output was not removed')
  assert(
    conversion.killed
      and not delivered
      and not vim.uv.fs_stat(conversion.source)
      and not vim.uv.fs_stat(root .. '/cancel-converter/references/gutenberg-11'),
    'cancelling preparation must clean staging and never publish or deliver'
  )
  mode = 'ok'

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
  keys('d')
  assert(requests[#requests] == 'https://catalog.example.test/api/books/', 'custom Gutendex base')
  keys('hq')
  lilt.setup({ catalog = catalog.default_url })
  lilt.setup({ library = home })
  lilt.open()
  choose('Discover online')
  assert(
    table.concat(lines(), '\n'):find('Test Letters', 1, true),
    'browsing starts with popular results'
  )
  keys(']')
  assert(table.concat(lines(), '\n'):find('Another page', 1, true), 'navigate additional results')
  assert(
    requests[#requests] == catalog.default_url .. '/books/?page=2',
    'never follow foreign pagination URL'
  )
  keys('[')
  assert(
    table.concat(lines(), '\n'):find('Test Letters', 1, true),
    'previous page returns to the same query'
  )
  choose('Newest')
  assert(
    requests[#requests]:find('sort=descending', 1, true),
    'newest means descending catalog IDs'
  )
  choose('Poetry')
  assert(requests[#requests]:find('topic=poetry', 1, true), 'poetry is a topic preset')
  choose('Short stories')
  assert(
    requests[#requests]:find('topic=short%20stories', 1, true),
    'short stories is a topic preset'
  )
  keys('h')
  assert(
    table.concat(lines(), '\n'):find('Discover online', 1, true),
    'query and page changes do not add back navigation depth'
  )
  choose('Discover online')
  keys('s')
  api.nvim_buf_set_lines(0, 0, -1, false, { 'no such book' })
  keys('<CR>')
  assert(table.concat(lines(), '\n'):find('No works found', 1, true), 'empty search')
  keys('s')
  api.nvim_buf_set_lines(0, 0, -1, false, { 'cancelled' })
  keys('<Esc>')
  assert(
    table.concat(lines(), '\n'):find('No works found', 1, true),
    'search cancellation preserves browsing'
  )
  keys('s')
  api.nvim_buf_set_lines(0, 0, -1, false, { '' })
  keys('<CR>')
  assert(
    table.concat(lines(), '\n'):find('Test Letters', 1, true),
    'empty query returns to popular works'
  )
  local result_requests = #requests
  choose('second work')
  assert(
    table.concat(lines(), '\n'):find('Unavailable', 1, true),
    'unsupported works explain the limitation'
  )
  keys('h')
  assert(
    lines()[api.nvim_win_get_cursor(0)[1]]:find('second work', 1, true)
      and #requests == result_requests,
    'details back restores result selection without a request'
  )
  choose('Test Letters')
  assert(
    table.concat(lines(), '\n'):find('https://www.gutenberg.org/ebooks/11', 1, true),
    'inspect source before download'
  )
  mode = 'network-error'
  local before_failure = #messages
  keys('a')
  assert(#messages == before_failure, 'request error appears once inside the picker')
  assert(table.concat(lines(), '\n'):find('retry', 1, true), 'download failure offers retry')
  mode = 'ok'
  keys('r')
  wait_for(function()
    return table.concat(lines(), '\n'):find('The letter — 第一封信', 1, true) ~= nil
  end, 'acquisition did not reach unit selection')
  assert(
    table.concat(lines(), '\n'):find('The letter — 第一封信', 1, true),
    'acquisition proceeds directly to reading units'
  )
  local installed = work.validate(home .. '/references/gutenberg-11')
  assert(
    installed.source.id == '11' and installed.source.provider == 'Project Gutenberg',
    'portable provenance'
  )
  assert(
    read_binary(installed.root .. '/SOURCE.epub') == fixture,
    'original and license retained verbatim'
  )
  local original = table.concat(work.read(installed.units[2].reference), '\n')
  assert(
    original:find('"Café, 文学, and a rabbit 🐇,"', 1, true),
    'new English reading units use keyboard-friendly quotes'
  )
  for i, languages in ipairs({ { 'fr' }, { 'en', 'fr' }, {} }) do
    local other = vim.tbl_extend('force', book, { languages = languages })
    local language_error, reading = call(function(cb)
      acquisition.acquire(root .. '/original-punctuation-' .. i, other, cb)
    end)
    assert(not language_error, tostring(language_error))
    assert(
      table.concat(work.read(reading.units[2].reference), '\n'):find('“Café', 1, true),
      'non-English, multilingual, and unknown-language works retain source punctuation'
    )
  end
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
  assert(table.concat(lines(), '\n'):find('%%'), 'saved progress available')
  keys('jl')
  assert(
    api.nvim_get_current_buf() == manuscript and lines()[1] == 'A saved line.',
    'resume acquired work'
  )
  lilt.close()
  -- Model a copy acquired before quote simplification, with saved writing.
  original = '“An earlier reading copy.”'
  vim.fn.writefile({ original }, installed.units[2].reference)
  local count = #requests
  vim.fn.executable = function()
    return 0
  end
  err, installed = call(function(cb)
    acquisition.acquire(home, book, cb)
  end)
  vim.fn.executable = executable
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
    acquisition.acquire(collision, book, cb)
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
    acquisition.acquire(root .. '/local-library', book, cb)
  end)
  assert(err and #requests == count, 'same-name local work cannot be mistaken for a duplicate')
  assert(
    vim.fn.readfile(root .. '/local-library/references/gutenberg-11/text.txt')[1]
      == 'Local reference',
    'local reference unchanged'
  )

  lilt.open()
  choose('Discover online')
  choose('Next page')
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
  keys('hq')

  for _, dismiss in ipairs({
    function()
      api.nvim_win_close(0, true)
    end,
    function()
      api.nvim_buf_delete(0, { force = true })
    end,
  }) do
    lilt.open()
    choose('Discover online')
    choose('Next page')
    choose('Another page')
    held = true
    choose('Acquire and read')
    job = jobs[#jobs]
    local notifications = #messages
    job.finish() -- Success is queued before the user dismisses the picker.
    dismiss()
    vim.wait(20, function()
      return false
    end)
    assert(
      job.killed and not vim.uv.fs_stat(home .. '/references/gutenberg-13'),
      'native dismissal must cancel even an already queued acquisition completion'
    )
    assert(
      #messages == notifications and not pcall(api.nvim_get_autocmds, { group = 'LiltPicker' }),
      'dismissal must release resources without rendering into a destroyed window'
    )
    held = false
  end

  for _, quit in ipairs({ 'q', '<Esc>' }) do
    lilt.open()
    keys('d')
    keys(']')
    choose('Another page')
    held = true
    keys('a')
    job = jobs[#jobs]
    keys(quit)
    job.finish()
    vim.wait(20, function()
      return false
    end)
    assert(
      job.killed
        and not vim.uv.fs_stat(home .. '/references/gutenberg-13')
        and not pcall(api.nvim_get_autocmds, { group = 'LiltPicker' }),
      'quit from acquiring details cancels the download and closes every page'
    )
    held = false
  end

  -- Retry and close are real picker transitions, including a late download.
  mode = 'network-error'
  lilt.open()
  choose('Discover online')
  assert(table.concat(lines(), '\n'):find('retry', 1, true), 'recoverable network error page')
  mode = 'ok'
  keys('l')
  assert(table.concat(lines(), '\n'):find('Test Letters', 1, true), 'retry succeeds')
  keys('hq')
  held = true
  lilt.open()
  choose('Discover online')
  assert(table.concat(lines(), '\n'):find('Loading catalog', 1, true), 'nonblocking progress')
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
  -- Search owns an additional editable buffer, including during native dismissal.
  for _, dismiss in ipairs({
    function()
      api.nvim_win_close(0, true)
    end,
    function()
      api.nvim_buf_delete(0, { force = true })
    end,
    function()
      api.nvim_win_set_buf(0, api.nvim_create_buf(true, false))
    end,
    function()
      api.nvim_set_current_win(api.nvim_tabpage_list_wins(0)[1])
    end,
  }) do
    lilt.open()
    choose('Discover online')
    local menu = api.nvim_get_current_buf()
    keys('s')
    local search_buf, before_search_close = api.nvim_get_current_buf(), #requests
    dismiss()
    vim.wait(20, function()
      return false
    end)
    assert(
      not api.nvim_buf_is_valid(menu) and not api.nvim_buf_is_valid(search_buf),
      'search dismissal releases both buffers'
    )
    assert(
      #requests == before_search_close
        and not pcall(api.nvim_get_autocmds, { group = 'LiltPicker' }),
      'search dismissal sends no request or leaves callbacks'
    )
  end
  no_staging()
  print('Lilt online: catalog, cancellation, fidelity, installation and discover-to-reading passed')
end
local ok, err = xpcall(run, debug.traceback)
vim.system, vim.notify = system, notify
pcall(require('lilt').close)
vim.fn.delete(root, 'rf')
if not ok then
  io.write(err .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
