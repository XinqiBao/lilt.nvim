-- Picker presentation and lifetime. Pages contain information and actions;
-- the cursor can browse both, but only actions activate.
-- Reading resources never live here.
local api = vim.api
local preview = require('lilt.picker.preview')
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
  local s =
    { pages = {}, buf = api.nvim_create_buf(false, true), rows = {}, preview = preview.new() }
  s.group = api.nvim_create_augroup('LiltPicker', { clear = true })
  vim.bo[s.buf].bufhidden = 'hide'
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
    if self.input and api.nvim_get_current_win() == self.win then
      vim.cmd.stopinsert()
    end
    api.nvim_del_augroup_by_id(self.group)
    on_close()
    local function cleanup()
      self.preview:close()
      if self.win and api.nvim_win_is_valid(self.win) then
        api.nvim_win_close(self.win, true)
      end
      for _, buf in ipairs({ self.buf, self.input and self.input.buf }) do
        if api.nvim_buf_is_valid(buf) then
          api.nvim_buf_delete(buf, { force = true })
        end
      end
    end
    if defer then
      vim.schedule(cleanup)
    else
      cleanup()
    end
  end

  local function actionable(row)
    return s.rows[row] and s.rows[row].select and not s:page().busy
  end

  -- Keep a position within an item when wrapped metadata reflows on resize.
  local function remember()
    local page = s:page()
    local row = api.nvim_win_get_cursor(s.win)[1]
    page.selected, page.offset = s.rows[row], 0
    while row > 1 and s.rows[row - 1] == page.selected do
      page.offset = page.offset + 1
      row = row - 1
    end
  end

  function s:render(restore)
    if self.closed then
      return
    end
    local page = self:page()
    local available = math.max(1, vim.o.columns - 4)
    local room = math.max(1, vim.o.lines - vim.o.cmdheight - 4)
    local side = page.preview and available >= 100 and room >= 8
    local total = side and math.min(120, available) or math.min(76, available)
    local width = side and math.floor(total * 0.44) or total
    if self.input then
      self.preview:close()
      api.nvim_win_set_config(self.win, {
        relative = 'editor',
        width = width,
        height = 1,
        row = math.max(0, math.floor((vim.o.lines - vim.o.cmdheight - 3) / 2)),
        col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
        title = clip(' Search title or author ', width),
        footer = clip(' Enter search · Esc cancel ', width),
      })
      return
    end
    for _, key in ipairs(self.shortcuts or {}) do
      vim.keymap.del('n', key, { buffer = self.buf })
    end
    self.shortcuts = {}
    local lines, marks, selected, selected_end = {}, {}, nil, nil
    self.rows = {}
    local function row(text, item)
      lines[#lines + 1] = text
      self.rows[#lines] = item
      if item == page.selected then
        selected, selected_end = selected or #lines, #lines
      end
      if item.hl or not item.select then
        marks[#marks + 1] = { #lines - 1, item.hl or 'Comment' }
      end
    end
    local items = vim.list_extend(vim.list_slice(page.items), page.status or {})
    for _, item in ipairs(items) do
      local indent = item.select and '    ' or '  '
      if item.key then
        self.shortcuts[#self.shortcuts + 1] = item.key
        vim.keymap.set('n', item.key, function()
          if not page.busy then
            M.attempt(item.select)
          end
        end, { buffer = self.buf, silent = true })
        local hint = item.key:match('%w') and ('[' .. item.key .. ']') or item.key
        indent = indent .. hint .. ' '
      end
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
    if selected then
      selected = math.min(selected + (page.offset or 0), selected_end)
    end
    page.height = page.height or #lines
    local height = math.min(page.height, room)
    local below = page.preview and not side and available >= 44 and room >= 14
    if below then
      height = math.min(height, math.max(6, math.floor(math.min(room, 20) * 0.6)))
    end
    local row_pos = math.max(
      0,
      math.floor((vim.o.lines - vim.o.cmdheight - (below and math.min(room, 20) or height) - 2) / 2)
    )
    local col_pos = math.max(0, math.floor((vim.o.columns - total - 2) / 2))
    self.preview_config = side
        and {
          row = row_pos,
          col = col_pos + width + 2,
          width = total - width - 2,
          height = height,
        }
      or below and {
        row = row_pos + height + 2,
        col = col_pos,
        width = width,
        height = math.max(1, math.min(room, 20) - height - 2),
      }
      or nil
    local footer = ' Enter select · h/BS back · q/Esc quit '
    if width < 50 then
      footer = width < 30 and ' h back · q quit ' or ' Enter · h back · q/Esc quit '
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
      row = row_pos,
      col = col_pos,
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
    api.nvim_win_call(self.win, function()
      -- Pages share a window, but a new page must not inherit its scroll.
      vim.fn.winrestview(restore and page.view or { topline = 1, leftcol = 0 })
    end)
    if not selected then
      for i in ipairs(lines) do
        if actionable(i) then
          selected = i
          break
        end
      end
    end
    api.nvim_win_set_cursor(self.win, { selected or 1, 0 })
    self:update_cursor()
  end

  function s:update_cursor()
    remember()
    vim.wo[self.win].cursorline = actionable(api.nvim_win_get_cursor(self.win)[1]) and true or false
    self.preview:show(self:page().selected, self.preview_config)
  end

  local function save()
    local page = s:page()
    if page and s.win and api.nvim_win_is_valid(s.win) then
      remember()
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
            key = 'r',
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

  -- A single ordinary editable line in the existing float. Keep path input on
  -- vim.ui.input: Neovim's directory completion is more useful there.
  function s:search(default, callback)
    save()
    local buf = api.nvim_create_buf(false, true)
    self.input = { buf = buf }
    api.nvim_buf_set_lines(buf, 0, -1, false, { default })
    api.nvim_win_set_buf(self.win, buf)
    self:render()
    vim.wo[self.win].cursorline = false
    local function finish(submit)
      local value = api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      vim.cmd.stopinsert()
      self.input = nil
      api.nvim_win_set_buf(self.win, self.buf)
      api.nvim_buf_delete(buf, { force = true })
      self:render(true)
      if submit then
        callback(vim.trim(value))
      end
    end
    for _, mode in ipairs({ 'n', 'i' }) do
      vim.keymap.set(mode, '<CR>', function()
        M.attempt(function()
          finish(true)
        end)
      end, { buffer = buf })
      for _, key in ipairs({ '<Esc>', '<C-c>' }) do
        vim.keymap.set(mode, key, function()
          finish(false)
        end, { buffer = buf })
      end
    end
    api.nvim_win_set_cursor(self.win, { 1, #default })
    vim.cmd.startinsert({ bang = true })
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
  for _, key in ipairs({ '<CR>', 'l', '<Right>' }) do
    vim.keymap.set('n', key, function()
      activate()
    end, { buffer = s.buf, silent = true })
  end
  for _, key in ipairs({ 'h', '<BS>', '<Left>' }) do
    vim.keymap.set('n', key, function()
      s:back()
    end, { buffer = s.buf, silent = true })
  end
  for _, key in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', key, function()
      s:close()
    end, { buffer = s.buf, silent = true })
  end
  for key, motion in pairs({
    j = 'j',
    k = 'k',
    ['<Down>'] = 'j',
    ['<Up>'] = 'k',
    gg = 'gg',
    G = 'G',
  }) do
    vim.keymap.set('n', key, function()
      -- Preserve native counts and scrolling, then synchronize immediately;
      -- CursorMoved may be deferred while Neovim processes a batch of input.
      vim.cmd('normal! ' .. (vim.v.count > 0 and tostring(vim.v.count) or '') .. motion)
      M.attempt(function()
        s:update_cursor()
      end)
    end, { buffer = s.buf, silent = true })
  end
  api.nvim_create_autocmd('CursorMoved', {
    group = s.group,
    buffer = s.buf,
    callback = function()
      if s.closed or not s.win or not api.nvim_win_is_valid(s.win) or s.input then
        return
      end
      M.attempt(function()
        s:update_cursor()
      end)
    end,
  })
  api.nvim_create_autocmd('VimResized', {
    group = s.group,
    callback = function()
      if not s.closed and s.win and api.nvim_win_is_valid(s.win) then
        if not s.input then
          save()
        end
        M.attempt(function()
          s:render(true)
        end)
      end
    end,
  })
  api.nvim_create_autocmd({ 'WinLeave', 'BufWinLeave', 'BufWipeout', 'WinClosed' }, {
    group = s.group,
    callback = function(event)
      if
        (event.event == 'WinLeave' and api.nvim_get_current_win() == s.win)
        or (event.event == 'WinClosed' and (tonumber(event.match) == s.win or tonumber(event.match) == s.preview.win))
        -- Search intentionally hides the menu; finish clears input ownership
        -- before restoring it. Other buffer replacements dismiss the picker.
        or (event.event == 'BufWinLeave' and ((event.buf == s.buf and not s.input) or event.buf == s.preview.buf or (s.input and event.buf == s.input.buf)))
        or (
          event.event == 'BufWipeout'
          and (
            event.buf == s.buf
            or event.buf == s.preview.buf
            or (s.input and event.buf == s.input.buf)
          )
        )
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
