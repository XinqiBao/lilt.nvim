-- Picker presentation and lifetime. Pages contain information and actions;
-- only actions participate in selection. Reading resources never live here.
local api = vim.api
local M = {}
local namespace = api.nvim_create_namespace('lilt.picker')

local function clip(text, width)
  local part = text
  if vim.fn.strdisplaywidth(part) > width then
    part = vim.fn.strcharpart(part, 0, math.max(0, width - 1))
    while vim.fn.strdisplaywidth(part) > width - 1 do
      part = vim.fn.strcharpart(part, 0, vim.fn.strchars(part) - 1)
    end
    part = part .. '…'
  end
  return part
end

local function wrap(text, width, limit)
  local lines, line = {}, ''
  for word in text:gmatch('%S+') do
    if line ~= '' and vim.fn.strdisplaywidth(line .. ' ' .. word) > width then
      if #lines == limit - 1 then
        lines[#lines + 1] = clip(line .. ' …', width)
        return lines
      end
      lines[#lines + 1], line = line, word
    else
      line = line == '' and word or line .. ' ' .. word
    end
  end
  if line ~= '' then
    lines[#lines + 1] = line
  end
  return lines
end

function M.attempt(callback)
  local ok, err = pcall(callback)
  if not ok then
    vim.notify(tostring(err), vim.log.levels.ERROR)
  end
end

function M.new(on_close)
  local s = { pages = {}, buf = api.nvim_create_buf(false, true), rows = {} }
  s.group = api.nvim_create_augroup('LiltPicker', { clear = true })
  vim.bo[s.buf].bufhidden = 'wipe'
  vim.bo[s.buf].modifiable = false
  vim.bo[s.buf].readonly = true

  function s:page()
    return self.pages[#self.pages]
  end

  function s:cancel()
    if self.cancel_request then
      self.cancel_request()
      self.cancel_request = nil
    end
    if self:page() then
      self:page().generation = nil
    end
  end

  function s:close(defer)
    if self.closed then
      return
    end
    self.closed = true
    self:cancel()
    api.nvim_del_augroup_by_id(self.group)
    on_close()
    local function cleanup()
      if self.win and api.nvim_win_is_valid(self.win) then
        api.nvim_win_close(self.win, true)
      end
      if api.nvim_buf_is_valid(self.buf) then
        api.nvim_buf_delete(self.buf, { force = true })
      end
    end
    if defer then
      vim.schedule(cleanup)
    else
      cleanup()
    end
  end

  local function selectable(row)
    return s.rows[row] and s.rows[row].select and not s:page().busy
  end

  function s:render(restore)
    if self.closed then
      return
    end
    local page = self:page()
    local width = math.max(1, math.min(76, vim.o.columns - 4))
    local lines, marks, selected = {}, {}, nil
    self.rows = {}
    local function row(text, item)
      lines[#lines + 1] = text
      self.rows[#lines] = item
      if item == page.selected and item.select then
        selected = #lines
      end
      if item.hl or not item.select then
        marks[#marks + 1] = { #lines - 1, item.hl or 'Comment' }
      end
    end
    local items = vim.list_extend(vim.list_slice(page.items), page.status or {})
    for _, item in ipairs(items) do
      local indent = item.select and '    ' or '  '
      if item.wrap then
        for _, text in ipairs(wrap(item.label, math.max(1, width - 4), item.max_lines or 4)) do
          row(clip(indent .. text, width), item)
        end
      else
        local label = indent .. item.label
        local suffix_width = item.suffix and vim.fn.strdisplaywidth(item.suffix)
        if suffix_width and width > suffix_width + 6 then
          label = clip(label, width - suffix_width - 2)
          label = label .. string.rep(' ', width - vim.fn.strdisplaywidth(label) - suffix_width)
          label = label .. item.suffix
        end
        row(clip(label, width), item)
      end
    end
    if #lines == 0 then
      lines = { '' }
    end
    page.height = page.height or #lines
    local height = math.max(1, math.min(page.height, vim.o.lines - vim.o.cmdheight - 4))
    local footer = ' Enter select · ' .. (page.search and 's search · ' or '') .. 'h/q/Esc back '
    if width < 40 then
      footer = ' Enter · q/Esc back '
    elseif width >= 58 then
      footer = ' j/k move ·' .. footer
    end
    if page.busy then
      footer = width < 40 and ' Working · q/Esc cancels ' or (' ' .. page.status[1].label .. ' ')
    end
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
    vim.bo[self.buf].readonly = false
    vim.bo[self.buf].modifiable = true
    api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
    api.nvim_buf_clear_namespace(self.buf, namespace, 0, -1)
    for _, mark in ipairs(marks) do
      api.nvim_buf_set_extmark(self.buf, namespace, mark[1], 0, { line_hl_group = mark[2] })
    end
    vim.bo[self.buf].modifiable = false
    vim.bo[self.buf].readonly = true
    if self.win then
      api.nvim_win_set_config(self.win, config)
    else
      config.style = 'minimal'
      self.win = api.nvim_open_win(self.buf, true, config)
      for name, value in pairs({
        cursorlineopt = 'line',
        scrolloff = 0,
        scrollbind = false,
        cursorbind = false,
        foldenable = false,
        conceallevel = 0,
        colorcolumn = '',
        spell = false,
        winbar = '',
        list = false,
        cursorcolumn = false,
        sidescrolloff = 0,
      }) do
        api.nvim_set_option_value(name, value, { win = self.win })
      end
    end
    vim.wo[self.win].wrap = false
    vim.wo[self.win].linebreak = true
    vim.wo[self.win].cursorline = not page.busy
    if restore and page.view then
      api.nvim_win_call(self.win, function()
        vim.fn.winrestview(page.view)
      end)
    end
    if not selected then
      for i in ipairs(lines) do
        if selectable(i) then
          selected = i
          break
        end
      end
    end
    api.nvim_win_set_cursor(self.win, { selected or 1, 0 })
  end

  local function save()
    local page = s:page()
    if page and s.win and api.nvim_win_is_valid(s.win) then
      page.selected = s.rows[api.nvim_win_get_cursor(s.win)[1]]
      page.view = api.nvim_win_call(s.win, vim.fn.winsaveview)
    end
  end

  function s:push(page)
    save()
    self:cancel()
    self.pages[#self.pages + 1] = page
    self:render(true)
  end

  function s:replace(page)
    self:cancel()
    self.pages[#self.pages] = page
    self:render(true)
  end

  function s:back()
    self:cancel()
    if #self.pages == 1 then
      self:close()
    else
      table.remove(self.pages)
      self:render(true)
    end
  end

  function s:request(page, start, done, message)
    save()
    self:cancel()
    local generation = {}
    page.generation, page.busy = generation, true
    page.status = { { label = message } }
    self:render(true)
    self.cancel_request = start(function(err, value)
      if self.closed or self:page() ~= page or page.generation ~= generation then
        return
      end
      self.cancel_request, page.busy, page.status = nil, nil, nil
      M.attempt(function()
        if err then
          local retry = {
            label = 'Request failed — retry',
            select = function()
              self:request(page, start, done, message)
            end,
          }
          page.status = {
            { label = tostring(err):gsub('%c', ' '), wrap = true, hl = 'DiagnosticError' },
            retry,
          }
          page.selected = retry
          self:render(true)
        else
          done(value)
        end
      end)
    end)
  end

  function s:search(default, callback)
    save()
    self.prompt = true
    local ok, err = pcall(
      vim.ui.input,
      { prompt = 'Title or author: ', default = default },
      function(value)
        if self.closed or not api.nvim_win_is_valid(self.win) then
          return
        end
        api.nvim_set_current_win(self.win)
        self.prompt = false
        if value ~= nil then
          callback(vim.trim(value))
        else
          self:render(true)
        end
      end
    )
    if not ok then
      self.prompt = false
      error(err, 0)
    end
  end

  local function activate()
    M.attempt(function()
      local page = s:page()
      local item = s.rows[api.nvim_win_get_cursor(s.win)[1]]
      if item and item.select and not page.busy then
        item.select()
      end
    end)
  end
  for _, key in ipairs({ '<CR>', 'l' }) do
    vim.keymap.set('n', key, function()
      activate()
    end, { buffer = s.buf, silent = true })
  end
  for key, direction in pairs({ gg = 1, G = -1 }) do
    vim.keymap.set('n', key, function()
      local row = direction == 1 and 1 or #s.rows
      while row > 0 and row <= #s.rows and not selectable(row) do
        row = row + direction
      end
      if selectable(row) then
        api.nvim_win_set_cursor(s.win, { row, 0 })
      end
    end, { buffer = s.buf, silent = true })
  end
  for _, key in ipairs({ 'h', '<Esc>', 'q' }) do
    vim.keymap.set('n', key, function()
      s:back()
    end, { buffer = s.buf, silent = true })
  end
  for key, direction in pairs({ j = 1, k = -1, ['<Down>'] = 1, ['<Up>'] = -1 }) do
    vim.keymap.set('n', key, function()
      local row = api.nvim_win_get_cursor(s.win)[1]
      for _ = 1, vim.v.count1 do
        local next_row = row + direction
        while next_row > 0 and next_row <= #s.rows and not selectable(next_row) do
          next_row = next_row + direction
        end
        if not selectable(next_row) then
          break
        end
        row = next_row
      end
      api.nvim_win_set_cursor(s.win, { row, 0 })
    end, { buffer = s.buf, silent = true })
  end
  for key, field in pairs({ s = 'search' }) do
    vim.keymap.set('n', key, function()
      local page = s:page()
      if page[field] and not page.busy then
        M.attempt(function()
          page[field](s.rows[api.nvim_win_get_cursor(s.win)[1]])
        end)
      end
    end, { buffer = s.buf, silent = true })
  end
  api.nvim_create_autocmd('CursorMoved', {
    group = s.group,
    buffer = s.buf,
    callback = function()
      if s.closed or not s.win or not api.nvim_win_is_valid(s.win) then
        return
      end
      local row = api.nvim_win_get_cursor(s.win)[1]
      vim.wo[s.win].cursorline = selectable(row) and true or false
      s:page().selected = s.rows[row]
    end,
  })
  api.nvim_create_autocmd('VimResized', {
    group = s.group,
    callback = function()
      if not s.closed and s.win and api.nvim_win_is_valid(s.win) then
        save()
        M.attempt(function()
          s:render(true)
        end)
      end
    end,
  })
  api.nvim_create_autocmd({ 'WinLeave', 'BufWinLeave', 'BufWipeout', 'WinClosed' }, {
    group = s.group,
    callback = function(event)
      if event.event == 'WinLeave' and s.prompt then
        return
      end
      if
        (event.event == 'WinLeave' and api.nvim_get_current_win() == s.win)
        or (event.event == 'WinClosed' and tonumber(event.match) == s.win)
        or (event.event == 'BufWinLeave' and event.buf == s.buf)
        or (event.event == 'BufWipeout' and event.buf == s.buf)
      then
        s:close(true)
      end
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
