-- Unglue.it's published OPDS EPUB lists. Each installed identity pins a copy.
local xml = require('lilt.xml')
local request = require('lilt.online.request')
local work = require('lilt.work')
local M = {
  id = 'unglueit',
  name = 'Unglue.it',
  menu = {
    { label = 'Popular EPUBs', query = { order = 'popular' } },
    { label = 'New EPUBs', query = { order = 'newest' } },
  },
}
local atom = 'http://www.w3.org/2005/Atom'
local dc = 'http://purl.org/dc/terms/'
local opds = 'http://opds-spec.org/'
local schema = 'http://schema.org/'
local base = 'https://unglue.it/api/opds/epub/'
local orders = { popular = 'Popular EPUBs', newest = 'New EPUBs' }
local rights = {
  ['PD-US'] = true,
  ['CC0'] = true,
  ['CC BY'] = true,
  ['CC BY-SA'] = true,
  ['CC BY-NC'] = true,
  ['CC BY-ND'] = true,
  ['CC BY-NC-SA'] = true,
  ['CC BY-NC-ND'] = true,
}

local function fail(message)
  error('Lilt: Unglue.it: ' .. message, 0)
end

local function clean(value)
  return type(value) == 'string' and vim.trim(value:gsub('%c', ' ')) or ''
end

local function child_text(node, name, namespace)
  local child = xml.children(node, name, namespace)[1]
  return child and clean(xml.text(child)) or ''
end

local function feed_order(url)
  if type(url) ~= 'string' then
    fail('invalid feed URL')
  end
  local order = url:match('^https://unglue%.it/api/opds/epub/%?order_by=(%a+)$')
    or url:match('^https://unglue%.it/api/opds/epub/%?order_by=(%a+)&page=%d+$')
  if not orders[order] then
    fail('unsupported feed URL')
  end
  return order
end

local function english(languages)
  if #languages == 0 then
    return false
  end
  for _, language in ipairs(languages) do
    local tag = language:lower()
    if tag ~= 'en' and not tag:match('^en%-%w[%w%-]*$') then
      return false
    end
  end
  return true
end

local function parse(text, url, selected)
  local order = feed_order(url)
  if text:find('<!DOCTYPE', 1, true) or text:find('<!ENTITY', 1, true) then
    fail('XML declarations are unsupported')
  end
  local feed = xml.parse(text)
  if feed.name ~= 'feed' or feed.namespace ~= atom then
    fail('expected an Atom feed')
  end
  local entries, seen = {}, {}
  local found = false
  for _, node in ipairs(xml.children(feed, 'entry', atom)) do
    local title = child_text(node, 'title', atom)
    local id = child_text(node, 'id', atom)
    local number = id:match('^https://unglue%.it/api/id/work/([1-9]%d*)/$')
    if title == '' or not number or seen[id] then
      fail('invalid or duplicate work identity')
    end
    seen[id] = true
    local authors, languages, subjects = {}, {}, {}
    for _, author in ipairs(xml.children(node, 'author', atom)) do
      local name = child_text(author, 'name', atom)
      if name ~= '' then
        authors[#authors + 1] = name
      end
    end
    for _, language in ipairs(xml.children(node, 'language', dc)) do
      languages[#languages + 1] = clean(xml.text(language))
    end
    for _, category in ipairs(xml.children(node, 'category', atom)) do
      local term = clean(xml.attr(category, 'term'))
      if term ~= '' then
        subjects[#subjects + 1] = term
      end
    end
    local copies, acquisitions = {}, {}
    if english(languages) then
      for _, link in ipairs(xml.children(node, 'link', atom)) do
        local href = xml.attr(link, 'href') or ''
        local ebook = href:match('^https://unglue%.it/download_ebook/([1-9]%d*)/$')
          or href:match('^https://unglue%.it/download_ebook/([1-9]%d*)/%?feed=opds$')
        local license = xml.attr(link, 'rights', dc)
        if
          ebook
          and xml.attr(link, 'rel') == opds .. 'acquisition/open-access'
          and xml.attr(link, 'type') == 'application/epub+zip'
          and #xml.children(link, 'indirectAcquisition', opds) == 0
          and rights[license]
        then
          if acquisitions[ebook] and not vim.deep_equal(acquisitions[ebook], link) then
            fail('ambiguous EPUB copy ' .. ebook)
          end
          if not acquisitions[ebook] then
            acquisitions[ebook] = link
            local version = clean(xml.attr(link, 'version', schema))
            local label = 'EPUB · ' .. license
            if version ~= '' then
              label = label .. ' · version ' .. version
            end
            local link_title = clean(xml.attr(link, 'title'))
            if link_title ~= '' then
              label = label .. ' · ' .. link_title
            end
            copies[#copies + 1] = {
              kind = 'work',
              title = title,
              label = title .. ' · ' .. label .. ' · copy ' .. ebook,
              authors = authors,
              languages = languages,
              subjects = subjects,
              rights = license,
              source = {
                provider = M.id,
                id = number .. '-' .. ebook,
                url = id,
                version = version ~= '' and version or nil,
                title = link_title ~= '' and link_title or nil,
              },
              availability = label .. ' · copy ' .. ebook,
              supported = true,
              opds = {
                feed = text,
                catalog_url = url,
                work_id = id,
                acquisition = { href = href, attributes = link.attrs },
              },
            }
          end
        end
      end
    end
    if selected == id then
      entries, found = copies, true
    elseif not selected then
      if #copies == 1 then
        copies[1].label = nil -- The shared work label includes title and authors.
        entries[#entries + 1] = copies[1]
      elseif #copies > 1 then
        entries[#entries + 1] = {
          kind = 'group',
          label = title
            .. (#authors > 0 and (' — ' .. table.concat(authors, '; ')) or '')
            .. ' · '
            .. #copies
            .. ' EPUB copies',
          query = { feed = text, catalog_url = url, work_id = id },
        }
      end
    end
  end
  if selected and not found then
    fail('selected work is absent from the feed snapshot')
  end
  local page = {
    title = selected and child_text(feed, 'title', atom) or (orders[order] .. ' · English copies'),
    entries = entries,
    empty = 'No eligible English EPUB copies on this page. Only direct EPUBs with known rights are listed.',
  }
  if selected then
    for _, entry in ipairs(entries) do
      page.title = entry.title .. ' · choose an EPUB copy'
      break
    end
  else
    for _, link in ipairs(xml.children(feed, 'link', atom)) do
      local rel = xml.attr(link, 'rel')
      if rel == 'next' or rel == 'previous' then
        local href = xml.attr(link, 'href')
        if feed_order(href) ~= order then
          fail('continuation changed feed order')
        end
        if page[rel] then
          fail('ambiguous feed continuation')
        end
        page[rel] = { url = href }
      end
    end
  end
  return page
end

local function deferred(callback, action)
  local cancelled = false
  vim.schedule(function()
    if not cancelled then
      local ok, result = pcall(action)
      if ok then
        callback(nil, result)
      else
        callback(tostring(result))
      end
    end
  end)
  return function()
    cancelled = true
  end
end

function M.browse(query, callback)
  if query.work_id then
    return deferred(callback, function()
      return parse(query.feed, query.catalog_url, query.work_id)
    end)
  end
  local url = query.url or (base .. '?order_by=' .. (query.order or 'popular'))
  local ok, err = pcall(feed_order, url)
  if not ok then
    return deferred(callback, function()
      error(err, 0)
    end)
  end
  return request(url, function(request_error, path)
    if request_error then
      callback(request_error)
      return
    end
    local parsed, result = pcall(function()
      local stat = vim.uv.fs_stat(path)
      if not stat or stat.size > 4 * 1024 * 1024 then
        fail('feed exceeds 4 MiB')
      end
      work.read(path) -- Validate UTF-8 without changing the retained response bytes.
      local file = assert(io.open(path, 'rb'))
      local text = file:read('*a')
      file:close()
      return parse(text, url)
    end)
    if parsed then
      callback(nil, result)
    else
      callback(tostring(result))
    end
  end)
end

function M.prepare(entry, directory, callback)
  local ok, selected = pcall(function()
    if not entry.opds or not entry.source or entry.source.provider ~= M.id then
      fail('missing selected copy metadata')
    end
    local page = parse(entry.opds.feed, entry.opds.catalog_url, entry.opds.work_id)
    for _, copy in ipairs(page.entries) do
      if copy.source.id == entry.source.id and copy.source.url == entry.source.url then
        return copy
      end
    end
    fail('selected EPUB copy is absent or unsupported')
  end)
  if not ok then
    return deferred(callback, function()
      error(selected, 0)
    end)
  end
  local metadata = {
    title = selected.title,
    authors = selected.authors,
    languages = selected.languages,
    subjects = selected.subjects,
    rights = selected.rights,
    source = selected.source,
  }
  return require('lilt.online.materialize').epub(
    selected.opds.acquisition.href,
    directory,
    metadata,
    { plain_quotes = false },
    function(err, prepared)
      if err then
        callback(err)
        return
      end
      local saved, result = pcall(function()
        local file = assert(io.open(directory .. '/SOURCE.opds', 'wb'))
        local written, write_error = file:write(selected.opds.feed)
        local closed, close_error = file:close()
        assert(written and closed, write_error or close_error)
        prepared.snapshot = {
          catalog_url = selected.opds.catalog_url,
          feed_file = 'SOURCE.opds',
          source = selected.source,
          entry = {
            work_id = selected.opds.work_id,
            title = selected.title,
            authors = selected.authors,
            languages = selected.languages,
            acquisition = selected.opds.acquisition,
          },
        }
        prepared.attribution = {
          'Catalog: Unglue.it (https://unglue.it)',
          'Downloaded from: ' .. selected.opds.acquisition.href,
          'Selected copy: ' .. selected.source.id,
          'Source rights claim for this copy: ' .. selected.rights,
          'SOURCE.epub is the unmodified download, including original credits and license.',
          'SOURCE.opds is the exact catalog response; SOURCE.json identifies the selected link.',
          'Work-level ISBNs, dates and publishers in the feed may describe other editions.',
          'Source punctuation, front matter and notices are preserved in the reading copy.',
          'Review the original notices before reuse or sharing; local copyright law may differ.',
        }
        return prepared
      end)
      if saved then
        callback(nil, result)
      else
        callback(tostring(result))
      end
    end
  )
end

return M
