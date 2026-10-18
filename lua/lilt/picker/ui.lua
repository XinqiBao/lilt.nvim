local api = vim.api
local M = {}

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

function M.attempt(callback)
  local ok, err = pcall(callback)
  if not ok then
    vim.notify(tostring(err), vim.log.levels.ERROR)
  end
end

function M.new(on_close)
  local s = { pages = {}, buf = api.nvim_create_buf(false, true) }
  vim.bo[s.buf].bufhidden = 'wipe'
  s.group = api.nvim_create_augroup('LiltPicker', { clear = true })

  function s:close()
    if s.closed then
      return
    end
    s.closed = true
    on_close()
    if s.cancel then
      s.cancel()
    end
    api.nvim_del_augroup_by_id(s.group)
    if s.win and api.nvim_win_is_valid(s.win) then
      api.nvim_win_close(s.win, true)
    end
    if api.nvim_buf_is_valid(s.buf) then
      api.nvim_buf_delete(s.buf, { force = true })
    end
  end

  function s:render(reset)
    local page = s.pages[#s.pages]
    local index = not reset and s.win and api.nvim_win_get_cursor(s.win)[1] or page.index or 1
    local width = math.max(1, math.min(72, vim.o.columns - 4))
    local height = math.max(1, math.min(#page.items, vim.o.lines - vim.o.cmdheight - 4))
    local footer = width >= 58 and ' j/k move · Enter/l select · h/q/Esc back/close '
      or ' Enter · q/Esc back '
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
      local progress_width = item.progress and vim.fn.strdisplaywidth(item.progress)
      if progress_width and width > progress_width + 4 then
        label = clip(label, width - progress_width - 2)
        label = label .. string.rep(' ', width - vim.fn.strdisplaywidth(label) - progress_width)
        label = label .. item.progress
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

  function s:push(page)
    if #s.pages > 0 then
      s.pages[#s.pages].index = api.nvim_win_get_cursor(s.win)[1]
    end
    s.pages[#s.pages + 1] = page
    s:render(true)
  end

  local function back()
    if s.cancel then
      s.cancel()
      s.cancel = nil
    end
    if #s.pages == 1 then
      s:close()
    else
      table.remove(s.pages)
      s:render(true)
    end
  end

  -- Async operations belong to a page and picker lifetime. Back/close cancels
  -- the request, and late callbacks cannot reopen UI or install a work.
  function s:pending(page, start, done, message)
    local generation = {}
    page.generation = generation
    page.idle_items = page.idle_items or page.items
    page.items = { { label = (message or 'Loading catalog…') .. ' · h/q/Esc cancels' } }
    s:render(true)
    s.cancel = start(function(err, value)
      if s.closed or s.pages[#s.pages] ~= page or page.generation ~= generation then
        return
      end
      s.cancel = nil
      M.attempt(function()
        if err then
          page.items = {
            {
              label = 'Request failed — retry',
              select = function()
                s:pending(page, start, done, message)
              end,
            },
            { label = tostring(err):gsub('%c', ' ') },
          }
          vim.notify(tostring(err), vim.log.levels.ERROR)
          s:render(true)
        else
          page.items = page.idle_items
          done(value)
        end
      end)
    end)
  end

  for _, key in ipairs({ '<CR>', 'l' }) do
    vim.keymap.set('n', key, function()
      M.attempt(function()
        local selected = s.pages[#s.pages].items[api.nvim_win_get_cursor(s.win)[1]]
        if selected and selected.select then
          selected.select()
        end
      end)
    end, { buffer = s.buf, silent = true })
  end
  for _, key in ipairs({ 'h', '<Esc>', 'q' }) do
    vim.keymap.set('n', key, back, { buffer = s.buf, silent = true })
  end
  api.nvim_create_autocmd('VimResized', {
    group = s.group,
    callback = function()
      if not s.closed and s.win and api.nvim_win_is_valid(s.win) then
        s:render(false)
      end
    end,
  })
  api.nvim_create_autocmd({ 'WinLeave', 'BufWipeout' }, {
    group = s.group,
    buffer = s.buf,
    callback = function(event)
      if event.event == 'WinLeave' and s.prompt then
        return
      end
      -- Cancel at the lifecycle boundary, before an already queued completion
      -- can prepare/install a work. Window/buffer cleanup must remain deferred.
      if s.cancel then
        s.cancel()
        s.cancel = nil
      end
      vim.schedule(function()
        if not s.closed then
          s:close()
        end
      end)
    end,
  })
  api.nvim_create_autocmd('VimLeavePre', {
    group = s.group,
    callback = function()
      s:close()
    end,
  })

  return s
end

return M
