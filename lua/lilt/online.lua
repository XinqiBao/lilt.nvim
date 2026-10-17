local work = require('lilt.work')
local library = require('lilt.library')
local M = {}
M.default_catalog = 'https://gutendex.com'
local mirror = 'https://gutenberg.pglaf.org/cache/epub/'
local limit = 12 * 1024 * 1024

local function fail(message)
  error('Lilt: ' .. message, 0)
end

local function checked(value, err)
  if not value then
    fail(tostring(err))
  end
  return value
end

local function clean(value)
  return type(value) == 'string' and vim.trim(value:gsub('%c', ' ')) or ''
end

local function strings(value)
  local result = {}
  if type(value) == 'table' and vim.islist(value) then
    for _, item in ipairs(value) do
      if clean(item) ~= '' then
        result[#result + 1] = clean(item)
      end
    end
  end
  return result
end

local function encode(value)
  return (
    value:gsub('[^%w%-._~]', function(char)
      return string.format('%%%02X', char:byte())
    end)
  )
end

-- One bounded request, with an owned temporary file. All completions run on the
-- main loop; cancellation suppresses delivery even if the process already exited.
local function request(url, callback)
  local path, process, cancelled = vim.fn.tempname(), nil, false
  local function cleanup()
    vim.fn.delete(path)
  end
  local cancel = function()
    cancelled = true
    if process then
      process:kill(15)
    end
    cleanup()
  end
  local ok, err = pcall(function()
    if vim.fn.executable('curl') ~= 1 then
      fail('online discovery requires curl on PATH')
    end
    process = vim.system({
      'curl',
      '--disable',
      '--fail',
      '--silent',
      '--show-error',
      '--location',
      '--proto',
      '=https',
      '--proto-redir',
      '=https',
      '--max-redirs',
      '3',
      '--connect-timeout',
      '10',
      '--max-time',
      '45',
      '--max-filesize',
      tostring(limit),
      '--user-agent',
      'lilt.nvim (https://github.com/XinqiBao/lilt.nvim)',
      '--output',
      path,
      '--url',
      url,
    }, {}, function(result)
      vim.schedule(function()
        if cancelled then
          cleanup()
          return
        end
        if result.code ~= 0 then
          cleanup()
          callback('Lilt: online request failed: ' .. clean(result.stderr), nil)
          return
        end
        local stat = vim.uv.fs_stat(path)
        if not stat or stat.size > limit then
          cleanup()
          callback('Lilt: online response is missing or exceeds 12 MiB', nil)
          return
        end
        -- The consumer must read the file before returning.
        local delivered, delivery_error = pcall(callback, nil, path)
        cleanup()
        if not delivered then
          vim.notify(tostring(delivery_error), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
  if not ok then
    cleanup()
    vim.schedule(function()
      if not cancelled then
        callback(tostring(err), nil)
      end
    end)
  end
  return cancel
end

function M.catalog(base, query, callback)
  local parameters = {}
  for _, key in ipairs({ 'search', 'topic', 'sort', 'page' }) do
    if query[key] and tostring(query[key]) ~= '' then
      parameters[#parameters + 1] = key .. '=' .. encode(tostring(query[key]))
    end
  end
  local url = base
    .. '/books/'
    .. (#parameters > 0 and ('?' .. table.concat(parameters, '&')) or '')
  return request(url, function(err, path)
    if err then
      callback(err)
      return
    end
    local ok, result = pcall(function()
      local data = vim.json.decode(table.concat(work.read(path), '\n'))
      if
        type(data) ~= 'table'
        or type(data.results) ~= 'table'
        or not vim.islist(data.results)
        or type(data.count) ~= 'number'
      then
        fail('invalid catalog response')
      end
      local books = {}
      for _, entry in ipairs(data.results) do
        if
          type(entry) ~= 'table'
          or type(entry.id) ~= 'number'
          or entry.id < 1
          or entry.id >= 1000000000
          or entry.id % 1 ~= 0
          or clean(entry.title) == ''
        then
          fail('invalid book metadata in catalog response')
        end
        local authors = {}
        for _, author in ipairs(type(entry.authors) == 'table' and entry.authors or {}) do
          if type(author) == 'table' and clean(author.name) ~= '' then
            authors[#authors + 1] = clean(author.name)
          end
        end
        local formats = type(entry.formats) == 'table' and entry.formats or {}
        local plain = false
        for mime in pairs(formats) do
          if
            mime == 'text/plain'
            or mime == 'text/plain; charset=utf-8'
            or mime == 'text/plain; charset=us-ascii'
          then
            plain = true
          end
        end
        books[#books + 1] = {
          id = entry.id,
          title = clean(entry.title),
          author = table.concat(authors, '; '),
          languages = strings(entry.languages),
          subjects = strings(entry.subjects),
          supported = plain and entry.copyright == false and entry.media_type == 'Text',
        }
      end
      return { books = books, count = data.count, more = type(data.next) == 'string' }
    end)
    if ok then
      callback(nil, result)
    else
      callback(tostring(result))
    end
  end)
end

function M.name(book)
  return 'gutenberg-' .. book.id
end
function M.url(book)
  return 'https://www.gutenberg.org/ebooks/' .. book.id
end

-- Never refresh a reference beneath an existing manuscript, even if the source
-- edition has changed. Only a matching portable provenance record permits reuse.
function M.existing(root, book)
  local name = M.name(book)
  local path = root .. '/references/' .. name
  local stat = vim.uv.fs_lstat(path)
  if stat then
    if stat.type ~= 'directory' then
      fail('work name already exists: ' .. name)
    end
    local reading = work.load(path)
    if
      not reading.source
      or reading.source.provider ~= 'Project Gutenberg'
      or reading.source.id ~= tostring(book.id)
    then
      fail('work name already exists: ' .. name)
    end
    reading.name = name
    return reading
  end
  if vim.uv.fs_lstat(root .. '/manuscripts/' .. name) then
    fail('manuscript name already exists: ' .. name)
  end
end

function M.acquire(root, book, callback)
  local existing_ok, existing = pcall(M.existing, root, book)
  if not existing_ok or existing then
    local cancelled = false
    vim.schedule(function()
      if not cancelled then
        if existing_ok then
          callback(nil, existing)
        else
          callback(tostring(existing))
        end
      end
    end)
    return function()
      cancelled = true
    end
  end
  if not book.supported then
    local cancelled = false
    vim.schedule(function()
      if not cancelled then
        callback('Lilt: this work has no supported public-domain plain text')
      end
    end)
    return function()
      cancelled = true
    end
  end
  local url = mirror .. book.id .. '/pg' .. book.id .. '.txt'
  return request(url, function(err, path)
    if err then
      callback(err)
      return
    end
    local staging = vim.fn.tempname()
    local ok, result = pcall(function()
      local preserve_lines = false
      for _, subject in ipairs(book.subjects) do
        local lower = subject:lower()
        if
          lower:find('poet', 1, true)
          or lower:find('poems', 1, true)
          or lower:find('drama', 1, true)
          or lower:find('verse', 1, true)
          or lower:find('plays', 1, true)
        then
          preserve_lines = true
        end
      end
      local prepared =
        require('lilt.gutenberg').prepare(work.read(path), book.title, preserve_lines)
      local directory = staging .. '/' .. M.name(book)
      checked(vim.fn.mkdir(directory, 'p') == 1, 'cannot create acquisition staging directory')
      local manifest = {
        title = book.title,
        author = book.author ~= '' and book.author or nil,
        source = { provider = 'Project Gutenberg', id = tostring(book.id), url = M.url(book) },
        units = {},
      }
      for i, unit in ipairs(prepared) do
        local filename = string.format('%03d.txt', i)
        checked(
          vim.fn.writefile(unit.lines, directory .. '/' .. filename) == 0,
          'cannot write unit'
        )
        manifest.units[i] = { title = unit.title, path = filename }
      end
      checked(vim.uv.fs_copyfile(path, directory .. '/SOURCE.txt', { excl = true }))
      checked(vim.fn.writefile({
        book.title,
        book.author,
        '',
        'Source: Project Gutenberg #' .. book.id,
        M.url(book),
        'Downloaded from: ' .. url,
        '',
        'SOURCE.txt is the unmodified download, including credits and the Gutenberg license.',
        'Reading units omit the distribution header/footer and blank padding at unit edges.',
        preserve_lines
            and 'Source line breaks and indentation are preserved (cataloged poetry/drama).'
          or 'Source layout is retained; unindented prose lines over 80 columns wrap at 72.',
        'Headings and paragraph breaks divide long sections into reading units.',
        '',
        'Public domain in the USA. Check the law in your country before use.',
      }, directory .. '/README.txt') == 0, 'cannot write attribution')
      checked(
        vim.fn.writefile({ vim.json.encode(manifest) }, directory .. '/lilt.json') == 0,
        'cannot write manifest'
      )
      return library.add(root, directory)
    end)
    if vim.uv.fs_lstat(staging) and vim.fn.delete(staging, 'rf') ~= 0 then
      vim.notify('Lilt: could not remove acquisition staging: ' .. staging, vim.log.levels.WARN)
    end
    if ok then
      callback(nil, result)
    else
      callback(tostring(result))
    end
  end)
end

return M
