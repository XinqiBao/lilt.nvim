local api = vim.api
local compare = require('lilt.compare')
local original = compare.line
local calls = 0
compare.line = function(...)
  calls = calls + 1
  return original(...)
end
local lilt = require('lilt')
local ghost = require('lilt.view.ghost')
local draw = ghost.draw
-- Check every displayed result against a fresh computation, including rows
-- shifted by insertion/deletion. Count calls separately to prove reuse.
ghost.draw = function(s, lines, results)
  for row, result in ipairs(results) do
    assert(
      vim.deep_equal(result, original(s.reference[row] or '', lines[row] or '')),
      'stale comparison on row ' .. row
    )
  end
  draw(s, lines, results)
end

local function run()
  lilt.ghost()
  local buf = api.nvim_get_current_buf()
  local reference = vim.fn.readfile('samples/alice.txt')
  api.nvim_buf_set_lines(buf, 0, -1, false, reference)
  calls = 0
  api.nvim_buf_set_lines(buf, 0, 1, false, { 'Blice' })
  assert(calls == 1, 'unchanged rows were recomputed')
  calls = 0
  lilt.split()
  lilt.ghost()
  assert(calls == 0, 'switching discarded reusable comparisons')
  api.nvim_buf_set_lines(buf, 0, 0, false, { 'inserted', '' })
  api.nvim_buf_set_lines(buf, 1, 4, false, {})
  api.nvim_buf_set_lines(buf, 0, -1, false, { '', 'Alice', 'bank', '' })
  api.nvim_buf_set_lines(buf, 0, -1, false, reference)
  local path = vim.fn.tempname()
  vim.cmd('write ' .. vim.fn.fnameescape(path))
  vim.fn.writefile({ 'Aice', '', 'new row' }, path)
  calls = 0
  vim.cmd('edit!')
  assert(calls > 0, 'reload did not refresh comparisons')
  calls = 0
  api.nvim_buf_set_lines(buf, 1, 2, false, { 'changed after reload' })
  assert(calls == 1, 'reload did not reattach live comparison feedback')
  lilt.close()
  calls = 0
  api.nvim_buf_set_lines(buf, 0, -1, false, { 'changed while closed' })
  assert(calls == 0, 'closed session still computes comparisons')
  lilt.ghost()
  api.nvim_buf_set_lines(buf, 0, 1, false, { 'Alice' })
  lilt.close()
  vim.fn.delete(path)
  print('Lilt cache: reuse and edit/reload/reattachment validity passed')
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.write(err .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
