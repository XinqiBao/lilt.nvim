local api = vim.api
local render = require('lilt.render')
local ghost = require('lilt.view.ghost')
local split = require('lilt.view.split')
local compare = require('lilt.compare')
local M = {}
local session, manuscript
local attached = {}
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')

local function highlights()
  api.nvim_set_hl(0, 'LiltPending', { default = true, link = 'Comment' })
  api.nvim_set_hl(0, 'LiltError', { default = true, link = 'DiagnosticError' })
  api.nvim_set_hl(0, 'LiltExtra', { default = true, link = 'DiagnosticWarn' })
  api.nvim_set_hl(0, 'LiltMissing', { default = true, link = 'DiagnosticUnderlineWarn' })
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

-- Save options against the actual window that owns them, before changing it.
local function present(s, win, values)
  s.options[win] = s.options[win] or {}
  for name, value in pairs(values) do
    if s.options[win][name] == nil then
      s.options[win][name] = api.nvim_get_option_value(name, { win = win })
    end
    api.nvim_set_option_value(name, value, { win = win })
  end
end

local function draw(s)
  if not api.nvim_buf_is_loaded(s.manuscript) then return end
  local lines = api.nvim_buf_get_lines(s.manuscript, 0, -1, false)
  local results = {}
  for row = 1, math.max(#lines, #s.reference) do
    results[row] = compare.line(s.reference[row] or '', lines[row] or '')
  end
  render.clear(s.manuscript)
  if s.view == 'ghost' then ghost.draw(s, lines, results)
  else split.draw(s, lines, results) end
end

local function attach_manuscript(buf)
  if attached[buf] then
    return
  end
  attached[buf] = api.nvim_buf_attach(buf, false, {
    on_lines = function(_, changed)
      if session and session.manuscript == changed then
        draw(session)
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

function M.close()
  local s = session
  if not s then
    return
  end
  session = nil
  if s.group then api.nvim_del_augroup_by_id(s.group) end
  render.clear(s.manuscript)
  local current = api.nvim_get_current_win()
  local was_owned = current == s.user_win or current == s.reference_win
  ghost.leave(s)
  split.leave(s)
  if s.user_win and api.nvim_win_is_valid(s.user_win) then
    if not s.view or api.nvim_win_get_buf(s.user_win) == s.manuscript then
      if not pcall(api.nvim_win_close, s.user_win, true) then
        s.restore(s.user_win)
      end
    else
      s.restore(s.user_win)
    end
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
  if s.view == 'split' and (not s.reference_win or not api.nvim_win_is_valid(s.reference_win)
    or api.nvim_win_get_buf(s.reference_win) ~= s.reference_buf) then
    M.close()
    return
  end
  api.nvim_set_current_win(s.user_win)
  if s.view == view then return end
  ghost.leave(s)
  split.leave(s)
  s.view = view
  if view == 'ghost' then ghost.enter(s)
  else split.enter(s) end
  draw(s)
end

local function start(view)
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
  local s = {
    manuscript = manuscript, reference = reference, width = width,
    origin_win = origin, options = {},
  }
  s.present = function(target, values) present(s, target, values) end
  s.restore = function(target)
    window_options(target, s.options[target] or {})
    s.options[target] = nil
  end
  s.quiet = quiet
  session = s
  -- Even :tab split can allocate its window before reporting E36.
  local ok, err = pcall(vim.cmd, 'tab split')
  local win = api.nvim_get_current_win()
  if win ~= origin then s.user_win = win end
  if not ok then error(err, 0) end
  s.group = api.nvim_create_augroup('LiltSession', { clear = true })
  s.present(win, quiet)
  for _, name in ipairs({ 'wrap', 'linebreak', 'statusline' }) do
    s.options[win][name] = api.nvim_get_option_value(name, { win = win })
  end
  api.nvim_win_set_buf(win, manuscript)
  s.present(win, quiet)
  api.nvim_create_autocmd('ColorScheme', { group = s.group, callback = highlights })
  -- :edit! detaches Lua buffer callbacks; resume after the file has loaded.
  api.nvim_create_autocmd('BufReadPost', {
    group = s.group,
    callback = function(event)
      if session == s and event.buf == s.manuscript then
        attach_manuscript(s.manuscript)
        draw(s)
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
  set_view(view)
end

local function open(view)
  local ok, err = xpcall(function() start(view) end, debug.traceback)
  if not ok then
    -- Creation can fail after allocating only some resources (e.g. E36).
    -- Terminate the session, retaining the manuscript and the original error.
    pcall(M.close)
    error(err, 0)
  end
end

function M.ghost()
  open('ghost')
end

function M.split()
  open('split')
end

return M
