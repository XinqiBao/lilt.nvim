local api = vim.api
local online = require('lilt.online')
local M = {}

function M.open(s, root, catalog, units, home)
  catalog = catalog or online.default_catalog
  local function details(book)
    local page = { title = 'Gutenberg #' .. book.id, items = {} }
    local function info(text)
      -- Give long titles/authors room beyond the clipped catalog row.
      local row = ''
      for word in text:gmatch('%S+') do
        if row ~= '' and vim.fn.strdisplaywidth(row .. ' ' .. word) > 64 then
          page.items[#page.items + 1] = { label = row }
          row = ''
        end
        row = row == '' and word or row .. ' ' .. word
      end
      if row ~= '' then
        page.items[#page.items + 1] = { label = row }
      end
    end
    local ok, existing = pcall(online.existing, root, book)
    if not ok then
      info(tostring(existing))
    elseif existing then
      page.items[#page.items + 1] = {
        label = 'Open library copy',
        select = function()
          units(existing, false)
        end,
      }
    elseif book.supported then
      page.items[#page.items + 1] = {
        label = 'Acquire and read',
        select = function()
          s:pending(page, function(callback)
            return online.acquire(root, book, callback)
          end, function(reading)
            -- Refresh the library page so backing out immediately shows the copy.
            home(true)
            page.items[1] = {
              label = 'Open library copy',
              select = function()
                units(reading, false)
              end,
            }
            units(reading, false)
          end, 'Downloading and preparing…')
        end,
      }
    else
      info('Unavailable: requires public-domain UTF-8 plain text.')
    end
    info(book.title)
    info('Author: ' .. (book.author ~= '' and book.author or 'Unknown'))
    info('Languages: ' .. table.concat(book.languages, ', '))
    info(online.url(book))
    if book.supported then
      info('Public domain in the USA; check your local law.')
    end
    for _, subject in ipairs(book.subjects) do
      info('Subject: ' .. subject)
    end
    s:push(page)
  end

  local catalog_page
  catalog_page = function(query, title)
    local page = { title = title, items = { { label = 'Loading catalog…' } } }
    s:push(page)
    s:pending(page, function(callback)
      return online.catalog(catalog, query, callback)
    end, function(result)
      local function search()
        s.prompt = true
        local ok, err = pcall(
          vim.ui.input,
          { prompt = 'Title or author: ', default = query.search or '' },
          function(value)
            if s.closed or not api.nvim_win_is_valid(s.win) then
              return
            end
            api.nvim_set_current_win(s.win)
            s.prompt = false
            if value ~= nil then
              value = vim.trim(value)
              catalog_page(
                value == '' and {} or { search = value },
                value == '' and 'Popular' or value
              )
            end
          end
        )
        if not ok then
          s.prompt = false
          error(err, 0)
        end
      end
      local items = {
        { label = 'Search title or author…', select = search },
        {
          label = 'Browse popular',
          select = function()
            catalog_page({}, 'Popular')
          end,
        },
        {
          label = 'Browse newest',
          select = function()
            catalog_page({ sort = 'descending' }, 'Newest')
          end,
        },
        {
          label = 'Browse poetry',
          select = function()
            catalog_page({ topic = 'poetry' }, 'Poetry')
          end,
        },
        {
          label = 'Browse short stories',
          select = function()
            catalog_page({ topic = 'short stories' }, 'Short stories')
          end,
        },
        { label = result.count .. ' results · page ' .. (query.page or 1) },
      }
      for _, book in ipairs(result.books) do
        items[#items + 1] = {
          label = book.title .. (book.author ~= '' and (' — ' .. book.author) or ''),
          select = function()
            details(book)
          end,
        }
      end
      if #result.books == 0 then
        items[#items + 1] = { label = 'No works found. Try another title or author.' }
      end
      if result.more then
        items[#items + 1] = {
          label = 'More results…',
          select = function()
            local next_query = vim.deepcopy(query)
            next_query.page = (query.page or 1) + 1
            catalog_page(next_query, title)
          end,
        }
      end
      page.items = items
      s:render(true)
    end)
  end

  catalog_page({}, 'Popular')
end

return M
