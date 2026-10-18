-- Project Gutenberg acquisition produces ordinary local works.
local work = require('lilt.work')
local library = require('lilt.library')
local request = require('lilt.online.request')
local epub = require('lilt.import.epub')
local M = {}
local mirror = 'https://gutenberg.pglaf.org/cache/epub/'
local filter = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h:h:h')
  .. '/pandoc/gutenberg.lua'

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
        callback('Lilt: this work has no supported public-domain EPUB')
      end
    end)
    return function()
      cancelled = true
    end
  end
  local url = mirror .. book.id .. '/pg' .. book.id .. '.epub'
  local staging, cancel_step, cancelled = vim.fn.tempname(), nil, false
  local function cleanup()
    if vim.uv.fs_lstat(staging) and vim.fn.delete(staging, 'rf') ~= 0 then
      vim.notify('Lilt: could not remove acquisition staging: ' .. staging, vim.log.levels.WARN)
    end
  end
  local function finish(err, value)
    cleanup()
    if not cancelled then
      callback(err, value)
    end
  end
  cancel_step = epub.check(function(tool_error)
    if tool_error then
      finish(tool_error)
      return
    end
    cancel_step = request(url, function(err, path)
      if cancelled then
        return
      end
      if err then
        finish(err)
        return
      end
      local source = staging .. '/SOURCE.epub'
      local directory = staging .. '/' .. M.name(book)
      -- The request deletes its download when this callback returns. Keep an
      -- acquisition-owned input until conversion finishes; the converter only
      -- receives local paths and metadata, never a URL or library root.
      local copied, copy_error = pcall(function()
        checked(vim.fn.mkdir(staging, 'p') == 1, 'cannot create acquisition staging directory')
        checked(vim.uv.fs_copyfile(path, source, { excl = true }))
      end)
      if not copied then
        finish(tostring(copy_error))
        return
      end
      local plain_quotes = #book.languages == 1 and book.languages[1] == 'en'
      cancel_step = epub.prepare(source, directory, {
        title = book.title,
        author = book.author ~= '' and book.author or nil,
        source = { provider = 'Project Gutenberg', id = tostring(book.id), url = M.url(book) },
        plain_quotes = plain_quotes,
        filter = filter,
      }, function(prepare_error)
        if prepare_error then
          finish(prepare_error)
          return
        end
        local ok, result = pcall(function()
          checked(vim.uv.fs_rename(source, directory .. '/SOURCE.epub'))
          checked(vim.fn.writefile({
            book.title,
            book.author,
            '',
            'Source: Project Gutenberg #' .. book.id,
            M.url(book),
            'Downloaded from: ' .. url,
            '',
            'SOURCE.epub is the unmodified download, including original credits and license.',
            'Pandoc converts the EPUB reading order and headings to UTF-8 reading units.',
            'Distribution boilerplate and images are omitted from reading text.',
            'Prose wraps at 72 columns; explicit verse and preformatted line breaks are retained.',
            'Long sections divide at paragraph breaks. Titles come from structural headings.',
            plain_quotes
                and 'English curly quotation marks and apostrophes are converted to straight quotes.'
              or 'Source punctuation is preserved.',
            '',
            'Public domain in the USA. Check the law in your country before use.',
            'Project Gutenberg is a registered trademark; Lilt is an independent client.',
            'Before sharing, retain SOURCE.epub and review the source license and trademark terms:',
            'https://www.gutenberg.org/policy/license.html',
          }, directory .. '/README.txt') == 0, 'cannot write attribution')
          return library.add(root, directory)
        end)
        if ok then
          finish(nil, result)
        else
          finish(tostring(result))
        end
      end)
    end)
  end)
  return function()
    cancelled = true
    if cancel_step then
      cancel_step()
    end
    cleanup()
  end
end

return M
