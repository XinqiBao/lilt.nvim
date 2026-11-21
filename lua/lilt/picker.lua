local api = vim.api
local work = require('lilt.work')
local library = require('lilt.library')
local manuscript = require('lilt.manuscript')
local session = require('lilt.session')
local ui = require('lilt.picker.ui')
local information = require('lilt.picker.information')
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

local function browse(root, example_root, catalog)
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
    local function info()
      local items = information.items(reading.manifest, 'Saved local metadata · lilt.json')
      items[#items + 1] = { label = 'Local copy and preparation', hl = 'Title' }
      if not temporary then
        items[#items + 1] = { label = 'Directory: ' .. reading.name, wrap = 'full' }
      end
      if reading.manifest.preparation then
        local preparation = reading.manifest.preparation
        if preparation.wrap_columns then
          items[#items + 1] = {
            label = 'Prose wrap columns: ' .. preparation.wrap_columns,
            wrap = 'full',
          }
        end
        if preparation.plain_quotes ~= nil then
          items[#items + 1] = {
            label = 'Plain quotes: ' .. (preparation.plain_quotes and 'yes' or 'no'),
            wrap = 'full',
          }
        end
      end
      if reading.source and reading.source.file then
        items[#items + 1] = {
          label = 'Source file: ' .. reading.root .. '/' .. reading.source.file,
          wrap = 'full',
        }
      end
      local snapshot = reading.root .. '/SOURCE.json'
      local stat = vim.uv.fs_stat(snapshot)
      if stat and stat.type == 'file' then
        items[#items + 1] = { label = 'Saved catalog file: ' .. snapshot, wrap = 'full' }
      end
      local attribution = reading.root .. '/README.txt'
      local attribution_stat = vim.uv.fs_stat(attribution)
      if attribution_stat and attribution_stat.type == 'file' then
        items[#items + 1] = { label = 'Attribution and licenses: ' .. attribution, wrap = 'full' }
      end
      items[#items + 1] = {
        label = temporary and 'Writing: temporary, for this Neovim process'
          or 'Writing: saved with :write; progress counts saved rows',
        wrap = 'full',
      }
      items[#items + 1] = {
        label = 'Back to reading units',
        select = function()
          s:back()
        end,
      }
      s:push({ title = 'Work information', items = items, selected = items[1] })
    end
    local items = {
      { label = reading.title, hl = 'Title', wrap = true },
      { label = reading.author or '', wrap = true },
      { key = 'i', label = 'Work information', select = info },
      {
        label = temporary and 'Reading units · temporary writing'
          or 'Reading units · saved progress',
      },
    }
    for _, warning in ipairs(reading.import_warnings or {}) do
      items[#items + 1] = { label = warning, hl = 'DiagnosticWarn', wrap = true }
    end
    local actions, listed, first_unit = {}, {}, nil
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
      first_unit = first_unit or item
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
      selected = first_unit,
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
        detail = reading.author,
        compact = true,
        suffix = titles[reading.title] > 1 and ('[' .. reading.name .. ']') or nil,
        select = function()
          units(reading, temporary)
        end,
      }
    end
    return items
  end

  local home
  local function add_local(reading)
    local installed = library.find_source(root, reading.source)
    if installed then
      units(installed, false)
    else
      require('lilt.picker.name').prompt(s, root, reading.title, reading.source, function(name)
        local added = library.add(root, reading.root, name)
        home(true)
        units(added, false)
      end)
    end
  end

  home = function(refresh)
    local works, errors = discover(root .. '/references')
    local items = { { label = 'Your works', hl = 'Title' } }
    vim.list_extend(items, work_items(works, false))
    if #works == 0 then
      items[#items + 1] = { label = 'No works yet. Discover one or try an example.', wrap = true }
    end
    for _, err in ipairs(errors) do
      items[#items + 1] = { label = err, wrap = 'full', hl = 'DiagnosticWarn' }
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
          s:prompt({
            title = 'Local work directory',
            default = '',
            footer = 'Enter open · Tab complete · Esc cancel',
            complete = function(value)
              return vim.fn.getcompletion(value, 'dir')
            end,
            validate = function(directory)
              if directory == '' then
                error('Lilt: Enter a local work directory', 0)
              end
              return work.load(vim.fs.normalize(directory))
            end,
          }, add_local)
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
            choices[#choices + 1] = { label = err, wrap = 'full', hl = 'DiagnosticWarn' }
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
  local ok, err = pcall(home)
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
