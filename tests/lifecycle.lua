local api = vim.api
local lilt = require('lilt')
local namespace = require('lilt.render').namespace

local function no_resources(buf)
  for _, group in ipairs({ 'LiltSession', 'LiltGhost' }) do
    assert(not pcall(api.nvim_get_autocmds, { group = group }), group .. ' leaked')
  end
  for _, candidate in ipairs(api.nvim_list_bufs()) do
    assert(not api.nvim_buf_get_name(candidate):match('^lilt://'), 'reference buffer leaked')
  end
  assert(#api.nvim_buf_get_extmarks(buf, namespace, 0, -1, {}) == 0, 'decorations leaked')
end

local baseline = {
  number = true,
  relativenumber = true,
  signcolumn = 'yes',
  foldcolumn = '1',
  foldenable = true,
  cursorline = true,
  cursorcolumn = true,
  list = true,
  spell = true,
  colorcolumn = '80',
  conceallevel = 2,
  scrollbind = false,
  cursorbind = false,
  winbar = 'editor',
  sidescrolloff = 3,
  wrap = false,
  linebreak = false,
  statusline = 'editor status',
}
local function restored(win)
  for name, value in pairs(baseline) do
    assert(api.nvim_get_option_value(name, { win = win }) == value, name .. ' not restored')
  end
end

local function run()
  local origin = api.nvim_get_current_win()
  for name, value in pairs(baseline) do
    api.nvim_set_option_value(name, value, { win = origin })
  end
  local function failure(from_ghost)
    if from_ghost then
      lilt.ghost()
    end
    vim.o.winheight = 20
    vim.o.winminheight = 20
    local ok, err = pcall(lilt.split)
    vim.o.winminheight = 1
    vim.o.winheight = 1
    assert(not ok and err:find('E36: Not enough room', 1, true), tostring(err))
    local buf
    for _, candidate in ipairs(api.nvim_list_bufs()) do
      if vim.b[candidate].lilt_manuscript then
        buf = candidate
      end
    end
    assert(buf and api.nvim_buf_is_valid(buf), 'failed creation lost manuscript')
    if from_ghost then
      assert(
        api.nvim_buf_get_lines(buf, 0, -1, false)[1] == 'retained writing',
        'failed switch lost writing'
      )
    end
    no_resources(buf)
    assert(#api.nvim_list_tabpages() == 1, 'failed creation leaked tab')
    restored(origin)
    lilt.ghost()
    assert(api.nvim_get_current_buf() == buf, 'cannot resume failed session')
    api.nvim_buf_set_lines(buf, 0, -1, false, { 'retained writing' })
    lilt.close()
    assert(
      api.nvim_buf_get_lines(buf, 0, -1, false)[1] == 'retained writing',
      'cleanup lost writing'
    )
  end
  failure(false)
  failure(true)

  -- Reference can become the final editor window; it must show the retained
  -- manuscript with the editor's original options, regardless of entry view.
  for _, ghost_first in ipairs({ false, true }) do
    if ghost_first then
      lilt.ghost()
    end
    lilt.split()
    local user = api.nvim_get_current_win()
    local buf = api.nvim_get_current_buf()
    local ref
    for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
      if win ~= user then
        ref = win
      end
    end
    api.nvim_win_close(origin, true)
    api.nvim_win_close(user, true)
    assert(
      vim.wait(1000, function()
        return not pcall(api.nvim_get_autocmds, { group = 'LiltSession' })
      end),
      'session cleanup timed out'
    )
    assert(
      api.nvim_get_current_win() == ref and api.nvim_win_get_buf(ref) == buf,
      'final window lost manuscript'
    )
    restored(ref)
    no_resources(buf)
    origin = ref
  end
  print('Lilt lifecycle: failure recovery and final-window restoration passed')
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.write(err .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
