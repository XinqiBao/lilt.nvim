local api = vim.api
local work = require('lilt.work')
local library = require('lilt.library')
local manuscript = require('lilt.manuscript')
local session = require('lilt.session')
local ui = require('lilt.picker.ui')
local M = {}
local active
-- Buffer handles only. Authored text and undo stay in ordinary buffers.
local examples = {}

local function discover(directory)
  local ok, works, errors = pcall(work.discover, directory)
  if not ok then
    return {}, { tostring(works) }
  end
  return works, errors
end

local function browse(root, example_root, catalog, installed)
  if active then
    if active.win and api.nvim_win_is_valid(active.win) then
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
    local items = {
      { label = reading.title, hl = 'Title', wrap = true },
      { label = reading.author or '', wrap = true },
      {
        label = temporary and 'Reading units · temporary writing'
          or 'Reading units · saved progress',
      },
    }
    for _, warning in ipairs(reading.import_warnings or {}) do
      items[#items + 1] = { label = warning, hl = 'DiagnosticWarn', wrap = true }
    end
    local actions, listed = {}, {}
    local function action(unit, label, depth)
      if not actions[unit] then
        local progress, progress_error
        if not temporary then
          local ok, value = pcall(library.progress, root, reading, unit)
          if ok then
            progress = value
          else
            progress_error = value
          end
        end
        local function read()
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
        end
        actions[unit] = {
          label = unit.title,
          suffix = not temporary
              and (progress_error and '?' or progress and (progress .. '%') or '—')
            or nil,
          select = read,
          preview = function()
            return work.read_unit(reading, unit)
          end,
        }
      end
      local item = vim.tbl_extend('force', actions[unit], { label = label, depth = depth })
      items[#items + 1] = item
      listed[unit] = true
    end
    local function navigation(nodes, depth)
      for _, node in ipairs(nodes) do
        if node.unit then
          action(node.unit, node.title, depth)
        else
          items[#items + 1] = { label = node.title, depth = depth, hl = 'Title' }
        end
        if node.children then
          navigation(node.children, depth + 1)
        end
      end
    end
    if reading.toc then
      navigation(reading.toc, 0)
    end
    local remaining = false
    for _, unit in ipairs(reading.units) do
      if not listed[unit] then
        if reading.toc and not remaining then
          items[#items + 1] = { label = '' }
          items[#items + 1] = { label = 'Other reading units', hl = 'Title' }
        end
        remaining = true
        action(unit, unit.title, 0)
      end
    end
    s:push({
      title = reading.title,
      items = items,
      preview = true,
      height = 20,
    })
  end

  local function work_items(works, temporary)
    local items, titles = {}, {}
    for _, reading in ipairs(works) do
      titles[reading.title] = (titles[reading.title] or 0) + 1
    end
    for _, reading in ipairs(works) do
      items[#items + 1] = {
        label = reading.title,
        suffix = titles[reading.title] > 1 and ('[' .. reading.name .. ']') or nil,
        select = function()
          units(reading, temporary)
        end,
      }
    end
    return items
  end

  local home
  home = function(refresh)
    local works, errors = discover(root .. '/references')
    local items = { { label = 'Your works', hl = 'Title' } }
    vim.list_extend(items, work_items(works, false))
    if #works == 0 then
      items[#items + 1] = { label = 'No works yet. Discover one or try an example.', wrap = true }
    end
    for _, err in ipairs(errors) do
      items[#items + 1] = { label = err, wrap = true, hl = 'DiagnosticWarn', max_lines = 2 }
    end
    vim.list_extend(items, {
      { label = '' },
      { label = 'Find a work', hl = 'Title' },
      {
        key = 'd',
        label = 'Discover online…',
        select = function()
          require('lilt.picker.discover').open(s, root, catalog, units, function()
            home(true)
          end)
        end,
      },
      {
        key = 'a',
        label = 'Add local work…',
        select = function()
          s:close()
          vim.ui.input(
            { prompt = 'Local work directory: ', completion = 'dir' },
            function(directory)
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
            end
          )
        end,
      },
      {
        key = 'e',
        label = 'Examples',
        select = function()
          local samples, sample_errors = discover(example_root)
          local choices =
            { { label = 'Try reading · writing stays in this Neovim process', wrap = true } }
          vim.list_extend(choices, work_items(samples, true))
          for _, err in ipairs(sample_errors) do
            choices[#choices + 1] = { label = err, wrap = true, hl = 'DiagnosticWarn' }
          end
          if #samples == 0 then
            choices[#choices + 1] = { label = 'No examples found.' }
          end
          s:push({ title = 'Examples', items = choices })
        end,
      },
    })
    if refresh then
      s.pages[1].title, s.pages[1].items = 'Library', items
    else
      s:push({ title = #works == 0 and 'Library (empty)' or 'Library', items = items })
    end
  end
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
