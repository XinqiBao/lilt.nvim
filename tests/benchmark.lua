-- Diagnostic only: no timing thresholds. See DEVELOPING.md.
local api, lilt = vim.api, require('lilt')
local manuscript
local function open(view)
  if not manuscript or not vim.api.nvim_buf_is_valid(manuscript) then
    manuscript = require('lilt.manuscript').open()
  end
  require('lilt.session').open(view or 'ghost', {
    manuscript = manuscript,
    reference = vim.fn.readfile('examples/alice/alice.txt'),
  })
end

local reference = vim.fn.readfile('examples/alice/alice.txt')
local compare, calls = require('lilt.compare'), 0
local line = compare.line
compare.line = function(...)
  calls = calls + 1
  return line(...)
end
for _, count in ipairs({ 5, #reference }) do
  open()
  local buf = api.nvim_get_current_buf()
  local text = vim.deepcopy(reference)
  local mismatches = 0
  for i = 1, math.min(count, #text) do
    if text[i] ~= '' then
      text[i] = 'X' .. text[i]:sub(2)
      mismatches = mismatches + 1
    end
  end
  api.nvim_buf_set_lines(buf, 0, -1, false, text)
  local durations = {}
  calls = 0
  for i = 1, 15 do
    local t = vim.uv.hrtime()
    api.nvim_buf_set_lines(buf, 0, 1, false, { text[1] .. (i % 2 == 0 and 'x' or 'y') })
    durations[i] = (vim.uv.hrtime() - t) / 1e6
  end
  table.sort(durations)
  print(
    ('mismatched rows=%d median edit=%.3f ms comparisons=%d'):format(
      mismatches,
      durations[8],
      calls
    )
  )
  lilt.close()
end
vim.cmd('qa!')
