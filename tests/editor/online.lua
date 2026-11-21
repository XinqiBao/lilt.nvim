local api = vim.api
local catalog = require('lilt.online.catalog')
local acquisition = require('lilt.online.acquire')
local provider = require('lilt.online.providers.gutenberg').new()
local registry = require('lilt.online.providers')
local registry_list = registry.list
registry.list = function(base)
  return { require('lilt.online.providers.gutenberg').new(base) }
end
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
  if mode == 'changed-metadata' then
    results[1].title = 'Catalog title changed'
    results[1].translators = { { name = 'New catalog translator' } }
  end
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
local function shared_preparation()
  local materialize = require('lilt.online.materialize')
  vim.fn.mkdir(root, 'p')
  local metadata = {
    title = 'A poem',
    authors = { 'A. Poet' },
    source = {
      provider = 'test-source',
      id = 'chosen',
      url = 'https://example.org/poem',
      version = '0.2',
      title = 'Illustrated copy',
    },
    rights = 'Source rights notice',
    rights_url = 'https://example.org/license',
  }
  local rows = { '  “A poem 🐇”  ', '', 'Last stanza', '', '' }
  local prepared = materialize.text(rows, root .. '/text-work', metadata)
  assert(
    vim.deep_equal(work.read(root .. '/text-work/001.txt'), rows),
    'all physical source rows survive unchanged'
  )
  assert(
    not prepared.manifest.preparation.plain_quotes
      and prepared.snapshot
      and prepared.attribution
      and prepared.import_warnings,
    'text helper returns the shared prepared envelope'
  )
  for i, invalid in ipairs({
    { 'embedded\nrow' },
    { 'embedded\rrow' },
    { '\0' },
    { '\255' },
    { '\194' },
    { '\239\187\191BOM' },
    { 12 },
  }) do
    assert(
      not pcall(materialize.text, invalid, root .. '/invalid-rows-' .. i, metadata),
      'changed or invalid source rows must fail preparation'
    )
  end
  local blank = materialize.text({ '' }, root .. '/blank-row', metadata)
  assert(
    #work.read(root .. '/blank-row/001.txt') == 1 and #blank.manifest.units == 1,
    'one blank row is valid text'
  )
  local selected_entry = vim.tbl_extend('force', vim.deepcopy(metadata), { supported = true })
  local temporary, substituted, mutate = nil, true, false
  local fake = { id = 'test-source', name = 'Test Source' }
  function fake.prepare(selected, directory, callback)
    temporary = vim.fn.fnamemodify(directory, ':h')
    local result = materialize.text(rows, directory, vim.deepcopy(metadata))
    result.manifest.source.file = 'SOURCE.txt'
    vim.fn.writefile({ 'original source and license' }, directory .. '/SOURCE.txt')
    result.attribution = { 'Retain the original source license.' }
    if substituted then
      result.manifest.source.id = 'substituted'
    end
    if mutate then
      selected.source.id = 'substituted'
    end
    vim.schedule(function()
      callback(nil, result)
    end)
    return function() end
  end
  local destination = root .. '/shared-library'
  for _, mutation in ipairs({ false, true }) do
    mutate = mutation
    local err = call(function(cb)
      acquisition.acquire(destination, fake, selected_entry, cb)
    end)
    assert(
      err and err:find('identity', 1, true),
      'prepared source cannot substitute or mutate selection'
    )
    assert(
      not vim.uv.fs_stat(temporary) and not vim.uv.fs_stat(destination .. '/references'),
      'rejected preparation cleans staging without publication'
    )
    selected_entry.source = vim.deepcopy(metadata.source)
  end
  substituted, mutate = false, false
  local err, reading = call(function(cb)
    acquisition.acquire(destination, fake, selected_entry, cb)
  end)
  assert(not err and reading.source.id == 'chosen', tostring(err))
  assert(not vim.uv.fs_stat(temporary), 'successful preparation cleans staging')
  local credits = read_binary(reading.root .. '/README.txt')
  assert(
    credits:find('Source version: 0.2', 1, true)
      and credits:find('Source copy title: Illustrated copy', 1, true)
      and credits:find(metadata.rights, 1, true)
      and credits:find(metadata.rights_url, 1, true),
    'source revision and rights are retained offline'
  )
end
local function unified_discovery(lilt)
  local pending = {}
  local function request(id, query, callback)
    local job = { id = id, query = query, callback = callback }
    pending[#pending + 1] = job
    return function()
      job.cancelled = true
    end
  end
  local function source(id, name, search)
    local p = { id = id, name = name, browse = {} }
    p.browse.explore = function(cursor, cb)
      return request(id, cursor, cb)
    end
    if search then
      p.search = function(text, cursor, cb)
        return request(id, { search = text, cursor = cursor }, cb)
      end
    end
    return p
  end
  local first = source('first', 'First Library', true)
  local second = source('second', 'Second Library', true)
  local third = source('third', 'Browse Library', false)
  first.browse.poetry = function(cursor, cb)
    return request('poetry', cursor, cb)
  end
  first.expand = function(query, cb)
    return request('group', query, cb)
  end
  registry.list = function()
    return { first, second, third }
  end
  local function text()
    return table.concat(lines(), '\n')
  end
  local function finish(job, err, page)
    job.callback(err, page)
    vim.wait(10, function()
      return false
    end)
  end
  local function item(id, title, provider_id)
    return {
      kind = 'work',
      title = title,
      authors = { 'A. Writer' },
      supported = false,
      availability = 'Unavailable: fixture',
      source = { provider = provider_id or 'first', id = id, url = 'https://example.org/' .. id },
    }
  end
  lilt.open()
  keys('d')
  assert(
    #pending == 3 and text():find('[b] Browse categories', 1, true),
    'Discover immediately requests Explore with search and categories available'
  )
  assert(
    not text():find('Choose source', 1, true) and not text():find('Browse poets', 1, true),
    'no source chooser or unsupported categories'
  )
  assert(
    #pending == 3 and not text():find('Load more', 1, true),
    'one concurrent request per source and no in-flight load action'
  )
  local works = {}
  for i = 1, 32 do
    works[i] = item(tostring(i), 'Fast work ' .. i)
  end
  works[24].title = 'Fast work 24 ' .. string.rep('long title ', 12)
  works[#works + 1] =
    { kind = 'group', id = 'author:one', label = 'Selected author', query = { author = 'one' } }
  finish(pending[1], nil, { entries = works, next = 'next-first', title = '900 source records' })
  assert(
    text():find('Fast work 1', 1, true) and text():find('Selected author ›', 1, true),
    'successful works are usable during a slow peer and groups are visibly expandable'
  )
  assert(
    not text():find('900 source records', 1, true) and not text():find('Poetry', 1, true),
    'results keep content first without category menus or normal source diagnostics'
  )
  local row
  for i, line in ipairs(lines()) do
    if line:find('Fast work 24', 1, true) then
      row = i
    end
  end
  api.nvim_win_set_cursor(0, { row, 0 })
  local position, view = api.nvim_win_get_cursor(0), vim.fn.winsaveview()
  finish(pending[2], 'fixture peer failed')
  finish(pending[3], nil, { entries = {} })
  assert(
    vim.deep_equal(api.nvim_win_get_cursor(0), position)
      and vim.fn.winsaveview().topline == view.topline,
    'partial and settled updates preserve selection/scroll'
  )
  assert(
    text():find('Some results unavailable', 1, true)
      and text():find('Second Library · Request failed: fixture peer failed', 1, true),
    'partial success retains the failed source cause'
  )
  assert(
    text():find('Load more', 1, true) and text():find('Retry failed', 1, true),
    'continuation and failure have independent actions'
  )
  keys('<CR>')
  assert(text():find('first:24', 1, true), 'compact result opens its exact work details')
  keys('h')
  assert(
    vim.deep_equal(api.nvim_win_get_cursor(0), position),
    'details restore selected result row'
  )
  choose('Load more')
  assert(
    api.nvim_win_get_cursor(0)[1] > 20 and vim.fn.winsaveview().topline > 1,
    'clicking Load more preserves the scrolled result boundary'
  )
  assert(
    #pending == 4 and pending[4].id == 'first' and pending[4].query == 'next-first',
    'load more skips failed and exhausted peers'
  )
  finish(pending[4], nil, { entries = { item('33', 'Continued work') } })
  assert(
    text():find('Fast work 1', 1, true) and text():find('Continued work', 1, true),
    'load more appends without replacing earlier results'
  )
  choose('Retry failed')
  assert(
    lines()[api.nvim_win_get_cursor(0)[1]]:find('Continued work', 1, true)
      and vim.fn.winsaveview().topline > 1,
    'clicking Retry failed retains the scrolled result boundary'
  )
  assert(#pending == 5 and pending[5].id == 'second', 'retry requests failed sources only')
  finish(pending[5], nil, { entries = {}, empty = 'No eligible copies.' })
  assert(
    not text():find('Some results unavailable', 1, true)
      and not text():find('Retry failed', 1, true),
    'successful empty retry clears stale failure without hiding works'
  )
  choose('Selected author')
  assert(
    pending[6].id == 'group' and pending[6].query.author == 'one',
    'group expansion retains its provider query'
  )
  assert(
    vim.inspect(api.nvim_win_get_config(0).title):find('Selected author', 1, true),
    'group page title leads with the selected content rather than the provider'
  )
  finish(pending[6], 'temporary group failure')
  keys('r')
  finish(pending[7], nil, {
    entries = { item('copy', 'An exact copy') },
    title = '1 eligible copy from 10 source records',
    next = { author = 'next' },
  })
  assert(
    text():find('1 eligible copy from 10 source records', 1, true),
    'expanded groups retain honest provider-specific context'
  )
  keys(']')
  finish(
    pending[8],
    nil,
    { entries = {}, empty = 'No eligible copies.', previous = { author = 'one' } }
  )
  keys('[')
  finish(pending[9], nil, { entries = { item('copy', 'An exact copy') } })
  keys('h')
  assert(
    text():find('Selected author', 1, true) and #pending == 9,
    'group back restores accumulated parent without a request'
  )
  local parent_position, parent_view = api.nvim_win_get_cursor(0), vim.fn.winsaveview()
  keys('b')
  assert(
    text():find('Poetry', 1, true) and not text():find('Browse poets', 1, true),
    'category menu exposes supported categories only'
  )
  choose('Explore')
  assert(
    #pending == 9
      and vim.deep_equal(api.nvim_win_get_cursor(0), parent_position)
      and vim.fn.winsaveview().topline == parent_view.topline,
    'same category preserves its feed, selection and viewport without a request'
  )
  keys('b')
  choose('Poetry')
  assert(
    #pending == 10 and pending[10].id == 'poetry',
    'category with one participant sends no unsupported requests'
  )
  finish(pending[10], nil, { entries = {}, next = 'another-poetry-batch' })
  assert(
    text():find('No works found in this batch.', 1, true)
      and text():find('Load more', 1, true)
      and not text():find('Second Library', 1, true),
    'empty category batch can continue without unsupported source diagnostics'
  )
  keys('s')
  api.nvim_buf_set_lines(0, 0, -1, false, { 'fixture query' })
  keys('<CR>')
  assert(#pending == 12, 'search invokes only capable sources')
  finish(pending[11], nil, { entries = {} })
  finish(pending[12], 'search failed')
  assert(
    text():find('Could not complete search.', 1, true)
      and text():find('Some collections are browse-only.', 1, true),
    'partial empty search explains failures and browse-only coverage'
  )
  keys('r')
  finish(pending[13], nil, { entries = { item('recovered', 'Recovered result', 'second') } })
  choose('Recovered result')
  assert(
    text():find('Second Library', 1, true) and text():find('second:recovered', 1, true),
    'recovered work keeps original provider identity'
  )
  keys('hhb')
  choose('Explore')
  local fast, slow, browse = pending[14], pending[15], pending[16]
  finish(fast, nil, { entries = { item('fast', 'Usable early result') } })
  choose('Usable early result')
  assert(
    slow.cancelled and browse.cancelled,
    'opening details cancels pending peers through shared lifetime'
  )
  finish(slow, nil, { entries = { item('late', 'Stale result', 'second') } })
  keys('h')
  assert(
    text():find('Paused', 1, true)
      and not text():find('Loading', 1, true)
      and not text():find('Stale result', 1, true),
    'cached cancelled feed resumes honestly without stale loading or late rows'
  )
  keys(']')
  assert(
    #pending == 18 and pending[17].id == 'second' and pending[18].id == 'third',
    'load more resumes cancelled peers without refetching completed source'
  )
  finish(pending[17], nil, { entries = {} })
  finish(pending[18], nil, { entries = {} })
  keys('q')
  registry.list = function()
    return { third }
  end
  lilt.open()
  keys('ds')
  api.nvim_buf_set_lines(0, 0, -1, false, { 'unsupported search' })
  keys('<CR>')
  assert(
    #pending == 19
      and text():find('Unsupported by available sources', 1, true)
      and text():find('Some collections are browse-only.', 1, true)
      and not text():find('No matching works found', 1, true)
      and not text():find('Retry failed', 1, true),
    'wholly unsupported search does not claim empty results or a request failure'
  )
  keys('q')
end

local function discovery_navigation()
  local calls, cancellations = {}, 0
  local function request(query, cb)
    calls[#calls + 1] = query
    local entries = {}
    for i = 1, 24 do
      entries[i] = {
        title = query .. ' work ' .. i,
        supported = false,
        source = { provider = 'navigation', id = tostring(i), url = 'https://example.org/' .. i },
      }
    end
    cb(nil, { entries = entries, next = 'next' })
    return function()
      cancellations = cancellations + 1
    end
  end
  local saved = registry.list
  registry.list = function()
    return {
      {
        id = 'navigation',
        name = 'Navigation fixture',
        browse = {
          explore = function(_, cb)
            return request('Explore', cb)
          end,
          poetry = function(_, cb)
            return request('Poetry', cb)
          end,
        },
        search = function(query, _, cb)
          return request(query, cb)
        end,
      },
    }
  end
  local s = require('lilt.picker.ui').new(function() end)
  s:push({ title = 'Library', items = { { label = 'Local works' } } })
  require('lilt.picker.discover').open(s, home, nil, function() end, function() end)
  assert(#s.pages == 2 and #calls == 1, 'Discover immediately opens one Explore browse layer')
  choose('Explore work 20')
  keys('h')
  local browse = s:page()
  local selected, view = browse.selected, vim.fn.winsaveview()
  keys('b')
  keys('h')
  assert(
    s:page() == browse
      and browse.selected == selected
      and vim.fn.winsaveview().topline == view.topline,
    'category menu back restores browse exactly'
  )
  keys('s')
  assert(lines()[1] == '', 'first search starts empty')
  api.nvim_buf_set_lines(0, 0, -1, false, { 'first query' })
  keys('<CR>')
  assert(#s.pages == 3 and #calls == 2, 'search pushes once above browse')
  keys('s')
  assert(lines()[1] == 'first query', 'query editor starts from the current search')
  api.nvim_buf_set_lines(0, 0, -1, false, { 'edited query' })
  keys('<CR>')
  assert(#s.pages == 3 and calls[3] == 'edited query', 'query edit replaces the search layer')
  keys('h')
  assert(
    s:page() == browse
      and browse.selected == selected
      and vim.fn.winsaveview().topline == view.topline
      and #calls == 3,
    'Back from edited search restores exact browse selection and viewport without I/O'
  )
  keys('s')
  api.nvim_buf_set_lines(0, 0, -1, false, { 'another query' })
  keys('<CR>b')
  choose('Explore')
  assert(
    #s.pages == 2 and s:page() == browse and browse.selected == selected and #calls == 4,
    'same category from search returns to the retained browse without refetching'
  )
  keys('s')
  api.nvim_buf_set_lines(0, 0, -1, false, { 'last query' })
  keys('<CR>b')
  choose('Poetry')
  assert(
    #s.pages == 2 and s:page() ~= browse and calls[6] == 'Poetry',
    'different category from search replaces the browse layer'
  )
  keys('b')
  choose('Explore')
  assert(#s.pages == 2 and calls[7] == 'Explore', 'category switches never accumulate history')
  keys('h')
  assert(
    #s.pages == 1 and s:page().title == 'Library' and cancellations == 0,
    'browse Back returns directly to library; completed startup cancels are not called'
  )
  s:close()
  registry.list = saved
end

local function run()
  shared_preparation()
  local err, page = call(function(cb)
    catalog.fetch(catalog.default_url, {}, cb)
  end)
  assert(not err and #page.books == 2 and page.more, 'popular catalog')
  local book = page.books[1]
  assert(book.supported and not page.books[2].supported, 'copyright/format availability')
  assert(
    vim.deep_equal(book.authors, { 'A. Writer' }) and book.catalog_entry.title == book.title,
    'catalog metadata and raw entry retained'
  )
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
  err, page = call(function(cb)
    provider.browse.explore(nil, cb)
  end)
  assert(not err, tostring(err))
  book = page.entries[1]
  local request_count = #requests
  vim.fn.executable = function(name)
    return name == 'pandoc' and 0 or executable(name)
  end
  err = call(function(cb)
    acquisition.acquire(home, provider, book, cb)
  end)
  vim.fn.executable = executable
  assert(
    err and err:find('requires Pandoc', 1, true) and #requests == request_count,
    'missing conversion tool must explain installation before downloading'
  )
  for _, failure in ipairs({ 'old-pandoc', 'broken-pandoc' }) do
    mode = failure
    err = call(function(cb)
      acquisition.acquire(home, provider, book, cb)
    end)
    assert(
      err and err:find('3.1.1', 1, true) and #requests == request_count,
      'unusable tools must fail before any download'
    )
  end
  mode, tool_check = 'hold-tool-check', nil
  delivered = false
  cancel = acquisition.acquire(home, provider, book, function()
    delivered = true
  end)
  wait_for(function()
    return tool_check ~= nil
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
      acquisition.acquire(home, provider, book, cb)
    end)
    assert(
      err and not vim.uv.fs_stat(home .. '/references/test-letters-gutenberg-11'),
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
    acquisition.acquire(home, provider, book, cb)
  end)
  vim.uv.fs_copyfile = copy
  assert(err and err:find('disk failure', 1, true), 'conversion/install disk failure')
  no_staging()

  mode = 'hold-conversion'
  delivered = false
  cancel = acquisition.acquire(root .. '/cancel-converter', provider, book, function()
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
      and not vim.uv.fs_stat(root .. '/cancel-converter/references/test-letters-gutenberg-11'),
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
    'Discover immediately opens Explore results'
  )
  keys(']')
  assert(table.concat(lines(), '\n'):find('Another page', 1, true), 'navigate additional results')
  assert(
    requests[#requests] == catalog.default_url .. '/books/?page=2',
    'never follow foreign pagination URL'
  )
  assert(
    table.concat(lines(), '\n'):find('Test Letters', 1, true),
    'load more retains earlier works'
  )
  keys('b')
  choose('Recently listed')
  assert(
    requests[#requests]:find('sort=descending', 1, true),
    'newest means descending catalog IDs'
  )
  keys('b')
  choose('Poetry')
  assert(requests[#requests]:find('topic=poetry', 1, true), 'poetry is a topic preset')
  keys('b')
  choose('Short stories')
  assert(
    requests[#requests]:find('topic=short%20stories', 1, true),
    'short stories is a topic preset'
  )
  keys('h')
  assert(
    table.concat(lines(), '\n'):find('Discover online', 1, true),
    'category changes keep a single browse layer above the library'
  )
  choose('Discover online')
  keys('s')
  api.nvim_buf_set_lines(0, 0, -1, false, { 'no such book' })
  keys('<CR>')
  assert(table.concat(lines(), '\n'):find('No matching works found', 1, true), 'empty search')
  keys('s')
  api.nvim_buf_set_lines(0, 0, -1, false, { 'cancelled' })
  keys('<Esc>')
  assert(
    table.concat(lines(), '\n'):find('No matching works found', 1, true),
    'search cancellation preserves browsing'
  )
  keys('s')
  api.nvim_buf_set_lines(0, 0, -1, false, { '' })
  keys('<CR>')
  assert(
    table.concat(lines(), '\n'):find('No matching works found', 1, true),
    'empty input preserves results'
  )
  keys('h')
  assert(
    table.concat(lines(), '\n'):find('Test Letters', 1, true),
    'empty query preserves the current results'
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
  local before_naming = #requests
  keys('a<Esc>')
  assert(
    #requests == before_naming and not vim.uv.fs_stat(home .. '/references'),
    'canceling a name does not download or install'
  )
  mode = 'network-error'
  local before_failure = #messages
  keys('a')
  api.nvim_buf_set_lines(0, 0, -1, false, { 'My Letters' })
  keys('<CR>')
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
  local installed = work.validate(home .. '/references/my-letters-gutenberg-11')
  assert(
    installed.source.id == '11' and installed.source.provider == 'gutenberg',
    'portable provenance'
  )
  assert(
    read_binary(installed.root .. '/SOURCE.epub') == fixture,
    'original and license retained verbatim'
  )
  local metadata = installed.manifest
  local snapshot = vim.json.decode(read_binary(installed.root .. '/SOURCE.json'))
  assert(
    metadata.title == book.title
      and metadata.authors[1] == 'A. Writer'
      and metadata.languages[1] == 'en',
    'acquired bibliographic metadata'
  )
  assert(
    metadata.source.file == 'SOURCE.epub'
      and metadata.preparation.plain_quotes
      and metadata.preparation.wrap_columns == 72,
    'actual source and preparation settings'
  )
  assert(
    snapshot.entry.id == 11 and snapshot.catalog_url == catalog.default_url .. '/books/11',
    'original catalog record provenance'
  )
  assert(
    read_binary(installed.root .. '/lilt.json'):find('\n  "', 1, true),
    'acquired manifest is readable JSON'
  )
  local original = table.concat(work.read(installed.units[2].reference), '\n')
  assert(
    original:find('"Café, 文学, and a rabbit 🐇,"', 1, true),
    'new English reading units use keyboard-friendly quotes'
  )
  for i, languages in ipairs({ { 'fr' }, { 'en', 'fr' }, {} }) do
    local other = vim.tbl_extend('force', book, { languages = languages })
    local language_error, reading = call(function(cb)
      acquisition.acquire(root .. '/original-punctuation-' .. i, provider, other, cb)
    end)
    assert(not language_error, tostring(language_error))
    assert(
      table.concat(work.read(reading.units[2].reference), '\n'):find('“Café', 1, true),
      'non-English, multilingual, and unknown-language works retain source punctuation'
    )
  end
  local path = home .. '/manuscripts/my-letters-gutenberg-11/002.txt'
  choose('The letter — 第一封信')
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
  choose('The letter — 第一封信')
  assert(
    api.nvim_get_current_buf() == manuscript and lines()[1] == 'A saved line.',
    'resume acquired work'
  )
  lilt.close()
  mode = 'changed-metadata'
  local saved_metadata = read_binary(installed.root .. '/lilt.json')
  lilt.open()
  keys('d')
  wait_for(function()
    return table.concat(lines(), '\n'):find('Catalog title changed', 1, true) ~= nil
  end, 'changed catalog metadata did not load')
  choose('Catalog title changed')
  local live_details = table.concat(lines(), '\n')
  assert(
    live_details:find('Current online catalog metadata', 1, true)
      and live_details:find('New catalog translator', 1, true),
    'online information describes the current catalog'
  )
  assert(
    live_details:find('Library copy keeps its saved metadata', 1, true),
    'existing-copy context'
  )
  assert(
    vim.inspect(api.nvim_win_get_config(0).footer):find('o Open library copy', 1, true),
    'existing online copy advertises the actual Open action'
  )
  keys('o')
  local info_request_count = #requests
  keys('i')
  local saved_details = table.concat(lines(), '\n')
  assert(
    saved_details:find('Saved local metadata', 1, true)
      and saved_details:find('Test Letters', 1, true)
      and not saved_details:find('New catalog translator', 1, true),
    'local information uses the acquisition manifest, not current online metadata'
  )
  assert(
    #requests == info_request_count and saved_details:find('Saved catalog file:', 1, true),
    'acquired information is offline and retains access to the fuller snapshot'
  )
  assert(
    read_binary(installed.root .. '/lilt.json') == saved_metadata,
    'viewing local information leaves the acquisition snapshot unchanged'
  )
  keys('q')
  mode = 'ok'
  -- Model a copy acquired before quote simplification, with saved writing.
  original = '“An earlier reading copy.”'
  vim.fn.writefile({ original }, installed.units[2].reference)
  local count = #requests
  vim.fn.executable = function()
    return 0
  end
  err, installed = call(function(cb)
    acquisition.acquire(
      home,
      provider,
      vim.tbl_extend('force', book, { title = 'Catalog title changed' }),
      cb
    )
  end)
  vim.fn.executable = executable
  assert(
    not err and installed.name == 'my-letters-gutenberg-11' and #requests == count,
    'duplicates reuse stable copy without a download'
  )
  assert(
    table.concat(work.read(installed.units[2].reference), '\n') == original,
    'duplicate acquisition cannot change references'
  )
  assert(vim.fn.readfile(path)[1] == 'A saved line.', 'acquisition cannot overwrite manuscripts')
  local collision = root .. '/collision'
  vim.fn.mkdir(collision .. '/manuscripts/test-letters-gutenberg-11', 'p')
  err = call(function(cb)
    acquisition.acquire(collision, provider, book, cb)
  end)
  assert(err and #requests == count, 'orphan manuscripts block acquisition before downloading')
  require('lilt.library').add(collision, 'examples/tyger')
  assert(
    work.validate(collision .. '/references/tyger').title,
    'existing local work remains compatible'
  )
  vim.fn.mkdir(root .. '/local/test-letters-gutenberg-11', 'p')
  vim.fn.writefile({ 'Local reference' }, root .. '/local/test-letters-gutenberg-11/text.txt')
  local local_manifest = {
    title = 'Unrelated local work',
    units = { { title = 'Text', path = 'text.txt' } },
  }
  vim.fn.writefile(
    { vim.json.encode(local_manifest) },
    root .. '/local/test-letters-gutenberg-11/lilt.json'
  )
  require('lilt.library').add(root .. '/local-library', root .. '/local/test-letters-gutenberg-11')
  err = call(function(cb)
    acquisition.acquire(root .. '/local-library', provider, book, cb)
  end)
  assert(err and #requests == count, 'same-name local work cannot be mistaken for a duplicate')
  assert(
    vim.fn.readfile(root .. '/local-library/references/test-letters-gutenberg-11/text.txt')[1]
      == 'Local reference',
    'local reference unchanged'
  )

  lilt.open()
  choose('Discover online')
  choose('Load more')
  choose('Another page')
  held = true
  choose('Add to library')
  keys('<CR>')
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
    job.killed and not vim.uv.fs_stat(home .. '/references/another-page-gutenberg-13'),
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
    choose('Load more')
    choose('Another page')
    held = true
    choose('Add to library')
    keys('<CR>')
    job = jobs[#jobs]
    local notifications = #messages
    job.finish() -- Success is queued before the user dismisses the picker.
    dismiss()
    vim.wait(20, function()
      return false
    end)
    assert(
      job.killed and not vim.uv.fs_stat(home .. '/references/another-page-gutenberg-13'),
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
    keys('a<CR>')
    job = jobs[#jobs]
    keys(quit)
    job.finish()
    vim.wait(20, function()
      return false
    end)
    assert(
      job.killed
        and not vim.uv.fs_stat(home .. '/references/another-page-gutenberg-13')
        and not pcall(api.nvim_get_autocmds, { group = 'LiltPicker' }),
      'quit from acquiring details cancels the download and closes every page'
    )
    held = false
  end

  held = true
  lilt.open()
  choose('Discover online')
  job = jobs[#jobs]
  keys('s')
  api.nvim_buf_set_lines(0, 0, -1, false, { 'query in progress' })
  job.finish()
  vim.wait(20, function()
    return false
  end)
  assert(lines()[1] == 'query in progress', 'catalog completion preserves the search editor')
  keys('<Esc>')
  assert(
    table.concat(lines(), '\n'):find('Test Letters', 1, true),
    'cancelled input reveals results completed behind the editor'
  )
  keys('b')
  choose('Recently listed')
  local stale = jobs[#jobs]
  keys('b')
  choose('Poetry')
  job = jobs[#jobs]
  stale.finish()
  vim.wait(20, function()
    return false
  end)
  assert(
    stale.killed
      and vim.inspect(api.nvim_win_get_config(0).footer):find('Loading…', 1, true)
      and not table.concat(lines(), '\n'):find('Test Letters', 1, true),
    'late results cannot replace a newer pending catalog query'
  )
  job.finish()
  wait_for(function()
    return table.concat(lines(), '\n'):find('Test Letters', 1, true) ~= nil
  end)
  keys('hq')
  held = false

  -- Retry and close are real picker transitions, including a late download.
  mode = 'network-error'
  lilt.open()
  choose('Discover online')
  assert(
    table.concat(lines(), '\n'):find('Retry failed', 1, true),
    'recoverable network error page'
  )
  mode = 'ok'
  keys('r')
  assert(table.concat(lines(), '\n'):find('Test Letters', 1, true), 'retry succeeds')
  keys('hq')
  held = true
  lilt.open()
  choose('Discover online')
  assert(
    vim.inspect(api.nvim_win_get_config(0).footer):find('Loading…', 1, true),
    'nonblocking progress'
  )
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
  discovery_navigation()
  unified_discovery(lilt)
  print('Lilt online: catalog, cancellation, fidelity, installation and discover-to-reading passed')
end
local ok, err = xpcall(run, debug.traceback)
vim.system, vim.notify = system, notify
registry.list = registry_list
pcall(require('lilt').close)
vim.fn.delete(root, 'rf')
if not ok then
  io.write(err .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
