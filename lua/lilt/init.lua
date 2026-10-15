local api = vim.api
local render = require('lilt.render')
local M = {}
local session, manuscript
local attached = {}
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')

local function highlights()
  api.nvim_set_hl(0, 'LiltPending', { default = true, link = 'Comment' })
  api.nvim_set_hl(0, 'LiltError', { default = true, link = 'SpellBad' })
end

local function window_options(win, values)
  for name, value in pairs(values) do
    api.nvim_set_option_value(name, value, { win = win })
  end
end

local quiet = {
  number = false, relativenumber = false, signcolumn = 'no', foldcolumn = '0',
  foldenable = false, cursorline = false, cursorcolumn = false, list = false,
  spell = false, colorcolumn = '', conceallevel = 0, scrollbind = false,
  cursorbind = false, winbar = '', sidescrolloff = 0,
}

local function remember_options(win)
  local saved = {}
  for name in pairs(quiet) do
    saved[name] = api.nvim_get_option_value(name, { win = win })
  end
  for _, name in ipairs({ 'wrap', 'linebreak', 'statusline' }) do
    saved[name] = api.nvim_get_option_value(name, { win = win })
  end
  return saved
end

local function usable_width(win)
  return api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff
end

local function attach_manuscript(buf)
  if attached[buf] then
    return
  end
  attached[buf] = api.nvim_buf_attach(buf, false, {
    on_lines = function(_, changed)
      if session and session.manuscript == changed then
        render.draw(session)
      end
    end,
    on_detach = function()
      attached[buf] = nil
    end,
  })
end

local function new_manuscript()
  local buf = api.nvim_create_buf(true, false)
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].filetype = 'text'
  -- Explicit physical line breaks, with no automatic formatting or indentation.
  for name, value in pairs({
    textwidth = 0, wrapmargin = 0, formatoptions = '', autoindent = false,
    smartindent = false, cindent = false, indentexpr = '',
  }) do
    api.nvim_set_option_value(name, value, { buf = buf })
  end
  vim.b[buf].lilt_manuscript = true
  return buf
end

local function close_reference(s)
  if s.reference_win and api.nvim_win_is_valid(s.reference_win) then
    if api.nvim_win_get_buf(s.reference_win) == s.reference_buf then
      local ok = pcall(api.nvim_win_close, s.reference_win, true)
      if not ok then
        api.nvim_win_set_buf(s.reference_win, s.manuscript)
        window_options(s.reference_win, s.saved_options)
      end
    else
      window_options(s.reference_win, s.saved_options)
    end
  end
  s.reference_win = nil
end

function M.close()
  local s = session
  if not s then
    return
  end
  session = nil
  api.nvim_del_augroup_by_id(s.group)
  render.clear(s.manuscript)
  local current = api.nvim_get_current_win()
  local was_owned = current == s.user_win or current == s.reference_win
  close_reference(s)
  if api.nvim_win_is_valid(s.user_win) then
    if api.nvim_win_get_buf(s.user_win) == s.manuscript then
      if not pcall(api.nvim_win_close, s.user_win, true) then
        window_options(s.user_win, s.saved_options)
      end
    else
      window_options(s.user_win, s.saved_options)
    end
  end
  if s.reference_buf and api.nvim_buf_is_valid(s.reference_buf) then
    api.nvim_buf_delete(s.reference_buf, { force = true })
  end
  if was_owned and api.nvim_win_is_valid(s.origin_win) then
    api.nvim_set_current_win(s.origin_win)
  end
  -- The ordinary, listed manuscript buffer survives, including its undo tree.
end

local function set_view(view)
  local s = session
  if not api.nvim_win_is_valid(s.user_win) or api.nvim_win_get_buf(s.user_win) ~= s.manuscript then
    M.close()
    return
  end
  api.nvim_set_current_win(s.user_win)
  close_reference(s)
  local narrow = view == 'ghost' and usable_width(s.user_win) < s.width
  if narrow then
    view = 'split'
  end
  s.view = view
  if view == 'ghost' and s.reference_buf then
    api.nvim_buf_delete(s.reference_buf, { force = true })
    s.reference_buf = nil
  end
  window_options(s.user_win, {
    wrap = view == 'split', linebreak = true,
    statusline = narrow and (' Lilt · Split (Ghost needs %d cols) %%m'):format(s.width)
      or (' Lilt · ' .. (view == 'ghost' and 'Ghost' or 'Manuscript') .. ' %m'),
  })
  if view == 'split' then
    if not s.reference_buf then
      s.reference_buf = api.nvim_create_buf(false, true)
      api.nvim_buf_set_name(s.reference_buf, 'lilt://reference/alice')
      api.nvim_buf_set_lines(s.reference_buf, 0, -1, false, s.reference)
      vim.bo[s.reference_buf].filetype = 'text'
      vim.bo[s.reference_buf].modifiable = false
      vim.bo[s.reference_buf].readonly = true
    end
    -- Above/below keeps the prepared prose readable on ordinary terminals.
    vim.cmd('aboveleft split')
    s.reference_win = api.nvim_get_current_win()
    api.nvim_win_set_buf(s.reference_win, s.reference_buf)
    window_options(s.reference_win, quiet)
    window_options(s.reference_win, { wrap = true, linebreak = true, statusline = ' Lilt · Reference ' })
    api.nvim_set_current_win(s.user_win)
  end
  render.draw(s)
end

local function open(view)
  if vim.fn.has('nvim-0.11') == 0 then
    error('Lilt requires Neovim 0.11 or newer')
  end
  if session then
    set_view(view)
    return
  end
  highlights()
  local reference = vim.fn.readfile(root .. '/samples/alice.txt')
  if not manuscript or not api.nvim_buf_is_valid(manuscript) then
    manuscript = new_manuscript()
  end
  vim.fn.bufload(manuscript)
  attach_manuscript(manuscript)
  local width = 1
  for _, line in ipairs(reference) do
    width = math.max(width, vim.fn.strdisplaywidth(line) + 1)
  end
  local origin = api.nvim_get_current_win()
  vim.cmd('tab split')
  local win = api.nvim_get_current_win()
  local s = {
    manuscript = manuscript, reference = reference, width = width,
    origin_win = origin, user_win = win, saved_options = remember_options(win),
    group = api.nvim_create_augroup('LiltSession', { clear = true }),
  }
  session = s
  api.nvim_win_set_buf(win, manuscript)
  window_options(win, quiet)
  api.nvim_create_autocmd('ColorScheme', { group = s.group, callback = highlights })
  -- :edit! detaches Lua buffer callbacks; resume after the file has loaded.
  api.nvim_create_autocmd('BufReadPost', {
    group = s.group,
    callback = function(event)
      if event.buf == s.manuscript then
        attach_manuscript(s.manuscript)
        render.draw(s)
      end
    end,
  })
  api.nvim_create_autocmd({ 'WinClosed', 'BufWinEnter', 'BufWinLeave' }, {
    group = s.group,
    callback = function()
      vim.schedule(function()
        if session ~= s then
          return
        end
        if not api.nvim_win_is_valid(s.user_win) or api.nvim_win_get_buf(s.user_win) ~= s.manuscript then
          M.close()
        elseif s.view == 'split' and (not s.reference_win or not api.nvim_win_is_valid(s.reference_win)
          or api.nvim_win_get_buf(s.reference_win) ~= s.reference_buf) then
          M.close()
        end
      end)
    end,
  })
  api.nvim_create_autocmd({ 'VimResized', 'WinResized' }, {
    group = s.group,
    callback = function()
      if session == s and s.view == 'ghost' and api.nvim_win_is_valid(win) and usable_width(win) < s.width then
        -- Window changes are deferred out of Neovim's resize event.
        vim.schedule(function()
          if session == s and s.view == 'ghost' and api.nvim_win_is_valid(win) and usable_width(win) < s.width then
            set_view('ghost')
          end
        end)
      end
    end,
  })
  set_view(view)
end

function M.ghost()
  open('ghost')
end

function M.split()
  open('split')
end

return M
