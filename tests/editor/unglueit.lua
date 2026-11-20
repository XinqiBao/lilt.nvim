local provider = require('lilt.online.providers.unglueit')
local work = require('lilt.work')
local root = vim.fn.tempname()
local system = vim.system
local requests, jobs = {}, {}
local held, network_error = false, false
local function bytes(path)
  local file = assert(io.open(path, 'rb'))
  local text = assert(file:read('*a'))
  file:close()
  return text
end
local fixture = bytes('tests/fixtures/unglueit.opds')
local epub = bytes(assert(vim.env.LILT_TEST_EPUB, 'run through tests/run.py'))
local response = fixture
vim.system = function(args, opts, callback)
  if args[1] ~= 'curl' then
    return system(args, opts, callback)
  end
  local url, path
  for i, arg in ipairs(args) do
    if arg == '--url' then
      url = args[i + 1]
    elseif arg == '--output' then
      path = args[i + 1]
    end
  end
  assert(url and path and vim.tbl_contains(args, '=https'), 'bounded HTTPS request')
  requests[#requests + 1] = url
  local job = { path = path }
  jobs[#jobs + 1] = job
  function job:kill()
    self.killed = true
  end
  function job.finish()
    local file = assert(io.open(path, 'wb'))
    file:write(url:find('/download_ebook/', 1, true) and epub or response)
    file:close()
    callback({ code = network_error and 22 or 0, stderr = 'HTTP 503' })
  end
  if not held then
    vim.schedule(job.finish)
  end
  return job
end

local function call(start)
  local result
  start(function(err, value)
    assert(not result, 'callback delivered more than once')
    result = { err = err, value = value }
  end)
  assert(
    vim.wait(5000, function()
      return result ~= nil
    end, 5),
    'operation timed out'
  )
  return result.err, result.value
end
local function browse(query)
  return call(function(callback)
    return provider.browse(query or provider.menu[1].query, callback)
  end)
end
local function rejected(text, message)
  response = text
  local err = browse()
  assert(err, message)
end
local function run()
  vim.fn.mkdir(root, 'p')
  local registered = false
  for _, source in ipairs(require('lilt.online.providers').list()) do
    registered = registered or source == provider
  end
  assert(registered, 'Unglue.it is registered for source selection')
  local err, page = browse()
  assert(not err, tostring(err))
  assert(
    requests[1] == 'https://unglue.it/api/opds/epub/?order_by=popular' and #provider.menu == 2,
    'browse uses published popular/new EPUB feeds, without a Gutenberg exclusion or title search'
  )
  assert(#page.entries == 2 and not page.count, 'lists only eligible explicit English copies')
  assert(
    page.title == 'Popular EPUBs · page 1 · 2 eligible English works / 5 source records',
    'mixed page counts works/groups once, independently of acquisition copy totals'
  )
  local continuation = page.next
  local group, single = unpack(page.entries)
  assert(group.kind == 'group' and group.label:find('2 EPUB copies', 1, true), 'copy choice group')
  assert(
    group.label:find('A. Writer; B. Contributor', 1, true),
    'copy group identifies source authors'
  )
  assert(single.kind == 'work' and single.source.id == '43-105', 'single eligible copy is direct')
  assert(
    not single.label and single.authors[1] == 'C. Writer',
    'single work uses shared title/author label'
  )
  assert(single.languages[1] == 'en-GB', 'explicit English regional tag is retained')
  local query = vim.json.decode(vim.json.encode(group.query))
  local before = #requests
  err, page = browse(query)
  assert(not err and #requests == before, 'copy group opens the retained feed without refetching')
  local first, second = unpack(page.entries)
  assert(page.title == first.title .. ' · choose an EPUB copy', 'copy group heading is unchanged')
  assert(
    #page.entries == 2 and first.source.id == '42-101' and second.source.id == '42-102',
    'only eligible copies have distinct stable source identities'
  )
  assert(first.title == 'Letters & reply — é', 'XML basic and numeric entities decode')
  assert(first.label:find('copy 101', 1, true), 'copy selection label preserves the official title')
  assert(first.source.version == '0.2' and second.source.version == '0.1', 'supplied copy versions')
  assert(
    first.source.title == 'Illustrated copy' and not second.source.title,
    'only supplied nonempty acquisition titles are retained'
  )
  assert(
    vim.deep_equal(first.authors, { 'A. Writer', 'B. Contributor' })
      and first.subjects[1] == 'Letters',
    'all source authors, CDATA and categories survive normalization'
  )
  assert(
    first.availability:find('CC BY-NC-ND · version 0.2', 1, true)
      and first.availability:find('Illustrated copy · copy 101', 1, true)
      and second.availability:find('PD-US · version 0.1', 1, true),
    'copy details distinguish rights, supplied version/title and copy identity'
  )
  assert(
    not first.publisher and not first.published,
    'work-level date/publisher are not edition facts'
  )
  assert(first.opds.feed == fixture, 'entire original feed snapshot retained')
  assert(not page.next and not page.previous, 'copy choices do not inherit catalog pagination')

  response = fixture:gsub('\n', '\r\n')
  err, page = browse()
  assert(not err and page.entries[1].query.feed == response, 'snapshot retains original CRLF bytes')
  response = fixture:gsub('dc:rights="CC BY%-NC%-ND"', 'extra:rights="CC BY-NC-ND"')
  err, page = browse()
  assert(
    not err and page.entries[1].source.id == '42-102',
    'a rights attribute in another namespace does not establish eligibility'
  )

  response = fixture:gsub('xmlns:dc=', 'xmlns:terms='):gsub('dc:', 'terms:')
  err, page = browse()
  assert(not err and #page.entries == 2, 'namespace URI controls semantics, not prefix spelling')
  response = fixture
    :gsub('<dc:language>en</dc:language>', '<dc:language>fr</dc:language>')
    :gsub('<dc:language>en%-GB</dc:language>', '<dc:language>fr</dc:language>')
    :gsub('page=1', 'page=2')
  err, page = browse(continuation)
  assert(
    not err and #page.entries == 0 and page.next and page.empty:find('English', 1, true),
    'filtered empty pages explain eligibility and retain the next page'
  )
  assert(
    page.title == 'Popular EPUBs · page 2 · 0 eligible English works / 5 source records'
      and not page.count,
    'advertised page=1 is readable page 2; filtered counts are local, not global totals'
  )
  response = '<feed xmlns="http://www.w3.org/2005/Atom"/>'
  err, page = browse(page.next)
  assert(
    not err and #page.entries == 0 and not page.next,
    'a genuinely empty last page is supported'
  )
  assert(
    page.title == 'Popular EPUBs · page 3 · 0 eligible English works / 0 source records'
      and requests[#requests]:find('&page=2', 1, true),
    'continued empty page follows actual next link and retains its page context'
  )
  response = fixture:gsub('order_by=popular', 'order_by=newest')
  err, page = browse(provider.menu[2].query)
  assert(not err and requests[#requests]:find('order_by=newest', 1, true), 'new EPUB browse')
  assert(
    page.title == 'New EPUBs · page 1 · 2 eligible English works / 5 source records',
    'newest page context'
  )

  rejected('<html><body>Service error</body></html>', 'HTML is not an OPDS feed')
  rejected('<feed xmlns="https://example.invalid"><entry/></feed>', 'wrong namespace rejected')
  rejected(fixture:gsub('</entry>', '</broken>', 1), 'unbalanced XML rejected')
  rejected('<!DOCTYPE feed SYSTEM "https://example.invalid/dtd">' .. fixture, 'DTD rejected')
  rejected(fixture:gsub('urn:ISBN:', '\0urn:ISBN:'), 'NUL metadata rejected')
  rejected(fixture:gsub('urn:ISBN:', '\255urn:ISBN:'), 'invalid UTF-8 rejected')
  rejected(fixture .. string.rep(' ', 4 * 1024 * 1024), 'oversized feed rejected')
  rejected(
    '<feed xmlns="http://www.w3.org/2005/Atom">'
      .. string.rep('<x>', 64)
      .. string.rep('</x>', 64)
      .. '</feed>',
    'deep XML rejected'
  )
  rejected(fixture:gsub('work/43/', 'work/42/'), 'duplicate work identity rejected')
  rejected(fixture:gsub('ebook/102/', 'ebook/101/'), 'conflicting copy identity rejected')
  rejected(
    fixture:gsub(
      'https://unglue.it/api/opds/epub/%?order_by=popular&amp;page=1',
      'https://example.invalid/feed'
    ),
    'cross-origin next link rejected'
  )
  local request_count = #requests
  err = browse({ url = 'https://unglue.it@evil.invalid/api/opds/epub/?order_by=popular' })
  assert(err and #requests == request_count, 'invalid query fails before requesting')

  response = fixture
  network_error = true
  err = browse()
  assert(err and err:find('503', 1, true), 'source failure is an error, not empty results')
  network_error = false
  held = true
  local delivered = false
  local cancel = provider.browse(provider.menu[1].query, function()
    delivered = true
  end)
  local job = jobs[#jobs]
  cancel()
  job.finish()
  vim.wait(20, function()
    return false
  end)
  assert(job.killed and not delivered and not vim.uv.fs_stat(job.path), 'cancelled request cleaned')
  held = false
  cancel = provider.browse(query, function()
    delivered = true
  end)
  cancel()
  vim.wait(20, function()
    return false
  end)
  assert(not delivered, 'scheduled copy choices respect cancellation')

  local tampered = vim.deepcopy(first)
  tampered.source.id = '42-103'
  err = call(function(callback)
    return provider.prepare(tampered, root .. '/unsupported', callback)
  end)
  assert(err and not vim.uv.fs_stat(root .. '/unsupported'), 'unknown-rights copy cannot prepare')

  held = true
  delivered = false
  local request_before = #requests
  cancel = provider.prepare(first, root .. '/cancelled', function()
    delivered = true
  end)
  assert(
    vim.wait(2000, function()
      return #requests > request_before
    end, 5),
    'preparation did not reach download'
  )
  job = jobs[#jobs]
  cancel()
  job.finish()
  vim.wait(20, function()
    return false
  end)
  assert(
    job.killed and not delivered and not vim.uv.fs_stat(root .. '/cancelled'),
    'preparation cancellation suppresses conversion and callback'
  )
  held = false
  local archive = epub
  epub = '<html>A failed download</html>'
  err = call(function(callback)
    return provider.prepare(first, root .. '/bad-archive', callback)
  end)
  assert(
    err and not vim.uv.fs_stat(root .. '/bad-archive'),
    'invalid EPUB fails without prepared work'
  )
  epub = archive

  local prepared
  err, prepared = call(function(callback)
    return provider.prepare(first, root .. '/prepared', callback)
  end)
  assert(not err, tostring(err))
  assert(
    requests[#requests] == 'https://unglue.it/download_ebook/101/?feed=opds',
    'advertised download'
  )
  assert(bytes(root .. '/prepared/SOURCE.epub') == epub, 'original EPUB bytes unchanged')
  assert(
    bytes(root .. '/prepared/SOURCE.opds') == fixture,
    'raw OPDS including unknown fields unchanged'
  )
  assert(prepared.manifest.source.file == 'SOURCE.epub', 'manifest identifies original archive')
  assert(
    prepared.manifest.rights == 'CC BY-NC-ND' and prepared.manifest.source.id == '42-101',
    'preparation pins the exact selected copy and its rights'
  )
  assert(
    prepared.manifest.source.version == '0.2',
    'offline source retains the supplied copy version'
  )
  assert(
    prepared.manifest.source.title == 'Illustrated copy',
    'offline source retains the advertised copy title'
  )
  assert(prepared.manifest.preparation.plain_quotes == false, 'source punctuation policy')
  assert(prepared.snapshot.catalog_url == requests[1], 'catalog provenance')
  assert(
    prepared.snapshot.entry.acquisition.attributes['https://example.invalid/metadata:credit']
      == 'A source-specific credit',
    'selected link attributes are retained without guessing edition facts'
  )
  local contents = {}
  for _, unit in ipairs(prepared.manifest.units) do
    vim.list_extend(contents, work.read(root .. '/prepared/' .. unit.path))
  end
  contents = table.concat(contents, '\n')
  assert(
    contents:find('distribution header', 1, true)
      and contents:find('Full distribution license', 1, true)
      and contents:find('“Café, 文学, and a rabbit 🐇,”', 1, true),
    'no Gutenberg cleanup or quote normalization in Unglue.it conversion'
  )
  assert(
    table.concat(prepared.attribution, '\n'):find('CC BY-NC-ND', 1, true),
    'readable copy rights'
  )
  local acquisition = require('lilt.online.acquire')
  local library = root .. '/library'
  local installed
  err, installed = call(function(callback)
    return acquisition.acquire(library, provider, first, callback, 'chosen-copy')
  end)
  assert(not err, tostring(err))
  assert(installed.name == 'chosen-copy' and installed.source.id == '42-101', 'install chosen copy')
  local offline = work.validate(installed.root)
  assert(
    offline.source.version == '0.2'
      and offline.source.title == 'Illustrated copy'
      and offline.manifest.rights == 'CC BY-NC-ND',
    'offline manifest preserves selected copy title, version and rights'
  )
  assert(bytes(installed.root .. '/SOURCE.opds') == fixture, 'installation retains complete feed')
  local snapshot = vim.json.decode(bytes(installed.root .. '/SOURCE.json'))
  assert(
    snapshot.entry.work_id == 'https://unglue.it/api/id/work/42/'
      and snapshot.entry.acquisition.href == 'https://unglue.it/download_ebook/101/?feed=opds',
    'installed snapshot identifies the selected work and actual advertised acquisition'
  )
  assert(
    bytes(installed.root .. '/README.txt'):find(
      'Source rights claim for this copy: CC BY-NC-ND',
      1,
      true
    ),
    'installed attribution is available offline'
  )
  request_count = #requests
  err, installed = call(function(callback)
    return acquisition.acquire(library, provider, first, callback)
  end)
  assert(
    not err and installed.name == 'chosen-copy' and #requests == request_count,
    'offline copy reuse'
  )
  err, installed = call(function(callback)
    return acquisition.acquire(library, provider, second, callback, 'other-copy')
  end)
  assert(
    not err and installed.source.id == '42-102' and installed.source.version == '0.1',
    'a distinct eligible copy installs independently with its own source version'
  )
  assert(
    bytes(library .. '/references/chosen-copy/SOURCE.epub') == epub,
    'first copy remains intact'
  )
  print(
    'Lilt Unglue.it: OPDS eligibility, edition groups, identity, provenance and conversion passed'
  )
end

local ok, err = xpcall(run, debug.traceback)
vim.system = system
vim.fn.delete(root, 'rf')
if not ok then
  io.write(err .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
