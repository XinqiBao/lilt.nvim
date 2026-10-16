local api = vim.api
local compare = require('lilt.compare')
local M = { namespace = api.nvim_create_namespace('lilt') }

function M.clear(buf)
  if api.nvim_buf_is_valid(buf) then
    api.nvim_buf_clear_namespace(buf, M.namespace, 0, -1)
  end
end

return M
