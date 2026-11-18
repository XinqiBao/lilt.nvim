local json = require('lilt.json')
local function run()
  local data = {
    title = '中文 "title"\nnext',
    units = { { title = 'Second', path = '02.txt' }, { title = 'First', path = '01.txt' } },
    source = vim.empty_dict(),
    languages = {},
    optional = vim.NIL,
  }
  local encoded = json.encode(data)
  assert(
    encoded:find('\n  "', 1, true) and encoded:find('中文', 1, true),
    'readable indented UTF-8 JSON'
  )
  assert(
    vim.deep_equal(vim.json.decode(encoded), data),
    'formatting preserves values, array order and escaping'
  )
  assert(json.encode(vim.json.decode(encoded)) == encoded, 'stable object ordering')
  print('Lilt JSON: readable UTF-8, escaping, stable objects and ordered arrays passed')
end
local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.write(err .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
