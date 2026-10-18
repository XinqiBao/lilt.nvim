-- Online navigation stays separate from the local library and reading flow.
local catalog_api = require('lilt.online.catalog')
local acquisition = require('lilt.online.acquire')
local M = {}

function M.open(s, root, catalog, units, refresh)
  local results
  local function details(book)
    local items = {
      { label = book.title, hl = 'Title', wrap = true },
      { label = 'Author: ' .. (book.author ~= '' and book.author or 'Unknown'), wrap = true },
      {
        label = 'Language: '
          .. (#book.languages > 0 and table.concat(book.languages, ', ') or 'Unknown'),
      },
      { label = 'Source: Project Gutenberg #' .. book.id },
      { label = acquisition.url(book) },
    }
    if #book.subjects > 0 then
      items[#items + 1] =
        { label = 'Subjects: ' .. table.concat(book.subjects, '; '), wrap = true, max_lines = 2 }
    end
    items[#items + 1] = { label = '' }
    local page = { title = 'Work details', items = items }
    local ok, existing = pcall(acquisition.existing, root, book)
    local function open_copy(reading)
      return {
        key = 'o',
        label = 'Open library copy',
        select = function()
          units(reading, false)
        end,
      }
    end
    if not ok then
      items[#items + 1] = { label = tostring(existing), hl = 'DiagnosticError', wrap = true }
    elseif existing then
      items[#items + 1] = { label = 'Available offline in your library' }
      items[#items + 1] = open_copy(existing)
    elseif book.supported then
      items[#items + 1] =
        { label = 'Available: UTF-8 plain text · public domain in the USA', wrap = true }
      items[#items + 1] =
        { label = 'Check copyright in your country before downloading.', wrap = true }
      local acquire
      acquire = {
        key = 'a',
        label = 'Acquire and read',
        select = function()
          s:request(page, function(callback)
            return acquisition.acquire(root, book, callback)
          end, function(reading)
            refresh()
            acquire.key = 'o'
            acquire.label, acquire.select =
              'Open library copy', function()
                units(reading, false)
              end
            units(reading, false)
          end, 'Downloading and preparing… · Esc cancels')
        end,
      }
      items[#items + 1] = acquire
    else
      items[#items + 1] =
        { label = 'Unavailable: requires public-domain UTF-8 plain text.', wrap = true }
    end
    -- An explicit return keeps metadata-only pages usable by menu navigation.
    items[#items + 1] = {
      label = 'Back to results',
      select = function()
        s:back()
      end,
    }
    s:push(page)
  end

  results = function(query, title, initial)
    local page = { title = 'Discover · ' .. title, items = {}, height = 20 }
    local function search()
      s:search(query.search or '', function(value)
        results(
          value == '' and {} or { search = value },
          value == '' and 'Popular' or ('Search: ' .. value)
        )
      end)
    end
    page.search = search
    local context = { label = title .. ' · page ' .. (query.page or 1), hl = 'Title', wrap = true }
    page.items = {
      { key = 's', label = 'Search title or author…', select = search },
      { label = 'Order', hl = 'Title' },
      {
        label = 'Popular · most downloaded',
        select = function()
          results({}, 'Popular')
        end,
      },
      {
        label = 'Newest · latest catalog IDs',
        select = function()
          results({ sort = 'descending' }, 'Newest')
        end,
      },
      { label = 'Topics · popular works', hl = 'Title' },
      {
        label = 'Poetry',
        select = function()
          results({ topic = 'poetry' }, 'Poetry')
        end,
      },
      {
        label = 'Short stories',
        select = function()
          results({ topic = 'short stories' }, 'Short stories')
        end,
      },
      { label = '' },
      context,
    }
    if initial then
      s:push(page)
    else
      s:replace(page)
    end
    s:request(page, function(callback)
      return catalog_api.fetch(catalog or catalog_api.default_url, query, callback)
    end, function(result)
      page.selected = nil
      context.label = title .. ' · ' .. result.count .. ' works · page ' .. (query.page or 1)
      for _, book in ipairs(result.books) do
        local item = {
          label = book.title .. (book.author ~= '' and (' — ' .. book.author) or ''),
          select = function()
            details(book)
          end,
        }
        page.items[#page.items + 1] = item
        page.selected = page.selected or item
      end
      if #result.books == 0 then
        page.items[#page.items + 1] =
          { label = 'No works found. Try another title or author.', wrap = true }
      end
      if (query.page or 1) > 1 then
        page.items[#page.items + 1] = {
          key = '[',
          label = 'Previous page',
          select = function()
            local previous = vim.deepcopy(query)
            previous.page = query.page - 1
            results(previous, title)
          end,
        }
      end
      if result.more then
        page.items[#page.items + 1] = {
          key = ']',
          label = 'Next page',
          select = function()
            local next_query = vim.deepcopy(query)
            next_query.page = (query.page or 1) + 1
            results(next_query, title)
          end,
        }
      end
      s:render(true)
    end, 'Loading catalog… · Esc cancels')
  end
  results({}, 'Popular', true)
end

return M
