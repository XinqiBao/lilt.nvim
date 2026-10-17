local api = vim.api
local picker = require('lilt.picker')
local work = require('lilt.work')
local root = vim.fn.tempname()
local home = root .. '/library'
local example_root = root .. '/examples'
local notify = vim.notify
local messages = {}
vim.notify = function(message)
  messages[#messages + 1] = message
end
local function keys(text)
  api.nvim_feedkeys(api.nvim_replace_termcodes(text, true, false, true), 'xt', false)
  vim.wait(10, function()
    return false
  end)
end
local function lines()
  return api.nvim_buf_get_lines(0, 0, -1, false)
end
local function fixture(name, title, count)
  local directory = example_root .. '/' .. name
  vim.fn.mkdir(directory, 'p')
  local units = {}
  for i = 1, count do
    units[i] = { path = i .. '.txt', title = i == 1 and title or ('Unit ' .. i) }
    vim.fn.writefile({ 'Reference ' .. i }, directory .. '/' .. i .. '.txt')
  end
  vim.fn.writefile({ vim.json.encode({ title = title, units = units }) }, directory .. '/lilt.json')
end
local function no_picker()
  assert(not pcall(api.nvim_get_autocmds, { group = 'LiltPicker' }), 'picker autocmds leaked')
  for _, win in ipairs(api.nvim_list_wins()) do
    assert(api.nvim_win_get_config(win).relative == '', 'picker window leaked')
  end
end
local function run()
  local origin = api.nvim_get_current_win()
  -- Observe configured discovery paths while exercising the real entry/picker.
  local discover, xdg = work.discover, vim.env.XDG_DATA_HOME
  local seen
  work.discover = function(directory)
    seen = directory
    return {}, {}
  end
  for _, case in ipairs({
    { root .. '/data', root .. '/data/lilt/references' },
    { '', vim.env.HOME .. '/.local/share/lilt/references' },
    { 'relative/path', vim.env.HOME .. '/.local/share/lilt/references' },
    { '~/.data', vim.env.HOME .. '/.local/share/lilt/references' },
    { false, vim.env.HOME .. '/.local/share/lilt/references' },
  }) do
    vim.env.XDG_DATA_HOME = case[1] or nil
    package.loaded.lilt = nil
    local lilt = require('lilt')
    assert(
      seen ~= case[2] or case[2]:find('/.local/share', 1, true),
      'loading must not discover works'
    )
    lilt.open()
    assert(seen == case[2], 'XDG convention: ' .. tostring(seen))
    keys('q')
    no_picker()
    seen = nil
  end
  package.loaded.lilt = nil
  local lilt = require('lilt')
  lilt.setup({ library = home })
  lilt.open()
  assert(seen == home .. '/references', 'custom library must override default')
  assert(vim.fn.isdirectory(root) == 0, 'loading and browsing must not create directories')
  keys('q')
  work.discover, vim.env.XDG_DATA_HOME = discover, xdg

  fixture('first', 'A poem — ' .. string.rep('長', 80), 2)
  fixture('second', 'B letters — 文学', 24)
  local works = work.discover(example_root)
  assert(#works == 2 and #works[2].units == 24, 'multiple example works and units discovered')
  picker.open(home, example_root)
  assert(vim.deep_equal(lines(), { '  Add local work…', '  Examples' }), 'empty library actions')
  local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
  picker.open(home, example_root)
  assert(
    api.nvim_get_current_win() == win and api.nvim_get_current_buf() == buf,
    'repeated open must reuse picker'
  )
  keys('Gll')
  assert(#lines() == 2, 'first example has two ordered units')
  local width = api.nvim_win_get_width(0)
  for _, line in ipairs(lines()) do
    assert(vim.fn.strdisplaywidth(line) <= width, 'long Unicode titles must fit')
  end
  keys('jl')
  local second_unit = api.nvim_get_current_buf()
  assert(
    vim.bo.buftype == '' and api.nvim_buf_get_name(0) == '',
    'example uses ordinary temporary manuscript'
  )
  keys('iReference<Esc>')
  local undo = vim.fn.undotree().seq_cur
  lilt.close()
  picker.open(home, example_root)
  keys('Glljl')
  assert(
    api.nvim_get_current_buf() == second_unit and lines()[1] == 'Reference',
    'example reopens unsaved manuscript'
  )
  assert(vim.fn.undotree().seq_cur == undo, 'example reopen keeps native undo')
  lilt.close()
  picker.open(home, example_root)
  keys('Glll')
  local first_unit = api.nvim_get_current_buf()
  assert(
    first_unit ~= second_unit and lines()[1] == '',
    'example units have independent manuscripts'
  )
  lilt.close()
  api.nvim_buf_delete(second_unit, { force = true })
  picker.open(home, example_root)
  keys('Glljl')
  assert(
    api.nvim_get_current_buf() ~= second_unit and lines()[1] == '',
    'wiped example starts fresh'
  )
  lilt.close()
  picker.open(home, example_root)
  keys('GljlG')
  assert(api.nvim_win_get_cursor(0)[1] == 24, 'G navigates a long chapter list')
  keys('ggh')
  assert(#lines() == 2 and api.nvim_win_get_cursor(0)[1] == 2, 'back restores work selection')
  keys('<Esc>q')
  assert(api.nvim_get_current_win() == origin, 'back/close restores original focus')
  no_picker()

  local open_win = api.nvim_open_win
  api.nvim_open_win = function()
    error('picker initialization failure')
  end
  picker.open(home, example_root)
  api.nvim_open_win = open_win
  no_picker()
  assert(
    messages[#messages]:find('picker initialization failure', 1, true),
    'initialization error must be reported'
  )

  -- Cancellation of the native path prompt returns to the library picker.
  local input = vim.ui.input
  vim.ui.input = function(_, callback)
    callback(nil)
  end
  picker.open(home, example_root)
  keys('l')
  assert(lines()[1] == '  Add local work…', 'canceling import must return to library')
  keys('q')
  vim.ui.input = function(_, callback)
    callback(root .. '/missing-work')
  end
  picker.open(home, example_root)
  keys('l')
  assert(lines()[1] == '  Add local work…', 'failed import must return to library')
  keys('q')
  vim.ui.input = input
  vim.fn.writefile({ 'not a directory' }, root .. '/invalid-library')
  picker.open(root .. '/invalid-library', example_root)
  keys('Glll')
  assert(api.nvim_get_current_buf() == first_unit, 'unusable library must not block examples')
  lilt.close()
  no_picker()
  for _ = 1, 4 do
    picker.open(home, example_root)
    local floating = api.nvim_get_current_win()
    api.nvim_win_close(floating, true)
    api.nvim_exec_autocmds('VimResized', {})
    vim.wait(10, function()
      return false
    end)
    no_picker()
  end
  picker.open(home, example_root)
  local scratch = api.nvim_get_current_buf()
  api.nvim_set_current_win(origin)
  vim.wait(10, function()
    return false
  end)
  no_picker()
  assert(not api.nvim_buf_is_valid(scratch), 'leaving picker must release scratch buffer')
  assert(vim.fn.isdirectory(home) == 0, 'examples and browsing never write the library')
  -- A corrupt progress file is local to one unit and cannot hide its siblings.
  require('lilt.library').add(home, example_root .. '/second')
  vim.fn.mkdir(home .. '/manuscripts/second/1.txt', 'p')
  vim.fn.writefile({ 'Reference 2' }, home .. '/manuscripts/second/2.txt')
  picker.open(home, example_root)
  keys('l')
  assert(
    lines()[1]:match('%?$') and #lines() == 24,
    'one progress error must not hide reading units'
  )
  width = api.nvim_win_get_width(0)
  assert(lines()[2]:match('100%%$'), 'saved rows must show their numeric progress')
  for _, line in ipairs(lines()) do
    assert(vim.fn.strdisplaywidth(line) == width, 'saved progress must share the right edge')
  end
  keys('jl')
  assert(
    vim.uv.fs_realpath(api.nvim_buf_get_name(0))
      == vim.uv.fs_realpath(home .. '/manuscripts/second/2.txt'),
    'other units must remain readable'
  )
  lilt.close()
  no_picker()
  print('Lilt picker: XDG, hierarchy, multiple examples, buffer reuse and cleanup passed')
end
local ok, err = xpcall(run, debug.traceback)
vim.notify = notify
pcall(require('lilt').close)
vim.fn.delete(root, 'rf')
if not ok then
  io.write(err .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
