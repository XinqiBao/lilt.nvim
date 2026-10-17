local api = vim.api
local M = {}

-- Named files use Neovim's buffer registry and read machinery. Never reload an
-- already loaded buffer: it may contain unsaved work or a native undo tree.
function M.open(path)
  local buf = path and vim.fn.bufadd(path) or api.nvim_create_buf(true, false)
  vim.fn.bufload(buf)
  vim.bo[buf].buflisted = true
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].filetype = 'text'
  if not vim.b[buf].lilt_manuscript then
    for name, value in pairs({
      textwidth = 0,
      wrapmargin = 0,
      formatoptions = '',
      autoindent = false,
      smartindent = false,
      cindent = false,
      indentexpr = '',
    }) do
      api.nvim_set_option_value(name, value, { buf = buf })
    end
    vim.b[buf].lilt_manuscript = true
    if path then
      api.nvim_create_autocmd('BufWritePre', {
        buffer = buf,
        desc = 'Create manuscript parent directories',
        callback = function(event)
          -- Follow the current name, including a native :saveas destination.
          local parent = vim.fn.fnamemodify(api.nvim_buf_get_name(event.buf), ':h')
          vim.fn.mkdir(parent, 'p')
        end,
      })
    end
  end
  return buf
end

return M
