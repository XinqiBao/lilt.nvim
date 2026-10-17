local api = vim.api
local lilt = require('lilt')
local manuscript
local function open(view)
  if not manuscript or not vim.api.nvim_buf_is_valid(manuscript) then
    manuscript = require('lilt.manuscript').open()
  end
  require('lilt.session').open(view or 'ghost', {
    manuscript = manuscript,
    reference = vim.fn.readfile('samples/alice.txt'),
  })
end

local render = require('lilt.render')
local checks = 0
local function eq(actual, expected, label)
  checks = checks + 1
  assert(
    vim.deep_equal(actual, expected),
    label .. '\nexpected: ' .. vim.inspect(expected) .. '\nactual: ' .. vim.inspect(actual)
  )
end
local function keys(input)
  api.nvim_feedkeys(api.nvim_replace_termcodes(input, true, false, true), 'xt', false)
  vim.wait(10, function()
    return false
  end)
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
    if mark[2] == row and (mark[4].hl_group == 'LiltError' or mark[4].hl_group == 'LiltExtra') then
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
  local global_options =
    { vim.o.laststatus, vim.o.showtabline, vim.o.splitbelow, vim.o.equalalways }
  local buffers_before = #api.nvim_list_bufs()
  local function autocmd_count()
    local ok, result = pcall(api.nvim_get_autocmds, { group = 'LiltSession' })
    return ok and #result or 0
  end
  open()
  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  eq(vim.bo[buf].buftype, '', 'manuscript is an ordinary buffer')
  eq(lines(buf), { '' }, 'no physical placeholders')
  eq(pending(buf, 0), vim.fn.readfile('samples/alice.txt')[1], 'initial first row')
  local initial_marks = marks(buf)
  local reference = vim.fn.readfile('samples/alice.txt')
  eq(#initial_marks[2][4].virt_lines, #reference - 1, 'every future row allocated once')
  local count = autocmd_count()
  api.nvim_buf_set_lines(buf, 0, -1, false, { 'Aice' })
  eq(pending(buf, 0), reference[1]:sub(6), 'missing character advances aligned coverage')
  eq(lines(buf), { 'Aice' }, 'missing character never inserts a placeholder')
  local omission
  for _, mark in ipairs(marks(buf)) do
    if mark[4].hl_group == 'LiltMissing' then
      omission = mark
    end
  end
  eq(
    { omission[3], omission[4].end_col, omission[4].hl_group },
    { 1, 2, 'LiltMissing' },
    'Ghost underlines next real character at omission'
  )
  open('split')
  local refwin
  for _, candidate in ipairs(api.nvim_tabpage_list_wins(0)) do
    if candidate ~= win then
      refwin = candidate
    end
  end
  local refbuf = api.nvim_win_get_buf(refwin)
  eq(
    pcall(api.nvim_buf_set_lines, refbuf, 0, 1, false, { 'changed' }),
    false,
    'protected reference refuses actual edits'
  )
  local refmarks = marks(refbuf)
  eq(
    { refmarks[1][3], refmarks[1][4].end_col, refmarks[1][4].hl_group },
    { 1, 2, 'LiltMissing' },
    'Split marks omitted reference character'
  )
  eq(
    { refmarks[2][3], refmarks[2][4].hl_group },
    { 5, 'LiltPending' },
    'Split pending begins at aligned coverage'
  )
  eq(
    api.nvim_win_get_position(refwin)[1] < api.nvim_win_get_position(win)[1],
    true,
    'ordinary terminal starts above/below'
  )
  api.nvim_win_set_cursor(refwin, { #reference, 0 })
  api.nvim_buf_set_lines(buf, 0, -1, false, { 'Bllice' })
  eq(
    api.nvim_win_get_cursor(refwin),
    { #reference, 0 },
    'redraw preserves independent reference cursor'
  )
  eq(marks(refbuf)[1][4].hl_group, 'LiltError', 'Split reference replacement')
  eq(error_ranges(buf, 0), { { 0, 1 }, { 2, 3 } }, 'Split manuscript replacement and extra')
  api.nvim_set_current_win(refwin)
  vim.cmd('wincmd H')
  api.nvim_buf_set_lines(buf, 0, -1, false, { 'Alice' })
  eq(lines(refbuf), reference, 'native window rearrangement preserves reference')
  eq(api.nvim_get_current_win(), refwin, 'redraw after rearrangement preserves focus')
  local layout = vim.fn.winlayout()
  open('split')
  eq(api.nvim_get_current_win(), win, 'repeated Split focuses manuscript')
  eq(api.nvim_win_get_buf(refwin), refbuf, 'repeated Split retains reference resources')
  eq(
    api.nvim_win_get_cursor(refwin),
    { #reference, 0 },
    'repeated Split retains reference position'
  )
  eq(vim.fn.winlayout(), layout, 'repeated Split retains native layout')
  open()
  eq(api.nvim_get_current_win(), win, 'switch targets manuscript by window ID')
  api.nvim_buf_set_lines(buf, 0, -1, false, { '' })
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
  open('split')
  keys('u')
  eq(lines(buf)[1], 'Alice was', 'undo crosses view switches')
  lilt.close()
  open()
  win = api.nvim_get_current_win()
  keys('<C-r>')
  eq(lines(buf)[1], 'Alicia was', 'redo crosses close and reopen')
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
  eq(
    lines(buf),
    { '“It’s… — yes.”', '', 'Alice' },
    'Unicode and blank paragraph preserved'
  )
  for _, range in ipairs(error_ranges(buf, 0)) do
    local byte = lines(buf)[1]:byte(range[2] + 1)
    eq(byte == nil or byte < 128 or byte >= 192, true, 'Unicode extmark ends on byte boundary')
  end
  local written = lines(buf)
  local cursor = api.nvim_win_get_cursor(win)
  local undo_seq = vim.fn.undotree().seq_cur
  for _ = 1, 8 do
    open('split')
    eq(api.nvim_get_current_buf(), buf, 'Split shares buffer')
    eq(#api.nvim_tabpage_list_wins(0), 2, 'two reading windows in Split')
    local cycle_win
    for _, candidate in ipairs(api.nvim_tabpage_list_wins(0)) do
      if candidate ~= win then
        cycle_win = candidate
      end
    end
    local cycle_buf = api.nvim_win_get_buf(cycle_win)
    eq(lines(cycle_buf), reference, 'ordinary complete reference buffer')
    eq(vim.bo[cycle_buf].modifiable, false, 'reference protected')
    eq(vim.bo[cycle_buf].readonly, true, 'reference readonly')
    eq(pending(buf, 0), nil, 'Ghost rendering removed in Split')
    open()
    eq(#api.nvim_tabpage_list_wins(0), 1, 'reference window cleaned up')
    eq(lines(buf), written, 'switching preserves authored text exactly')
    eq(api.nvim_win_get_cursor(win), cursor, 'cursor retained across switching')
    eq(autocmd_count(), count, 'no accumulated autocmds')
  end
  eq(vim.fn.undotree().seq_cur, undo_seq, 'switching adds no undo entries')
  local path = vim.fn.tempname()
  api.nvim_buf_call(buf, function()
    vim.cmd('write ' .. vim.fn.fnameescape(path))
  end)
  eq(vim.fn.readfile(path), written, 'ordinary file contains only authored text')
  vim.fn.writefile({ 'Alice', '', 'So' }, path)
  vim.cmd('edit!')
  vim.wait(10, function()
    return false
  end)
  eq(lines(buf), { 'Alice', '', 'So' }, 'file reload remains authoritative')
  eq(pending(buf, 0), reference[1]:sub(6), 'file reload refreshes pending rendering')
  keys('ggA!<Esc>')
  eq(pending(buf, 0), reference[1]:sub(7), 'reload reattaches live edit feedback')
  written = lines(buf)
  lilt.close()
  eq(api.nvim_get_current_win(), origin, 'returns to original window')
  eq(lines(original), { 'unrelated writing' }, 'unrelated buffer intact')
  eq({ vim.wo.number, vim.wo.wrap }, { true, false }, 'original local options intact')
  eq(
    { vim.o.laststatus, vim.o.showtabline, vim.o.splitbelow, vim.o.equalalways },
    global_options,
    'global options intact'
  )
  eq(#marks(buf), 0, 'all session extmarks cleared')
  eq(autocmd_count(), 0, 'session autocmds removed')
  eq(#api.nvim_list_bufs(), buffers_before + 1, 'only authored buffer retained')
  open()
  eq(api.nvim_get_current_buf(), buf, 'reopen resumes retained manuscript')
  eq(lines(buf), written, 'reopen keeps writing')
  vim.cmd('tabclose')
  vim.wait(20, function()
    return false
  end)
  eq(autocmd_count(), 0, 'manual tab closure cleans session')
  eq(#marks(buf), 0, 'manual tab closure clears decorations')
  open('split')
  local reuse_win = api.nvim_get_current_win()
  api.nvim_win_set_buf(reuse_win, original)
  vim.wait(20, function()
    return false
  end)
  eq(api.nvim_win_is_valid(reuse_win), true, 'repurposed window survives cleanup')
  eq(api.nvim_win_get_buf(reuse_win), original, 'repurposed content survives cleanup')
  eq(vim.wo[reuse_win].number, true, 'repurposed window options restored')
  eq(autocmd_count(), 0, 'replacing manuscript cleans session')
  api.nvim_win_close(reuse_win, true)
  open()
  vim.cmd('vsplit')
  local extra_win = api.nvim_get_current_win()
  api.nvim_win_set_buf(extra_win, original)
  lilt.close()
  eq(api.nvim_win_is_valid(extra_win), true, 'user-created window survives close')
  eq(lines(original), { 'unrelated writing' }, 'user-created window content intact')
  api.nvim_win_close(extra_win, true)
  open()
  api.nvim_win_close(origin, true)
  lilt.close()
  eq(api.nvim_buf_is_valid(buf), true, 'closing final tab retains manuscript')
  eq(api.nvim_get_current_buf(), buf, 'final editor window remains usable')
  eq(vim.wo.number, true, 'final window options restored')
  eq(autocmd_count(), 0, 'final window session cleaned')
  api.nvim_buf_delete(buf, { force = true })
  local reference_baseline = { vim.wo.number, vim.wo.statusline }
  open()
  local fresh = api.nvim_get_current_buf()
  eq(fresh ~= buf, true, 'explicit manuscript wipe starts a fresh buffer')
  keys('iAlice<Esc>')
  eq(pending(fresh, 0), reference[1]:sub(6), 'fresh manuscript has a live renderer')
  open('split')
  local manuscript_win = api.nvim_get_current_win()
  local reference_win
  for _, candidate in ipairs(api.nvim_tabpage_list_wins(0)) do
    if candidate ~= manuscript_win then
      reference_win = candidate
    end
  end
  api.nvim_win_set_buf(reference_win, original)
  vim.wait(20, function()
    return false
  end)
  eq(api.nvim_win_is_valid(reference_win), true, 'repurposed reference window survives')
  eq(
    { vim.wo[reference_win].number, vim.wo[reference_win].statusline },
    reference_baseline,
    'reference restores editor options before Lilt'
  )
  eq(autocmd_count(), 0, 'reference replacement ends session')
  api.nvim_win_close(reference_win, true)
  open('split')
  manuscript_win = api.nvim_get_current_win()
  api.nvim_win_close(manuscript_win, true)
  vim.wait(20, function()
    return false
  end)
  eq(autocmd_count(), 0, 'manual manuscript window closure ends Split')
  open()
  api.nvim_buf_delete(fresh, { force = true })
  vim.wait(20, function()
    return false
  end)
  eq(autocmd_count(), 0, 'active manuscript wipe ends session')
  open()
  eq(api.nvim_get_current_buf() ~= fresh, true, 'active wipe allows fresh session')
  lilt.close()
  vim.fn.delete(path)
  print(('Lilt: %d assertions passed on %s'):format(checks, tostring(vim.version())))
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.write(err .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
