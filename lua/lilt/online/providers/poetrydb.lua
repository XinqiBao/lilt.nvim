local request = require('lilt.online.request')
local materialize = require('lilt.online.materialize')
local work = require('lilt.work')
local M = {
  id = 'poetrydb',
  name = 'PoetryDB',
  browse = {},
}
local base = 'https://poetrydb.org'
local fields = '/author,title,linecount'
local random_count = 20
local license = 'https://github.com/thundercomb/poetrydb/blob/main/DATA_LICENSE.md'
local rights = 'PoetryDB curated data: CC BY 4.0; primary poem texts: public domain (source claim).'

local function fail(message)
  error('Lilt: PoetryDB: ' .. message, 0)
end

local function title(value)
  return type(value) == 'string' and value:find('%S') and not value:find('%c')
end

local function encode(value)
  return (
    value:gsub('[^A-Za-z0-9%-._~]', function(char)
      return string.format('%%%02X', char:byte())
    end)
  )
end

local function deferred(err, callback)
  local cancelled = false
  vim.schedule(function()
    if not cancelled then
      callback(tostring(err))
    end
  end)
  return function()
    cancelled = true
  end
end

local function response(path)
  local data = vim.json.decode(table.concat(work.read(path), '\n'))
  if type(data) ~= 'table' then
    fail('invalid JSON response')
  end
  if data.status ~= nil then
    if data.status == 404 or data.status == '404' then
      return {}
    end
    if data.status == 413 or data.status == '413' then
      fail('too many matches; narrow your title or author search')
    end
    local reason = type(data.reason) == 'string' and vim.trim(data.reason:gsub('%c', ' '))
      or 'unknown API error'
    fail('API error: ' .. reason)
  end
  return data
end

local function records(data)
  if not vim.islist(data) then
    fail('expected an array of poems')
  end
  for _, record in ipairs(data) do
    if type(record) ~= 'table' or not title(record.title) or not title(record.author) then
      fail('invalid poem title or author')
    end
    local count = record.linecount
    if type(count) == 'string' and count:match('^%d+$') then
      count = tonumber(count)
    end
    if type(count) ~= 'number' or count < 0 or count > 9007199254740991 or count % 1 ~= 0 then
      fail('invalid poem linecount')
    end
  end
  return data
end

local function fetch(url, transform, callback)
  return request(url, function(err, path)
    if err then
      callback(err)
      return
    end
    local ok, result = pcall(function()
      return transform(response(path), path)
    end)
    if ok then
      callback(nil, result)
    else
      callback(tostring(result))
    end
  end)
end

local function lookup(author, poem_title)
  if author:find('[;/]') then
    fail('exact lookup is unsupported for this author name')
  end
  local term = encode(poem_title) .. ':abs'
  if poem_title:find('[;/]') then
    local fragment = ''
    for part in poem_title:gmatch('[^:;/]+') do
      part = vim.trim(part)
      if #part > #fragment then
        fragment = part
      end
    end
    if fragment == '' then
      fail('exact lookup is unsupported for this title')
    end
    -- The documented grammar cannot escape semicolons or route slashes.
    -- A fragment only locates candidates; acquisition verifies the exact pair.
    term = encode(fragment)
  end
  return base .. '/author,title/' .. encode(author) .. ':abs;' .. term
end

local function source(author, poem_title)
  -- Lengths count UTF-8 bytes, making the pair unambiguous without delimiters
  -- that could collide with author/title text. Keep the entire digest.
  local identity = #author .. ':' .. author .. #poem_title .. ':' .. poem_title
  local ok, url = pcall(lookup, author, poem_title)
  return {
    provider = M.id,
    id = vim.fn.sha256(identity),
    url = ok and url or base,
  },
    ok,
    url
end

local function browse(query, callback)
  local ok, url = pcall(function()
    if query.random then
      return base .. '/random/' .. random_count .. fields
    end
    if query.search ~= nil then
      -- Percent encoding does not hide API delimiters or terminal modifiers.
      if
        query.search:find('[;/]')
        or query.search:match(':abs$')
        or query.search:match(':word$')
      then
        fail('search cannot contain ";", "/", or end in an API modifier; try a shorter title')
      end
      return base .. '/author,title/' .. encode(query.search) .. fields
    end
    if query.author ~= nil then
      if not title(query.author) or query.author:find('[;/]') then
        fail('exact author browsing is unsupported for this name')
      end
      return base .. '/author/' .. encode(query.author) .. ':abs' .. fields
    end
    return base .. '/author'
  end)
  if not ok then
    return deferred(url, callback)
  end
  return fetch(url, function(data)
    local entries = {}
    if not query.random and query.search == nil and query.author == nil then
      local authors = data.authors
      if authors == nil and vim.islist(data) and #data == 0 then
        authors = {}
      end
      if type(authors) ~= 'table' or not vim.islist(authors) then
        fail('expected an author list')
      end
      local seen = {}
      for _, author in ipairs(authors) do
        if not title(author) then
          fail('invalid author name')
        end
        if not seen[author] then
          entries[#entries + 1] = {
            kind = 'group',
            id = author,
            label = author,
            query = { author = author },
          }
          seen[author] = true
        end
      end
    else
      local seen = {}
      local poems = records(data)
      if query.random and #poems > random_count then
        fail('random response exceeds requested batch size')
      end
      for _, record in ipairs(poems) do
        if query.author and record.author ~= query.author then
          fail('author response does not match the selected author')
        end
        local identity, supported, lookup_error = source(record.author, record.title)
        if not seen[identity.id] then
          entries[#entries + 1] = {
            kind = 'work',
            title = record.title,
            authors = { record.author },
            source = identity,
            supported = supported,
            availability = supported and 'Plain text · one poem' or tostring(lookup_error),
            rights = rights,
            rights_url = 'https://creativecommons.org/licenses/by/4.0/',
          }
          seen[identity.id] = true
        end
      end
    end
    return {
      title = query.random and 'Random poems'
        or query.search and ('Search: ' .. query.search)
        or query.author
        or 'Poets',
      entries = entries,
      -- Each continuation is a fresh sample, not an exhaustive catalog page.
      next = query.random and { random = true } or nil,
      empty = query.random and 'No poems returned in this random batch. Load more to try again.'
        or 'No poems or poets found. Try another title or author.',
    }
  end, callback)
end

function M.browse.explore(_, callback)
  return browse({ random = true }, callback)
end

M.browse.poetry = M.browse.explore

function M.browse.poets(_, callback)
  return browse({}, callback)
end

function M.search(text, _, callback)
  if not title(text) then
    return deferred('Lilt: PoetryDB: enter a title or author to search', callback)
  end
  return browse({ search = text }, callback)
end

function M.expand(query, callback)
  if not query.author then
    return deferred('Lilt: PoetryDB: missing selected author', callback)
  end
  return browse({ author = query.author }, callback)
end

function M.prepare(entry, directory, callback)
  local ok, url = pcall(function()
    if
      not title(entry.title)
      or type(entry.authors) ~= 'table'
      or #entry.authors ~= 1
      or not title(entry.authors[1])
    then
      fail('invalid selected poem')
    end
    local identity = source(entry.authors[1], entry.title)
    if not entry.source or not vim.deep_equal(identity, entry.source) then
      fail('selected poem identity has changed; browse again')
    end
    return lookup(entry.authors[1], entry.title)
  end)
  if not ok then
    return deferred(url, callback)
  end
  return fetch(url, function(data, path)
    local selected
    for _, record in ipairs(records(data)) do
      if record.author == entry.authors[1] and record.title == entry.title then
        if selected and not vim.deep_equal(selected, record) then
          fail('ambiguous poem: different records share this exact author and title')
        end
        selected = record
      end
    end
    if not selected then
      fail('the exact selected poem was not returned; browse again')
    end
    local prepared = materialize.text(selected.lines, directory, {
      title = selected.title,
      authors = { selected.author },
      source = vim.deepcopy(entry.source),
      rights = rights,
      rights_url = 'https://creativecommons.org/licenses/by/4.0/',
    })
    local copied, copy_error =
      vim.uv.fs_copyfile(path, directory .. '/SOURCE.poetrydb.json', { excl = true })
    if not copied then
      fail('cannot retain original JSON response: ' .. tostring(copy_error))
    end
    prepared.manifest.source.file = 'SOURCE.poetrydb.json'
    prepared.snapshot = { catalog_url = url, entry = selected }
    prepared.attribution = {
      'Poetry data from PoetryDB (https://poetrydb.org), curated by The Combed Thunderclap, licensed under CC BY 4.0.',
      'Curated edition and database: https://creativecommons.org/licenses/by/4.0/',
      'PoetryDB describes the primary poem texts as public domain.',
      'Data license: ' .. license,
      '',
      'SOURCE.poetrydb.json is the unmodified full API response to the selected request.',
      'SOURCE.json retains the selected record and its request URL, including source provenance when supplied.',
      'Reading text preserves the API lines, including indentation, blank rows, Unicode and punctuation.',
      'No reflow or quotation-mark normalization is applied. One poem is one reading unit.',
    }
    return prepared
  end, callback)
end

return M
