local api = vim.api
local M = {}

-- Named files use Neovim's buffer registry and read machinery. Never reload an
-- already loaded buffer: it may contain unsaved work or a native undo tree.
function M.open(path)
  if path then
    local stat, err, code = vim.uv.fs_stat(path)
    if (stat and stat.type ~= 'file') or (not stat and code ~= 'ENOENT') then
      error(
        'Lilt: cannot open manuscript ' .. path .. ': ' .. (err or 'expected a regular file'),
        0
      )
    end
  end
  local buf = path and vim.fn.bufadd(path) or api.nvim_create_buf(true, false)
  vim.fn.bufload(buf)
  vim.bo[buf].buflisted = true
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].filetype = 'text'
  if not vim.b[buf].lilt_manuscript then
    -- Native automatic completion is buffer-local and available from 0.12.
    if vim.fn.exists('+autocomplete') == 1 then
      vim.bo[buf].autocomplete = false
    end
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
