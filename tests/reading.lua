local api = vim.api
local manuscript = require('lilt.manuscript')
local session = require('lilt.session')
local root = vim.fn.tempname()
local path = root .. '/chapters/01.txt'
local reference = { 'A first line.', '', 'A last line.' }
local function open(target)
  local buf = manuscript.open(target)
  session.open('ghost', { manuscript = buf, reference = reference })
  return buf
end
local function run()
  local tabs = #api.nvim_list_tabpages()
  local messages = {}
  local notify = vim.notify
  vim.notify = function(message)
    messages[#messages + 1] = message
  end
  require('lilt').ghost()
  require('lilt').split()
  vim.notify = notify
  assert(
    #messages == 2 and messages[1]:find(':Lilt', 1, true),
    'inactive commands need helpful messages'
  )
  assert(#api.nvim_list_tabpages() == tabs, 'inactive commands must not open content')
  local buf = open(path)
  assert(api.nvim_buf_get_name(buf) == path, 'manuscript must be named')
  assert(not vim.bo[buf].modified and vim.fn.filereadable(path) == 0, 'opening must not save')
  api.nvim_feedkeys(api.nvim_replace_termcodes('iA first<Esc>', true, false, true), 'xt', false)
  local undo = vim.fn.undotree().seq_cur
  session.open('split')
  assert(api.nvim_get_current_buf() == buf, 'views must share named manuscript')
  session.close()
  assert(not session.open('ghost'), 'close must forget the reading session')
  assert(not session.open('split'), 'close must not reopen presentation')
  local second = open(root .. '/02.txt')
  api.nvim_buf_set_lines(second, 0, -1, false, { 'Other writing' })
  assert(open(path) == buf, 'switching must reuse an unsaved buffer')
  assert(api.nvim_buf_get_lines(buf, 0, -1, false)[1] == 'A first', 'switch lost unsaved edits')
  assert(vim.fn.undotree().seq_cur == undo, 'switch changed undo history')
  local ok, err = pcall(vim.cmd, 'bdelete')
  assert(not ok and err:find('E89', 1, true), 'native delete must protect edits: ' .. tostring(err))
  session.close()
  ok, err = pcall(vim.cmd, 'qall')
  assert(
    not ok and (err:find('E162', 1, true) or err:find('E37', 1, true)),
    'hidden edits must block quit: ' .. tostring(err)
  )
  open(path)
  vim.cmd('write')
  assert(vim.fn.readfile(path)[1] == 'A first', ':w must create parents and save authored text')
  session.close()
  api.nvim_buf_delete(buf, {})
  buf = open(path)
  assert(api.nvim_buf_get_lines(buf, 0, -1, false)[1] == 'A first', 'reopen must read saved file')
  api.nvim_feedkeys(api.nvim_replace_termcodes('A line.<Esc>', true, false, true), 'xt', false)
  vim.cmd('write')
  assert(vim.fn.readfile(path)[1] == reference[1], 'resumed writing must save normally')
  session.close()
  vim.fn.writefile({}, path)
  api.nvim_buf_delete(buf, {})
  buf = open(path)
  assert(vim.deep_equal(api.nvim_buf_get_lines(buf, 0, -1, false), { '' }), 'empty saved file')
  session.open('split')
  session.open('ghost')
  local renamed = root .. '/elsewhere/new-name.txt'
  vim.cmd('saveas ' .. vim.fn.fnameescape(renamed))
  assert(
    api.nvim_buf_get_name(buf) == renamed and vim.fn.filereadable(renamed) == 1,
    ':saveas must create parents for its new name'
  )
  session.close()
  local original = open(path)
  assert(
    original ~= buf and api.nvim_buf_get_name(original) == path,
    'unit must retain its original file association after :saveas'
  )
  session.close()
  print('Lilt reading: named buffers, save/resume, switching and native protections passed')
end
local ok, err = xpcall(run, debug.traceback)
pcall(session.close)
vim.fn.delete(root, 'rf')
if not ok then
  io.write(err .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
