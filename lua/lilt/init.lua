local session = require('lilt.session')
local manuscript = require('lilt.manuscript')
local work = require('lilt.work')
local M = {}
local sample
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')

function M.example(view)
  local example = work.load(root .. '/samples')
  if not sample or not vim.api.nvim_buf_is_valid(sample) then
    sample = manuscript.open()
  end
  session.open(view or 'ghost', {
    manuscript = sample,
    reference = work.read(example.units[1].reference),
  })
end

function M.ghost()
  if not session.open('ghost') then
    M.example('ghost')
  end
end

function M.split()
  if not session.open('split') then
    M.example('split')
  end
end

M.close = session.close
return M
