local names = require('lilt.name')
local source = { provider = 'gutenberg', id = '37106' }
local function run()
  for _, case in ipairs({
    { '  Little_Women  ', 'little-women' },
    { 'Little Women; Or, Meg, Jo, Beth, and Amy', 'little-women-or-meg-jo-beth-and-amy' },
    { 'Alice’s Adventures', 'alices-adventures' },
    { 'Café — 红楼梦 第一卷', 'café-红楼梦-第一卷' },
    { '../A/B\\C: D?', 'a-b-c-d' },
    { 'Poems 🐇 & Letters', 'poems-letters' },
    { 'é', 'é' },
  }) do
    assert(names.slug(case[1]) == case[2], 'directory spelling: ' .. case[1])
  end
  assert(names.work('Little Women', source) == 'little-women-gutenberg-37106', 'source suffix')
  assert(names.work('… 🐇', source) == 'gutenberg-37106', 'source-only fallback')
  assert(not pcall(names.work, '… 🐇'), 'local works need a usable name')
  for _, reserved in ipairs({ 'CON', 'nul', 'COM1', 'lpt9' }) do
    assert(not pcall(names.work, reserved), 'portable reserved name: ' .. reserved)
  end
  local long = names.work(string.rep('红楼梦', 80), source)
  assert(
    #long <= 240 and vim.fn.strchars(long, 1) > 0 and not long:find('\239\191\189'),
    'bounded UTF-8 path'
  )
  local isk = vim.bo.iskeyword
  vim.bo.iskeyword = '33-255'
  assert(
    names.slug('Café # _ 文学') == 'café-文学',
    'naming is independent of editing word settings'
  )
  vim.bo.iskeyword = isk

  print('Lilt names: portable spelling and source suffixes passed')
end
local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.write(err .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
