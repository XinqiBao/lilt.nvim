-- Project Gutenberg acquisition produces ordinary local works.
local work = require('lilt.work')
local library = require('lilt.library')
local request = require('lilt.online.request')
local M = {}
local mirror = 'https://gutenberg.pglaf.org/cache/epub/'

local function fail(message)
  error('Lilt: ' .. message, 0)
end

local function checked(value, err)
  if not value then
    fail(tostring(err))
  end
  return value
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
      local plain_quotes = #book.languages == 1 and book.languages[1] == 'en'
      local prepared = require('lilt.online.gutenberg').prepare(work.read(path), book.title, {
        preserve_lines = preserve_lines,
        plain_quotes = plain_quotes,
      })
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
        plain_quotes
            and 'English curly quotation marks and apostrophes are converted to straight quotes.'
          or 'Source punctuation is preserved.',
        preserve_lines
            and 'Source line breaks and indentation are preserved (cataloged poetry/drama).'
          or 'Source layout is retained; unindented prose lines over 80 columns wrap at 72.',
        'Headings and paragraph breaks divide long sections into reading units.',
        '',
        'Public domain in the USA. Check the law in your country before use.',
        'Project Gutenberg is a registered trademark; Lilt is an independent client.',
        'Before sharing, retain SOURCE.txt and review the source license and trademark terms:',
        'https://www.gutenberg.org/policy/license.html',
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
