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
  vim.fn.mkdir(root .. '/directory.txt', 'p')
  assert(
    not pcall(manuscript.open, root .. '/directory.txt'),
    'manuscript directory must be rejected'
  )
  local native_completion = vim.fn.exists('+autocomplete') == 1
  local filetypes = {}
  api.nvim_create_autocmd('FileType', {
    pattern = 'text',
    callback = function(event)
      filetypes[event.buf] = (filetypes[event.buf] or 0) + 1
      vim.bo[event.buf].textwidth = 60
    end,
  })
  local original_buffer = api.nvim_get_current_buf()
  local default_completion, original_completion
  if native_completion then
    default_completion = api.nvim_get_option_value('autocomplete', { scope = 'global' })
    original_completion = vim.bo[original_buffer].autocomplete
    api.nvim_set_option_value('autocomplete', true, { scope = 'global' })
  end
  local buf = open(path)
  assert(vim.bo[buf].textwidth == 0, 'manuscripts must keep native typing free of autoformatting')
  if native_completion then
    assert(not vim.bo[buf].autocomplete, 'manuscripts must disable native automatic completion')
    assert(
      vim.bo[original_buffer].autocomplete == original_completion,
      'manuscript completion settings must not affect other buffers'
    )
    api.nvim_set_option_value('autocomplete', default_completion, { scope = 'global' })
  end
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
  assert(
    filetypes[buf] == 1 and vim.bo[buf].textwidth == 0,
    'resuming must not repeat filetype initialization or reset manuscript options'
  )
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
    original ~= buf
      and vim.uv.fs_realpath(api.nvim_buf_get_name(original)) == vim.uv.fs_realpath(path),
    'unit must retain its original file association after :saveas'
  )
  api.nvim_win_close(api.nvim_get_current_win(), true)
  assert(open(path) == original, 'immediate selection after window closure must reuse manuscript')
  vim.wait(10, function()
    return false
  end)
  assert(
    api.nvim_get_current_buf() == original,
    'deferred cleanup must not close the newly selected session'
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
