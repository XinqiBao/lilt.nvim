local provider = require('lilt.online.providers.poetrydb')
local work = require('lilt.work')
local json = require('lilt.json')
local root = vim.fn.tempname()
local system = vim.system
local payload, held, network_error = '', false, false
local requests, jobs = {}, {}

local function bytes(path)
  local file = assert(io.open(path, 'rb'))
  local text = assert(file:read('*a'))
  file:close()
  return text
end

vim.system = function(args, _, callback)
  assert(args[1] == 'curl', 'native poems require no conversion subprocess')
  local path, url
  for i, arg in ipairs(args) do
    if arg == '--output' then
      path = args[i + 1]
    elseif arg == '--url' then
      url = args[i + 1]
    end
  end
  assert(path and url and vim.tbl_contains(args, '--max-filesize'), 'bounded request')
  requests[#requests + 1] = url
  local job = { path = path, body = payload, failed = network_error }
  function job:kill()
    self.killed = true
  end
  function job.finish()
    local file = assert(io.open(path, 'wb'))
    assert(file:write(job.body))
    file:close()
    callback({ code = job.failed and 22 or 0, stderr = 'HTTP 503' })
  end
  jobs[#jobs + 1] = job
  if not held then
    vim.schedule(job.finish)
  end
  return job
end

local function call(start)
  local result
  local starting = true
  local cancel = start(function(err, value)
    assert(not starting and not vim.in_fast_event(), 'callbacks run once on the main loop')
    assert(not result, 'callback delivered twice')
    result = { err = err, value = value }
  end)
  starting = false
  assert(type(cancel) == 'function', 'every operation returns cancellation')
  assert(
    vim.wait(2000, function()
      return result ~= nil
    end, 5),
    'async completion timed out'
  )
  return result.err, result.value
end

local function respond(data, start)
  payload = type(data) == 'string' and data or vim.json.encode(data)
  return call(start)
end

local function browse(category, cursor, data)
  return respond(data, function(cb)
    return provider.browse[category](cursor, cb)
  end)
end

local function search(text, data)
  return respond(data, function(cb)
    return provider.search(text, nil, cb)
  end)
end

local function expand(query, data)
  return respond(data, function(cb)
    return provider.expand(query, cb)
  end)
end

local function poem(poem_title, author)
  return {
    title = poem_title or 'A Small Poem',
    author = author or 'A. Poet',
    linecount = '2',
    lines = { '  “Love”—café\t ', '', '終わり', '' },
  }
end

local function entry(record)
  local err, page = search('Poem', { record })
  assert(not err, err)
  return page.entries[1]
end

local serial = 0
local function prepare(selected, data)
  serial = serial + 1
  local directory = root .. '/prepared-' .. serial
  payload = type(data) == 'string' and data or vim.json.encode(data)
  local err, prepared = call(function(cb)
    return provider.prepare(selected, directory, cb)
  end)
  return err, prepared, directory
end

local function run()
  vim.fn.mkdir(root, 'p')
  assert(
    provider.id == 'poetrydb' and provider.name == 'PoetryDB',
    'official provider name and identifier'
  )
  assert(
    require('lilt.online.providers').name(provider.id) == provider.name,
    'registered source is available to discovery and offline information'
  )
  assert(
    not provider.menu
      and vim.tbl_count(provider.browse) == 3
      and not provider.browse.recent
      and not provider.browse.short_stories,
    'only supported content categories are advertised'
  )
  local err, page = browse('poets', nil, { authors = { 'A. Poet', 'É. Author', 'A. Poet' } })
  assert(
    not err and #page.entries == 2 and not page.count and not page.next and not page.previous,
    'author groups without invented totals or pages'
  )
  assert(requests[#requests] == 'https://poetrydb.org/author', 'documented author list')
  assert(
    vim.deep_equal(page.entries[2], {
      kind = 'group',
      id = 'É. Author',
      label = 'É. Author',
      query = { author = 'É. Author' },
    }),
    'author group carries a data query'
  )
  local author_group = page.entries[2]
  err, page = browse('poets', nil, { authors = { 'É. Author', 'é. Author' } })
  assert(
    not err and page.entries[1].id == author_group.id and page.entries[2].id ~= author_group.id,
    'poet group identity survives reordering and preserves exact spelling'
  )

  local record = poem()
  err, page = expand({ author = record.author }, { record })
  assert(
    not err and page.title == record.author and #page.entries == 1,
    'selected author poem list'
  )
  assert(
    requests[#requests] == 'https://poetrydb.org/author/A.%20Poet:abs/author,title,linecount',
    'exact author metadata query'
  )
  local selected = page.entries[1]
  assert(
    selected.supported and selected.availability == 'Plain text · one poem',
    'native poem availability'
  )
  assert(
    #selected.source.id == 64 and selected.source.provider == 'poetrydb',
    'full source identity'
  )
  assert(
    selected.source.id == vim.fn.sha256('7:A. Poet12:A Small Poem'),
    'full length-prefixed identity'
  )
  assert(
    not selected.languages and not selected.description and not selected.publisher,
    'no inferred bibliography'
  )

  local metadata = vim.deepcopy(record)
  metadata.lines = nil
  for _, category in ipairs({ 'explore', 'poetry' }) do
    local before = #requests
    err, page = browse(category, nil, { metadata, metadata })
    assert(not err and #requests == before + 1, 'one random request per action')
    assert(
      requests[#requests] == 'https://poetrydb.org/random/20/author,title,linecount',
      'documented bounded random metadata query excludes poem bodies'
    )
    assert(
      #page.entries == 1 and vim.deep_equal(page.entries[1], selected),
      'random metadata deduplicates exact identities and preserves author-list work fields'
    )
    assert(
      page.next and not page.count and not page.previous and page.title == 'Random poems',
      'random batches offer another sample without exhaustive pagination or totals'
    )
    err, page = browse(category, vim.json.decode(vim.json.encode(page.next)), { metadata })
    assert(
      not err and page.next and #requests == before + 2,
      'opaque continuation repeats a bounded batch'
    )
    err, page = browse(category, page.next, {})
    assert(
      not err and #page.entries == 0 and page.empty and page.next,
      'an empty random sample can be retried by loading another batch'
    )
  end
  local oversized = {}
  for _ = 1, 21 do
    oversized[#oversized + 1] = metadata
  end
  err = browse('explore', nil, oversized)
  assert(
    err and err:find('batch size', 1, true),
    'oversized random responses fail before deduplication'
  )
  err = browse('poetry', nil, { authors = { record.author } })
  assert(err, 'random poem metadata cannot masquerade as an author list')

  local before_expansion = #requests
  err = expand({}, {})
  assert(err and #requests == before_expansion, 'expansion requires a selected author')

  err = expand({ author = 'Another Author' }, { record })
  assert(err and err:find('does not match', 1, true), 'author browsing verifies exact author')
  err, page = search('café & `x`', { record, record })
  assert(
    not err and #page.entries == 1,
    'duplicate metadata rows collapse without pretending text identity'
  )
  assert(
    requests[#requests]
      == 'https://poetrydb.org/author,title/caf%C3%A9%20%26%20%60x%60/author,title,linecount',
    'literal UTF-8 title/author search'
  )
  local left, right = entry(poem('bc', 'a')), entry(poem('c', 'ab'))
  assert(left.source.id ~= right.source.id, 'concatenation boundaries cannot alias identity')
  assert(
    entry(poem('A Small Poem', 'a. poet')).source.id ~= selected.source.id,
    'identity preserves case'
  )

  for _, status in ipairs({ 404, '404' }) do
    err, page = search('missing', { status = status, reason = 'Not found' })
    assert(not err and #page.entries == 0 and page.empty, 'HTTP-200 JSON404 is empty')
  end
  err, page = browse('poets', nil, { authors = {} })
  assert(not err and #page.entries == 0, 'empty author list')
  for _, status in ipairs({ 413, '413' }) do
    err = search('broad', { status = status, reason = 'too broad' })
    assert(err and err:find('narrow', 1, true), 'JSON413 asks for narrower input')
  end
  err = browse('poets', nil, { status = 405, reason = 'bad\nquery' })
  assert(err and err:find('API error: bad query', 1, true), 'source error reason is safe text')
  for _, data in ipairs({ '{bad', 'null', '{}', '{"authors":[null]}', '{"authors":["bad\\nname"]}' }) do
    err = browse('poets', nil, data)
    assert(err, 'invalid authors response is rejected')
  end
  for _, count in ipairs({ -1, 1.5, false, '', '2x', '1e2', '99999999999999999999' }) do
    local bad = poem()
    bad.linecount = count
    err = search('Poem', { bad })
    assert(err and err:find('linecount', 1, true), 'invalid literary counts are rejected')
  end
  err = search('Poem', { status = 200, reason = 'unexpected status object' })
  assert(err, 'a status object is not a result array')
  err = search('Poem', { title = 'not an array' })
  assert(err, 'object cannot masquerade as poem array')
  err = browse('poets', nil, '{"authors":["\255"]}')
  assert(err and err:find('UTF-8', 1, true), 'invalid response UTF-8 is rejected')
  network_error = true
  err = browse('poets', nil, { authors = {} })
  network_error = false
  assert(err and err:find('online request failed', 1, true), 'network errors propagate')

  for _, text in ipairs({ 'a;b', 'a/b', 'term:abs', 'term:word', '\n', '' }) do
    local before = #requests
    err = search(text, {})
    assert(err and #requests == before, 'unsupported syntax never turns into a different query')
  end
  local before_search = #requests
  err = search(nil, {})
  assert(err and #requests == before_search, 'missing search text cannot become an author browse')
  held = true
  local delivered = false
  local cancel = provider.browse.poets(nil, function()
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
    'cancelled browse cleans request'
  )
  cancel = provider.search('a;b', nil, function()
    delivered = true
  end)
  cancel()
  vim.wait(20, function()
    return false
  end)
  assert(not delivered, 'cancelled deferred validation suppresses delivery')
  held = false

  record.source = { name = 'Recorded source edition', url = 'https://example.org/edition' }
  local raw = '\n' .. json.encode({ poem('Nearby title'), record }) .. '\n  '
  local prepared, directory
  err, prepared, directory = prepare(selected, raw)
  assert(not err, err)
  assert(requests[#requests] == selected.source.url, 'request is tied to the selected identity')
  assert(
    prepared.manifest.source.file == 'SOURCE.poetrydb.json',
    'manifest points to native JSON archive'
  )
  assert(
    bytes(directory .. '/SOURCE.poetrydb.json') == raw,
    'original full response bytes retained'
  )
  assert(vim.deep_equal(prepared.snapshot, { catalog_url = selected.source.url, entry = record }))
  assert(
    not prepared.manifest.languages
      and not prepared.manifest.description
      and not prepared.manifest.publisher,
    'prepared metadata excludes inferred language, biography and publisher'
  )
  assert(prepared.manifest.rights:find('source claim', 1, true))
  assert(prepared.manifest.preparation.plain_quotes == false, 'no quotation normalization')
  json.write(directory .. '/lilt.json', prepared.manifest)
  local reading = work.validate(directory)
  assert(#reading.units == 1, 'one poem is one unit')
  assert(
    vim.deep_equal(work.read_unit(reading, reading.units[1]), record.lines),
    'every row survives exact readback'
  )
  assert(
    bytes(reading.units[1].reference) == table.concat(record.lines, '\n') .. '\n',
    'reference bytes remain exact'
  )
  assert(
    work.count_lines(reading.units[1].reference) == 4,
    'physical rows include blanks, unlike literary count'
  )
  local credit = table.concat(prepared.attribution, '\n')
  assert(
    credit:find('CC BY 4.0', 1, true)
      and credit:find('primary poem texts as public domain', 1, true),
    'attribution distinguishes curated data from primary texts'
  )
  assert(
    credit:find('DATA_LICENSE.md', 1, true) and credit:find('SOURCE.poetrydb.json', 1, true),
    'offline attribution links source and license'
  )

  err, prepared = prepare(selected, { record, record })
  assert(not err and prepared, 'byte-equivalent repeated records can collapse')
  err, prepared = prepare(selected, { poem() })
  assert(
    not err and prepared.snapshot.entry.source == nil,
    'missing source provenance stays missing'
  )
  err = prepare(selected, { status = '413', reason = 'Too many matches' })
  assert(
    err and err:find('narrow', 1, true),
    'over-broad selected lookup is an error, not a truncated poem'
  )
  local changed = vim.deepcopy(record)
  changed.lines[1] = 'A different poem'
  err = prepare(selected, { record, changed })
  assert(err and err:find('ambiguous poem', 1, true), 'different texts with the same pair fail')
  changed = vim.deepcopy(record)
  changed.source.url = 'https://example.org/different-edition'
  err = prepare(selected, { record, changed })
  assert(
    err and err:find('ambiguous poem', 1, true),
    'different provenance with the same pair also fails'
  )
  err = prepare(selected, { poem('a small poem') })
  assert(err and err:find('exact selected poem', 1, true), 'nearby title is never substituted')
  err = prepare(selected, { poem(nil, 'Another Poet') })
  assert(err and err:find('exact selected poem', 1, true), 'another author cannot substitute')
  err = prepare(selected, { status = 404, reason = 'Not found' })
  assert(
    err and err:find('exact selected poem', 1, true),
    'empty acquisition is a failed selection'
  )
  local altered = vim.deepcopy(selected)
  altered.source.id = 'not-the-selected-identity'
  local before = #requests
  err = prepare(altered, { record })
  assert(err and #requests == before, 'modified identity is rejected before downloading')

  for _, lines in ipairs({
    { 'embedded\nnewline' },
    { 'embedded\rcarriage' },
    { 'nul\0byte' },
    { 42 },
    { '\239\187\191BOM' },
    vim.empty_dict(),
  }) do
    local bad = vim.deepcopy(record)
    bad.lines = lines
    err = prepare(selected, { bad })
    assert(err, 'unrepresentable source lines must fail instead of changing rows')
  end
  err = prepare(
    selected,
    '[{"title":"A Small Poem","author":"A. Poet","linecount":1,"lines":["\\ud800"]}]'
  )
  assert(err, 'invalid escaped Unicode must not become reference text')
  local incomplete = poem()
  incomplete.lines = nil
  err = prepare(selected, { incomplete })
  assert(err, 'full selected record must contain a lines array')

  for _, name in ipairs({ 'Sonnet 2: When forty winters', 'Part One; Part Two / Finale' }) do
    local special = poem(name)
    local chosen = entry(special)
    assert(chosen.supported, 'supported delimiter title')
    err, prepared = prepare(chosen, { poem('Nearby'), special })
    assert(not err and prepared.snapshot.entry.title == name, err)
    local url = requests[#requests]
    if name:find(';', 1, true) then
      assert(
        url:sub(-#';Part%20One') == ';Part%20One'
          and not url:find('%3B', 1, true)
          and not url:find('%2F', 1, true),
        'safe longest fragment lookup'
      )
    else
      assert(
        url:find('Sonnet%202%3A%20When%20forty%20winters:abs', 1, true),
        'colon title is encoded as data'
      )
    end
  end
  local unsupported = entry(poem(';/'))
  assert(not unsupported.supported, 'title without a safe fragment is honestly unavailable')
  before = #requests
  err = prepare(unsupported, { poem(';/') })
  assert(err and #requests == before, 'unsupported selected lookup is not requested')

  held = true
  payload = vim.json.encode({ record })
  directory = root .. '/cancelled'
  cancel = provider.prepare(selected, directory, function()
    delivered = true
  end)
  job = jobs[#jobs]
  cancel()
  job.finish()
  vim.wait(20, function()
    return false
  end)
  assert(
    job.killed and not delivered and not vim.uv.fs_stat(directory),
    'cancelled preparation writes no work'
  )
  held = false
  local acquisition = require('lilt.online.acquire')
  local library = require('lilt.library')
  local home = root .. '/library'
  local staging = {}
  local tracked = vim.tbl_extend('force', provider, {
    prepare = function(chosen, destination, cb)
      staging[#staging + 1] = vim.fn.fnamemodify(destination, ':h')
      return provider.prepare(chosen, destination, cb)
    end,
  })
  local function acquire(chosen, name)
    return call(function(cb)
      return acquisition.acquire(home, tracked, chosen, cb, name)
    end)
  end
  payload = raw
  local installed
  err, installed = acquire(selected, 'my-poem')
  assert(not err and installed.name == 'my-poem', err or 'shared installation uses personal name')
  assert(
    bytes(installed.root .. '/SOURCE.poetrydb.json') == raw,
    'installed JSON archive remains byte exact'
  )
  local snapshot = vim.json.decode(bytes(installed.root .. '/SOURCE.json'))
  assert(
    vim.deep_equal(snapshot.entry, record) and snapshot.catalog_url == selected.source.url,
    'installed envelope retains exact record and request'
  )
  assert(
    vim.deep_equal(work.read_unit(installed, installed.units[1]), record.lines),
    'shared validation/publication preserves every row'
  )
  assert(
    bytes(installed.root .. '/README.txt'):find('Poetry data from PoetryDB', 1, true),
    'installed attribution works offline'
  )
  local information =
    require('lilt.picker.information').items(installed.manifest, 'Saved local metadata')
  local labels = {}
  for _, item in ipairs(information) do
    labels[#labels + 1] = item.label
  end
  local offline = table.concat(labels, '\n')
  assert(
    offline:find('Rights (source claim)', 1, true) and offline:find('CC BY 4.0', 1, true),
    'offline work information preserves rights distinction'
  )
  assert(
    offline:find(selected.source.url, 1, true),
    'offline information retains actual source URL'
  )

  local manuscript = library.manuscript(home, installed, installed.units[1])
  vim.fn.mkdir(vim.fn.fnamemodify(manuscript, ':h'), 'p')
  assert(
    vim.fn.writefile({ record.lines[1] }, manuscript) == 0,
    'write temporary library manuscript'
  )
  assert(
    library.progress(home, installed, installed.units[1]) == 25,
    'progress counts four physical rows, not two literary lines'
  )
  before = #requests
  payload = vim.json.encode({ changed })
  local reused
  err, reused = acquire(selected)
  assert(
    not err and reused.name == installed.name and #requests == before,
    'existing pair opens saved copy without refetching'
  )
  assert(bytes(manuscript) == record.lines[1] .. '\n', 'saved manuscript survives source reuse')
  assert(
    bytes(installed.root .. '/SOURCE.poetrydb.json') == raw,
    'source reuse never refreshes reference data'
  )

  local bad = poem('Invalid new poem')
  local bad_entry = entry(bad)
  bad.lines = { 'bad\nrow' }
  payload = vim.json.encode({ bad })
  err = acquire(bad_entry)
  assert(err, 'invalid source text fails shared acquisition')
  assert(not acquisition.existing(home, bad_entry), 'failed text preparation is not published')

  local pending_record = poem('Cancelled new poem')
  local pending_entry = entry(pending_record)
  payload = vim.json.encode({ pending_record })
  held = true
  before = #jobs
  cancel = acquisition.acquire(home, tracked, pending_entry, function()
    delivered = true
  end)
  assert(
    vim.wait(2000, function()
      return #jobs > before
    end, 5),
    'shared acquisition starts selected request'
  )
  job = jobs[#jobs]
  cancel()
  job.finish()
  vim.wait(20, function()
    return false
  end)
  assert(
    job.killed and not delivered and not acquisition.existing(home, pending_entry),
    'shared cancellation leaves no installed poem'
  )
  held = false
  for _, path in ipairs(staging) do
    assert(
      not vim.uv.fs_stat(path),
      'shared acquisition staging leaked after completion/failure/cancel'
    )
  end
  assert(
    #work.discover(home .. '/references') == 1,
    'only the successfully acquired poem is discoverable'
  )
  for _, job_result in ipairs(jobs) do
    assert(not vim.uv.fs_stat(job_result.path), 'request temporary file leaked')
  end
end

local ok, err = xpcall(run, debug.traceback)
vim.system = system
vim.fn.delete(root, 'rf')
assert(ok, err)
print(
  'Lilt PoetryDB: documented browsing, exact identity, ambiguity, JSON retention and native text fidelity passed'
)
