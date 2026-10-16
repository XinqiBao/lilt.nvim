local api = vim.api
local lilt = require('lilt')
local render = require('lilt.render')
local checks = 0
local function eq(actual, expected, label)
  checks = checks + 1
  assert(vim.deep_equal(actual, expected), label .. '\nexpected: ' .. vim.inspect(expected) .. '\nactual: ' .. vim.inspect(actual))
end
local function keys(input)
  api.nvim_feedkeys(api.nvim_replace_termcodes(input, true, false, true), 'xt', false)
  vim.wait(10, function() return false end)
end
local function lines(buf)
  return api.nvim_buf_get_lines(buf or 0, 0, -1, false)
end
local function marks(buf)
  return api.nvim_buf_get_extmarks(buf, render.namespace, 0, -1, { details = true })
end
local function pending(buf, row)
  for _, mark in ipairs(marks(buf)) do
    if mark[2] == row and mark[4].virt_text then
      return mark[4].virt_text[1][1]
    end
  end
end
local function error_ranges(buf, row)
  local ranges = {}
  for _, mark in ipairs(marks(buf)) do
    if mark[2] == row and mark[4].hl_group == 'LiltError' then
      ranges[#ranges + 1] = { mark[3], mark[4].end_col }
    end
  end
  return ranges
end

local function run()
  local origin = api.nvim_get_current_win()
  local original = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(original, 0, -1, false, { 'unrelated writing' })
  vim.o.showmode = false
  vim.o.report = 9999
  vim.wo.number, vim.wo.wrap = true, false
  local global_options = { vim.o.laststatus, vim.o.showtabline, vim.o.splitbelow, vim.o.equalalways }
  local buffers_before = #api.nvim_list_bufs()
  local function autocmd_count()
    local ok, result = pcall(api.nvim_get_autocmds, { group = 'LiltSession' })
    return ok and #result or 0
  end
  lilt.ghost()
  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  eq(vim.bo[buf].buftype, '', 'manuscript is an ordinary buffer')
  eq(lines(buf), { '' }, 'no physical placeholders')
  eq(pending(buf, 0), vim.fn.readfile('samples/alice.txt')[1], 'initial first row')
  local initial_marks = marks(buf)
  local reference = vim.fn.readfile('samples/alice.txt')
  eq(#initial_marks[2][4].virt_lines, #reference - 1, 'every future row allocated once')
  local count = autocmd_count()
  keys('iAlice was<CR>So she<Esc>')
  eq(lines(buf), { 'Alice was', 'So she' }, 'native Enter records only actual input')
  eq(pending(buf, 0), reference[1]:sub(10), 'unfinished preceding row survives Enter')
  eq(pending(buf, 1), reference[2]:sub(7), 'second row uses reference index')
  local before_motion = marks(buf)
  keys('gg0w$G0')
  eq(marks(buf), before_motion, 'cursor motion has no effect on comparison')
  keys('gg0ciwAlicia<Esc>')
  eq(lines(buf)[1], 'Alicia was', 'ciw edits real earlier word')
  eq(error_ranges(buf, 0), { { 4, 5 }, { 5, 6 } }, 'aligned errors stop before matching suffix')
  keys('u')
  eq(lines(buf)[1], 'Alice was', 'undo')
  eq(error_ranges(buf, 0), {}, 'undo refreshes error feedback')
  eq(pending(buf, 0), reference[1]:sub(10), 'undo refreshes pending suffix')
  keys('<C-r>')
  eq(lines(buf)[1], 'Alicia was', 'redo')
  keys('gg0x')
  eq(lines(buf)[1], 'licia was', 'x')
  keys('u')
  keys('gg0dw')
  eq(lines(buf)[1], 'was', 'dw')
  keys('u')
  keys('gg0xj0.')
  eq(lines(buf), { 'licia was', 'o she' }, 'dot repeats native change')
  keys('u')
  keys('u')
  keys('GoXY<BS>Z<Esc>')
  eq(lines(buf)[3], 'XZ', 'o creates a physical row')
  keys('dd')
  eq(#lines(buf), 2, 'dd removes row without repairing text')
  keys('u')
  eq(#lines(buf), 3, 'undo restores deleted row')
  keys('G0i<BS><Esc>')
  eq(#lines(buf), 2, 'Backspace at start joins physical lines')
  keys('u')
  api.nvim_buf_set_lines(buf, 0, -1, false, { '“It’s… — yes.”', '', 'Alice' })
  eq(lines(buf), { '“It’s… — yes.”', '', 'Alice' }, 'Unicode and blank paragraph preserved')
  for _, range in ipairs(error_ranges(buf, 0)) do
    local byte = lines(buf)[1]:byte(range[2] + 1)
    eq(byte == nil or byte < 128 or byte >= 192, true, 'Unicode extmark ends on byte boundary')
  end
  local written = lines(buf)
  local cursor = api.nvim_win_get_cursor(win)
  local undo_seq = vim.fn.undotree().seq_cur
  for _ = 1, 8 do
    lilt.split()
    eq(api.nvim_get_current_buf(), buf, 'Split shares buffer')
    eq(#api.nvim_tabpage_list_wins(0), 2, 'two reading windows in Split')
    local refwin
    for _, candidate in ipairs(api.nvim_tabpage_list_wins(0)) do
      if candidate ~= win then refwin = candidate end
    end
    local refbuf = api.nvim_win_get_buf(refwin)
    eq(lines(refbuf), reference, 'ordinary complete reference buffer')
    eq(vim.bo[refbuf].modifiable, false, 'reference protected')
    eq(vim.bo[refbuf].readonly, true, 'reference readonly')
    eq(pending(buf, 0), nil, 'Ghost rendering removed in Split')
    lilt.ghost()
    eq(#api.nvim_tabpage_list_wins(0), 1, 'reference window cleaned up')
    eq(lines(buf), written, 'switching preserves authored text exactly')
    eq(api.nvim_win_get_cursor(win), cursor, 'cursor retained across switching')
    eq(autocmd_count(), count, 'no accumulated autocmds')
  end
  eq(vim.fn.undotree().seq_cur, undo_seq, 'switching adds no undo entries')
  local path = vim.fn.tempname()
  api.nvim_buf_call(buf, function() vim.cmd('write ' .. vim.fn.fnameescape(path)) end)
  eq(vim.fn.readfile(path), written, 'ordinary file contains only authored text')
  vim.fn.writefile({ 'Alice', '', 'So' }, path)
  vim.cmd('edit!')
  vim.wait(10, function() return false end)
  eq(lines(buf), { 'Alice', '', 'So' }, 'file reload remains authoritative')
  eq(pending(buf, 0), reference[1]:sub(6), 'file reload refreshes pending rendering')
  keys('ggA!<Esc>')
  eq(pending(buf, 0), reference[1]:sub(7), 'reload reattaches live edit feedback')
  written = lines(buf)
  lilt.close()
  eq(api.nvim_get_current_win(), origin, 'returns to original window')
  eq(lines(original), { 'unrelated writing' }, 'unrelated buffer intact')
  eq({ vim.wo.number, vim.wo.wrap }, { true, false }, 'original local options intact')
  eq({ vim.o.laststatus, vim.o.showtabline, vim.o.splitbelow, vim.o.equalalways }, global_options, 'global options intact')
  eq(#marks(buf), 0, 'all session extmarks cleared')
  eq(autocmd_count(), 0, 'session autocmds removed')
  eq(#api.nvim_list_bufs(), buffers_before + 1, 'only authored buffer retained')
  lilt.ghost()
  eq(api.nvim_get_current_buf(), buf, 'reopen resumes retained manuscript')
  eq(lines(buf), written, 'reopen keeps writing')
  vim.cmd('tabclose')
  vim.wait(20, function() return false end)
  eq(autocmd_count(), 0, 'manual tab closure cleans session')
  eq(#marks(buf), 0, 'manual tab closure clears decorations')
  lilt.split()
  local reuse_win = api.nvim_get_current_win()
  api.nvim_win_set_buf(reuse_win, original)
  vim.wait(20, function() return false end)
  eq(api.nvim_win_is_valid(reuse_win), true, 'repurposed window survives cleanup')
  eq(api.nvim_win_get_buf(reuse_win), original, 'repurposed content survives cleanup')
  eq(vim.wo[reuse_win].number, true, 'repurposed window options restored')
  eq(autocmd_count(), 0, 'replacing manuscript cleans session')
  api.nvim_win_close(reuse_win, true)
  lilt.ghost()
  vim.cmd('vsplit')
  local extra_win = api.nvim_get_current_win()
  api.nvim_win_set_buf(extra_win, original)
  lilt.close()
  eq(api.nvim_win_is_valid(extra_win), true, 'user-created window survives close')
  eq(lines(original), { 'unrelated writing' }, 'user-created window content intact')
  api.nvim_win_close(extra_win, true)
  lilt.ghost()
  api.nvim_win_close(origin, true)
  lilt.close()
  eq(api.nvim_buf_is_valid(buf), true, 'closing final tab retains manuscript')
  eq(api.nvim_get_current_buf(), buf, 'final editor window remains usable')
  eq(vim.wo.number, true, 'final window options restored')
  eq(autocmd_count(), 0, 'final window session cleaned')
  api.nvim_buf_delete(buf, { force = true })
  lilt.ghost()
  local fresh = api.nvim_get_current_buf()
  eq(fresh ~= buf, true, 'explicit manuscript wipe starts a fresh buffer')
  keys('iAlice<Esc>')
  eq(pending(fresh, 0), reference[1]:sub(6), 'fresh manuscript has a live renderer')
  lilt.close()
  vim.fn.delete(path)
  print(('Lilt: %d assertions passed on %s'):format(checks, tostring(vim.version())))
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
