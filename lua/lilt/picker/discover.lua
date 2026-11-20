-- Source menus and result navigation share presentation and acquisition.
local providers = require('lilt.online.providers')
local acquisition = require('lilt.online.acquire')
local information = require('lilt.picker.information')
local M = {}

function M.open(s, root, catalog, units, refresh)
  local function source(provider)
    local results
    local function details(entry)
      local items = information.items(entry, 'Current online catalog metadata')
      items[#items + 1] = { label = '' }
      local page =
        { title = provider.name .. ' · Work details', items = items, selected = items[1] }
      local ok, existing = pcall(acquisition.existing, root, entry)
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
        items[#items + 1] = { label = tostring(existing), hl = 'DiagnosticError', wrap = 'full' }
      elseif existing then
        items[#items + 1] = { label = 'Available offline in your library', wrap = 'full' }
        items[#items + 1] = {
          label = 'Library copy keeps its saved metadata; use i from its reading units.',
          wrap = 'full',
        }
        items[#items + 1] = open_copy(existing)
      else
        items[#items + 1] = { label = entry.availability, wrap = 'full' }
        if entry.supported then
          local acquire
          acquire = {
            key = 'a',
            label = 'Add to library',
            select = function()
              require('lilt.picker.name').prompt(s, root, entry.title, entry.source, function(name)
                s:request(page, function(callback)
                  return acquisition.acquire(root, provider, entry, callback, name)
                end, function(reading)
                  refresh()
                  local action = open_copy(reading)
                  acquire.key, acquire.label, acquire.select =
                    action.key, action.label, action.select
                  units(reading, false)
                end, 'Downloading and preparing… · Esc cancels')
              end)
            end,
          }
          items[#items + 1] = acquire
        end
      end
      items[#items + 1] = {
        label = 'Back to results',
        select = function()
          s:back()
        end,
      }
      s:push(page)
    end

    local function menu_items(initial, search_value)
      local items = {}
      for _, choice in ipairs(provider.menu) do
        local query = vim.deepcopy(choice.query)
        items[#items + 1] = {
          key = choice.input and 's' or nil,
          label = choice.label,
          wrap = 'full',
          select = function()
            if choice.input then
              s:prompt({
                title = choice.input,
                default = search_value or '',
                footer = 'Enter search · Esc cancel',
              }, function(value)
                value = vim.trim(value)
                if value ~= '' then
                  query.search = value
                  results(query, initial)
                end
              end)
            else
              results(query, initial)
            end
          end,
        }
      end
      return items
    end

    results = function(query, push)
      local page = {
        title = 'Discover · ' .. provider.name,
        items = menu_items(false, query.search),
        height = 20,
        blocking = false,
      }
      local context = { label = 'Results', hl = 'Title', wrap = 'full' }
      page.items[#page.items + 1] = context
      if push then
        s:push(page)
      else
        s:replace(page)
      end
      s:request(page, function(callback)
        return provider.browse(query, callback)
      end, function(result)
        context.label = result.title
          .. (result.count and (' · ' .. result.count .. ' works') or '')
        page.selected = nil
        for _, entry in ipairs(result.entries) do
          local group = entry.kind == 'group'
          local label = entry.label or entry.title
          if not group and not entry.label and entry.authors and #entry.authors > 0 then
            label = label .. ' — ' .. table.concat(entry.authors, '; ')
          end
          local item = {
            label = label,
            wrap = 'full',
            select = function()
              if group then
                results(entry.query, true)
              else
                details(entry)
              end
            end,
          }
          page.items[#page.items + 1] = item
          page.selected = page.selected or item
        end
        if #result.entries == 0 then
          local empty = { label = result.empty or 'No works found.', wrap = 'full' }
          page.items[#page.items + 1], page.selected = empty, empty
        end
        for _, direction in ipairs({
          { 'previous', '[', 'Previous page' },
          { 'next', ']', 'Next page' },
        }) do
          if result[direction[1]] then
            page.items[#page.items + 1] = {
              key = direction[2],
              label = direction[3],
              select = function()
                results(result[direction[1]], false)
              end,
            }
          end
        end
        s:render(true)
      end, 'Loading catalog… · Esc cancels')
    end
    s:push({ title = provider.name, items = menu_items(true), height = 20 })
  end

  local items = {}
  for _, provider in ipairs(providers.list(catalog)) do
    items[#items + 1] = {
      label = provider.name,
      wrap = 'full',
      select = function()
        source(provider)
      end,
    }
  end
  s:push({ title = 'Discover online · Choose source', items = items })
end

return M
