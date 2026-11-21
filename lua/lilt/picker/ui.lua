-- Picker presentation and lifetime. Pages contain information and actions;
-- the cursor can browse both, but only actions activate.
-- Reading resources never live here.
local api = vim.api
local preview = require('lilt.picker.preview')
local M = {}
local namespace = api.nvim_create_namespace('lilt.picker')

local function blocked(page)
  return page.busy and page.blocking ~= false
end

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

-- Full labels must remain readable even without word boundaries (URLs,
-- CJK titles). Split at UTF-8 boundaries, preferring spaces when they fit.
local function full_wrap(text, width)
  -- Paths and diagnostics may contain controls; buffer rows must not.
  text = text:gsub('%c', ' ')
  if text == '' then
    return { '' }
  end
  local lines = {}
  while text ~= '' do
    local bytes = 0
    for char in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
      if bytes > 0 and vim.fn.strdisplaywidth(text:sub(1, bytes) .. char) > width then
        break
      end
      bytes = bytes + #char
    end
    local part = text:sub(1, bytes)
    local space = bytes < #text and part:match('^.*()%s')
    if space and space > 1 then
      lines[#lines + 1], text = part:sub(1, space - 1), text:sub(space + 1)
    else
      lines[#lines + 1], text = part, text:sub(bytes + 1)
    end
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
    local page = self:page()
    if page then
      page.generation = nil
    end
    if self.cancel_request then
      local cancel = self.cancel_request
      self.cancel_request = nil
      cancel()
      if page and page.cancelled then
        page.cancelled()
      end
    end
    if page then
      page.busy, page.status = nil, nil
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
    return s.rows[row] and s.rows[row].select and not blocked(s:page())
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
      local value = api.nvim_buf_get_lines(self.input.buf, 0, 1, false)[1] or ''
      if self.input.error and self.input.error.value ~= value then
        self.input.error = nil
      end
      local details = {}
      if self.input.options.preview then
        details[#details + 1] = {
          { clip('→ ' .. self.input.options.preview(value), width), 'Comment' },
        }
      end
      if self.input.error then
        for _, line in ipairs(wrap(self.input.error.message, width, 3)) do
          details[#details + 1] = { { clip(line, width), 'DiagnosticError' } }
        end
      end
      while #details > room - 1 do
        table.remove(details)
      end
      api.nvim_buf_clear_namespace(self.input.buf, namespace, 0, -1)
      if #details > 0 then
        api.nvim_buf_set_extmark(self.input.buf, namespace, 0, 0, { virt_lines = details })
      end
      local height = 1 + #details
      api.nvim_win_set_config(self.win, {
        relative = 'editor',
        width = width,
        height = height,
        row = math.max(0, math.floor((vim.o.lines - vim.o.cmdheight - height - 2) / 2)),
        col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
        title = clip(' ' .. self.input.options.title .. ' ', width),
        footer = clip(
          ' '
            .. (self.input.error and #details == 0 and self.input.error.message or self.input.options.footer)
            .. ' ',
          width
        ),
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
    local trailing_width = page.trailing_width or 0
    -- Keep at least 48 content columns, plus the action indent and a two-column gap.
    local trailing = trailing_width > 0 and width >= 4 + 48 + 2 + trailing_width
    for _, item in ipairs(items) do
      local depth = math.min(item.depth or 0, math.max(0, math.floor((width - 24) / 2)))
      local indent = (item.select and '    ' or '  ') .. string.rep('  ', depth)
      if item.key then
        self.shortcuts[#self.shortcuts + 1] = item.key
        vim.keymap.set('n', item.key, function()
          if not blocked(page) then
            M.attempt(item.select)
          end
        end, { buffer = self.buf, silent = true })
        local hint = item.key:match('%w') and ('[' .. item.key .. ']') or item.key
        indent = indent .. hint .. ' '
      end
      if item.wrap == 'full' then
        local reserved = trailing and item.trailing and trailing_width + 2 or 0
        local content_width = math.max(1, width - vim.fn.strdisplaywidth(indent) - reserved)
        for i, text in ipairs(full_wrap(item.label, content_width)) do
          local label = indent .. text
          if i == 1 and reserved > 0 then
            label = label
              .. string.rep(
                ' ',
                width - vim.fn.strdisplaywidth(label) - vim.fn.strdisplaywidth(item.trailing)
              )
            local start = #label
            label = label .. item.trailing
            row(label, item)
            marks[#marks + 1] = { #lines - 1, 'Comment', start, #label }
          else
            row(label, item)
          end
        end
      elseif item.wrap then
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
      if page.blocking == false then
        footer = width < 40 and ' Loading… · s search · h back '
          or ' Loading… · s search · h back · q/Esc quit '
      else
        footer = width < 40 and ' Working · q/Esc cancels ' or (' ' .. page.status[1].label .. ' ')
      end
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
      api.nvim_buf_set_extmark(
        self.buf,
        namespace,
        mark[1],
        mark[3] or 0,
        mark[3] and { hl_group = mark[2], end_col = mark[4] } or { line_hl_group = mark[2] }
      )
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
    if page and not s.input and s.win and api.nvim_win_is_valid(s.win) then
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

  function s:request(page, start, done, message, update)
    save()
    self:cancel()
    local generation = {}
    page.generation, page.busy = generation, true
    page.status = update and page.blocking == false and {} or { { label = message } }
    self:render(true)
    local function current()
      return not self.closed and self:page() == page and page.generation == generation
    end
    local completed = false
    local cancel = start(function(err, value)
      if not current() then
        return
      end
      save()
      completed = true
      page.generation = nil
      self.cancel_request, page.busy, page.status = nil, nil, nil
      M.attempt(function()
        if err then
          local retry = {
            key = 'r',
            label = 'Request failed — retry',
            select = function()
              self:request(page, start, done, message, update)
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
    end, function(value)
      if current() and update then
        save()
        M.attempt(function()
          update(value)
        end)
      end
    end)
    if current() then
      self.cancel_request = cancel
    elseif not completed then
      -- Startup progress can navigate or close before start returns its cancel.
      cancel()
      if page.cancelled then
        page.cancelled()
      end
    end
  end

  -- Input semantics belong to the caller; presentation and completion stay
  -- within the picker lifetime rather than replacing the global vim.ui.
  function s:prompt(options, callback)
    save()
    local buf = api.nvim_create_buf(false, true)
    self.input = { buf = buf, options = options }
    -- Input stays on one line regardless of the user's prose formatting.
    vim.bo[buf].textwidth = 0
    vim.bo[buf].wrapmargin = 0
    vim.bo[buf].formatoptions = ''
    api.nvim_buf_set_lines(buf, 0, -1, false, { options.default })
    api.nvim_win_set_buf(self.win, buf)
    self:render()
    vim.wo[self.win].cursorline = false
    local function finish(submit)
      local value = api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      if submit and options.validate then
        local ok, result = pcall(options.validate, value)
        if not ok then
          self.input.error = { value = value, message = tostring(result):gsub('^.-Lilt: ', '') }
          self:render()
          return
        end
        value = result
      end
      self.input = nil
      api.nvim_win_set_buf(self.win, self.buf)
      api.nvim_buf_delete(buf, { force = true })
      self:render(true)
      if submit then
        M.attempt(function()
          callback(value)
        end)
      end
      -- A submitted path may open the naming editor immediately. Keep Insert
      -- mode across that handoff; stopinsert would override its startinsert.
      if not self.input then
        vim.cmd.stopinsert()
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
    if options.complete then
      vim.bo[buf].completeopt = 'menu,menuone'
      local function keys(value)
        api.nvim_feedkeys(api.nvim_replace_termcodes(value, true, false, true), 'in', false)
      end
      for key, motion in pairs({ ['<Tab>'] = '<C-n>', ['<S-Tab>'] = '<C-p>' }) do
        vim.keymap.set('i', key, function()
          if vim.fn.pumvisible() == 1 then
            keys(motion)
          else
            local value = api.nvim_buf_get_lines(buf, 0, 1, false)[1]
            local column = api.nvim_win_get_cursor(self.win)[2]
            vim.fn.complete(1, options.complete(value:sub(1, column)))
          end
        end, { buffer = buf })
      end
      vim.keymap.set('i', '<CR>', function()
        if vim.fn.pumvisible() == 1 then
          keys('<C-y>')
        else
          M.attempt(function()
            finish(true)
          end)
        end
      end, { buffer = buf })
    end
    api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
      group = self.group,
      buffer = buf,
      callback = function()
        if not self.closed and self.input and self.input.buf == buf then
          self:render()
        end
      end,
    })
    api.nvim_win_set_cursor(self.win, { 1, #options.default })
    vim.cmd.startinsert({ bang = true })
  end

  function s:search(default, callback)
    self:prompt(
      { title = 'Search title or author', default = default, footer = 'Enter search · Esc cancel' },
      function(value)
        callback(vim.trim(value))
      end
    )
  end

  local function activate()
    M.attempt(function()
      local page = s:page()
      local item = s.rows[api.nvim_win_get_cursor(s.win)[1]]
      if item and item.select and not blocked(page) then
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
