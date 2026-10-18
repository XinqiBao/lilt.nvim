local api = vim.api
local work = require('lilt.work')
local library = require('lilt.library')
local manuscript = require('lilt.manuscript')
local session = require('lilt.session')
local ui = require('lilt.picker.ui')
local M = {}
local active
-- Only buffer handles, keyed by example reference path. Authored text and undo
-- remain in ordinary buffers; wiping one starts fresh on the next selection.
local examples = {}

local function discover(directory)
  local ok, works, errors = pcall(work.discover, directory)
  if not ok then
    vim.notify(tostring(works), vim.log.levels.WARN)
    return {}
  end
  if #errors > 0 then
    vim.notify(table.concat(errors, '\n'), vim.log.levels.WARN)
  end
  return works
end

local browse
browse = function(root, example_root, catalog, installed)
  if active then
    if api.nvim_win_is_valid(active.win) then
      api.nvim_set_current_win(active.win)
      return
    end
    active:close()
  end
  local s = ui.new(function()
    active = nil
  end)
  active = s

  local function units(reading, temporary)
    local items = {}
    for _, unit in ipairs(reading.units) do
      local progress, progress_error
      if not temporary then
        local ok, value = pcall(library.progress, root, reading, unit)
        if ok then
          progress = value
        else
          progress_error = value
        end
      end
      local saved = not temporary
          and (progress_error and '?' or progress and (progress .. '%') or '—')
        or nil
      items[#items + 1] = {
        label = unit.title,
        progress = saved,
        select = function()
          if progress_error then
            vim.notify(tostring(progress_error), vim.log.levels.WARN)
          end
          local reference = work.read_unit(reading, unit)
          local buf
          if temporary then
            buf = examples[unit.reference]
            if not buf or not api.nvim_buf_is_valid(buf) then
              buf = manuscript.open()
              examples[unit.reference] = buf
            end
          else
            buf = manuscript.open(library.manuscript(root, reading, unit))
          end
          s:close()
          session.open('ghost', { manuscript = buf, reference = reference })
        end,
      }
    end
    s:push({ title = reading.title, items = items })
  end

  local function work_items(works, temporary)
    local items = {}
    for _, reading in ipairs(works) do
      items[#items + 1] = {
        label = reading.title .. ' [' .. reading.name .. ']',
        select = function()
          units(reading, temporary)
        end,
      }
    end
    return items
  end

  local home
  home = function(refresh)
    local items = work_items(discover(root .. '/references'), false)
    local empty = #items == 0
    items[#items + 1] = {
      label = 'Add local work…',
      select = function()
        s:close()
        vim.ui.input({ prompt = 'Local work directory: ', completion = 'dir' }, function(directory)
          ui.attempt(function()
            local reading
            if directory and directory ~= '' then
              local ok, value = pcall(library.add, root, vim.fn.expand(directory))
              if ok then
                reading = value
              else
                vim.notify(tostring(value), vim.log.levels.ERROR)
              end
            end
            browse(root, example_root, catalog, reading)
          end)
        end)
      end,
    }
    items[#items + 1] = {
      label = 'Discover online…',
      select = function()
        require('lilt.picker.discover').open(s, root, catalog, units, home)
      end,
    }
    items[#items + 1] = {
      label = 'Examples',
      select = function()
        local choices = work_items(discover(example_root), true)
        if #choices == 0 then
          vim.notify('Lilt: no examples found.', vim.log.levels.INFO)
          return
        end
        s:push({ title = 'Examples', items = choices })
      end,
    }
    local title = empty and 'Library (empty)' or 'Library'
    if refresh then
      s.pages[1].title, s.pages[1].items = title, items
    else
      s:push({ title = title, items = items })
    end
  end

  -- Initialization may fail before a window exists (for example, E36).
  local ok, err = pcall(function()
    home()
    if installed then
      units(installed, false)
    end
  end)
  if not ok then
    s:close()
    error(err, 0)
  end
end

function M.open(root, example_root, catalog)
  ui.attempt(function()
    browse(root, example_root, catalog)
  end)
end

return M
