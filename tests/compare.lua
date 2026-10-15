local compare = require('lilt.compare')
local checks = 0
local function eq(actual, expected, label)
  checks = checks + 1
  assert(vim.deep_equal(actual, expected), label .. '\nexpected: ' .. vim.inspect(expected) .. '\nactual: ' .. vim.inspect(actual))
end

for _, case in ipairs({
  { 'abc', '', {}, 'abc' }, { 'abc', 'ab', {}, 'c' },
  { 'abc', 'axc', { { 1, 2 } }, '' }, { 'abc', 'xyz', { { 0, 3 } }, '' },
  { 'abc', 'ac', { { 1, 2 } }, 'c' }, { 'abc', 'abbc', { { 2, 4 } }, '' },
  { '', '', {}, '' }, { '', 'x', { { 0, 1 } }, '' },
  { '“It’s… — yes.”', '“It’s… — yes.”', {}, '' },
  { '“It’s…', '“It’', {}, 's…' },
  { '“a—b', '“x—b', { { 3, 4 } }, '' },
  { 'abc', 'a“', { { 1, 4 } }, 'c' },
  { 'a b', 'ab', { { 1, 2 } }, 'b' },
}) do
  local result = compare.line(case[1], case[2])
  eq(result.errors, case[3], 'positional error ranges')
  eq(result.pending, case[4], 'pending suffix')
end

print(('Lilt comparison: %d assertions passed on %s'):format(checks, tostring(vim.version())))
vim.cmd('qa!')
