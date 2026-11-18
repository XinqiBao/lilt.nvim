-- Gutendex catalog queries and metadata validation; no literary text downloads.
local work = require('lilt.work')
local request = require('lilt.online.request')
local M = {}
M.default_url = 'https://gutendex.com'

local function fail(message)
  error('Lilt: ' .. message, 0)
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

local function people(value)
  local names = {}
  for _, person in ipairs(type(value) == 'table' and value or {}) do
    if type(person) == 'table' and clean(person.name) ~= '' then
      names[#names + 1] = clean(person.name)
    end
  end
  return names
end

local function encode(value)
  return (
    value:gsub('[^%w%-._~]', function(char)
      return string.format('%%%02X', char:byte())
    end)
  )
end

function M.fetch(base, query, callback)
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
        local authors = people(entry.authors)
        local formats = type(entry.formats) == 'table' and entry.formats or {}
        local epub = clean(formats['application/epub+zip']) ~= ''
        books[#books + 1] = {
          id = entry.id,
          title = clean(entry.title),
          author = table.concat(authors, '; '),
          authors = authors,
          translators = people(entry.translators),
          languages = strings(entry.languages),
          subjects = strings(entry.subjects),
          bookshelves = strings(entry.bookshelves),
          catalog_entry = entry,
          catalog_url = base .. '/books/' .. entry.id,
          supported = epub and entry.copyright == false and entry.media_type == 'Text',
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

return M
