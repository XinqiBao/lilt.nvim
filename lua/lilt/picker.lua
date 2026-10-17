local api = vim.api
local work = require('lilt.work')
local library = require('lilt.library')
local manuscript = require('lilt.manuscript')
local session = require('lilt.session')
local M = {}
local active
-- Only buffer handles, keyed by example reference path. Authored text and undo
-- remain in ordinary buffers; wiping one starts fresh on the next selection.
local examples = {}

local function clip(text, width)
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end
  local part = vim.fn.strcharpart(text, 0, math.max(0, width - 1))
  while vim.fn.strdisplaywidth(part) > width - 1 do
    part = vim.fn.strcharpart(part, 0, vim.fn.strchars(part) - 1)
  end
  return part .. '…'
end

local function close()
  local s = active
  if not s then
    return
  end
  active = nil
  api.nvim_del_augroup_by_id(s.group)
  if s.win and api.nvim_win_is_valid(s.win) then
    api.nvim_win_close(s.win, true)
  end
  if api.nvim_buf_is_valid(s.buf) then
    api.nvim_buf_delete(s.buf, { force = true })
  end
end

local function attempt(callback)
  local ok, err = pcall(callback)
  if not ok then
    vim.notify(tostring(err), vim.log.levels.ERROR)
  end
end

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
browse = function(root, example_root, installed)
  if active then
    if api.nvim_win_is_valid(active.win) then
      api.nvim_set_current_win(active.win)
      return
    end
    close()
  end
  local s = { pages = {}, buf = api.nvim_create_buf(false, true) }
  vim.bo[s.buf].bufhidden = 'wipe'
  s.group = api.nvim_create_augroup('LiltPicker', { clear = true })
  active = s

  local function render(reset)
    local page = s.pages[#s.pages]
    local index = not reset and s.win and api.nvim_win_get_cursor(s.win)[1] or page.index or 1
    local width = math.max(1, math.min(72, vim.o.columns - 4))
    local height = math.max(1, math.min(#page.items, vim.o.lines - vim.o.cmdheight - 4))
    local footer = width >= 58 and ' j/k move · Enter/l select · h/q/Esc back/close '
      or ' Enter select · h/q back '
    local config = {
      relative = 'editor',
      width = width,
      height = height,
      row = math.max(0, math.floor((vim.o.lines - vim.o.cmdheight - height - 2) / 2)),
      col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
      border = 'rounded',
      title = clip(' Lilt · ' .. page.title .. ' ', width),
      footer = clip(footer, width),
    }
    local lines = {}
    for _, item in ipairs(page.items) do
      local label = '  ' .. item.label
      if item.progress and width > #item.progress + 4 then
        label = clip(label, width - #item.progress - 2) .. '  ' .. item.progress
      end
      lines[#lines + 1] = clip(label, width)
    end
    vim.bo[s.buf].modifiable = true
    api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
    vim.bo[s.buf].modifiable = false
    if s.win then
      api.nvim_win_set_config(s.win, config)
    else
      config.style = 'minimal'
      s.win = api.nvim_open_win(s.buf, true, config)
      vim.wo[s.win].cursorline = true
      vim.wo[s.win].cursorlineopt = 'line'
      vim.wo[s.win].wrap = false
      vim.wo[s.win].scrolloff = 0
      vim.wo[s.win].scrollbind = false
      vim.wo[s.win].cursorbind = false
      vim.wo[s.win].foldenable = false
      vim.wo[s.win].conceallevel = 0
      vim.wo[s.win].colorcolumn = ''
      vim.wo[s.win].spell = false
      vim.wo[s.win].winbar = ''
    end
    api.nvim_win_set_cursor(s.win, { math.min(index, #page.items), 0 })
  end

  local function push(page)
    if #s.pages > 0 then
      s.pages[#s.pages].index = api.nvim_win_get_cursor(s.win)[1]
    end
    s.pages[#s.pages + 1] = page
    render(true)
  end

  local function back()
    if #s.pages == 1 then
      close()
    else
      table.remove(s.pages)
      render(true)
    end
  end

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
          close()
          session.open('ghost', { manuscript = buf, reference = reference })
        end,
      }
    end
    push({ title = reading.title, items = items })
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

  local function home()
    local items = work_items(discover(root .. '/references'), false)
    local empty = #items == 0
    items[#items + 1] = {
      label = 'Add local work…',
      select = function()
        close()
        vim.ui.input({ prompt = 'Local work directory: ', completion = 'dir' }, function(directory)
          attempt(function()
            local reading
            if directory and directory ~= '' then
              local ok, value = pcall(library.add, root, vim.fn.expand(directory))
              if ok then
                reading = value
              else
                vim.notify(tostring(value), vim.log.levels.ERROR)
              end
            end
            browse(root, example_root, reading)
          end)
        end)
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
        push({ title = 'Examples', items = choices })
      end,
    }
    push({ title = empty and 'Library (empty)' or 'Library', items = items })
  end

  for _, key in ipairs({ '<CR>', 'l' }) do
    vim.keymap.set('n', key, function()
      attempt(function()
        s.pages[#s.pages].items[api.nvim_win_get_cursor(s.win)[1]].select()
      end)
    end, { buffer = s.buf, silent = true })
  end
  for _, key in ipairs({ 'h', '<Esc>', 'q' }) do
    vim.keymap.set('n', key, back, { buffer = s.buf, silent = true })
  end
  api.nvim_create_autocmd('VimResized', {
    group = s.group,
    callback = function()
      if active == s and s.win and api.nvim_win_is_valid(s.win) then
        render(false)
      end
    end,
  })
  api.nvim_create_autocmd({ 'WinLeave', 'BufWipeout' }, {
    group = s.group,
    buffer = s.buf,
    callback = function()
      vim.schedule(function()
        if active == s then
          close()
        end
      end)
    end,
  })
  -- Initialization may fail before a window exists (for example, E36).
  local ok, err = pcall(function()
    home()
    if installed then
      units(installed, false)
    end
  end)
  if not ok then
    close()
    error(err, 0)
  end
end

function M.open(root, example_root)
  attempt(function()
    browse(root, example_root)
  end)
end

return M
