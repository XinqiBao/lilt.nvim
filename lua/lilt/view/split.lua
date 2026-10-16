local api = vim.api
local render = require('lilt.render')
local M = {}

function M.leave(s)
  if s.reference_win and api.nvim_win_is_valid(s.reference_win) then
    if api.nvim_win_get_buf(s.reference_win) == s.reference_buf then
      if not pcall(api.nvim_win_close, s.reference_win, true) then
        api.nvim_win_set_buf(s.reference_win, s.manuscript)
        s.restore(s.reference_win)
      end
    else
      s.restore(s.reference_win)
    end
  end
  s.reference_win = nil
  if s.reference_buf and api.nvim_buf_is_valid(s.reference_buf) then
    api.nvim_buf_delete(s.reference_buf, { force = true })
  end
  s.reference_buf = nil
end

function M.enter(s, narrow)
  s.present(s.user_win, {
    wrap = true, linebreak = true,
    statusline = narrow and (' Lilt · Split (Ghost needs %d cols) %%m'):format(s.width)
      or ' Lilt · Manuscript %m',
  })
  s.reference_buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(s.reference_buf, 'lilt://reference/alice')
  api.nvim_buf_set_lines(s.reference_buf, 0, -1, false, s.reference)
  vim.bo[s.reference_buf].filetype = 'text'
  vim.bo[s.reference_buf].modifiable = false
  vim.bo[s.reference_buf].readonly = true
  vim.cmd('aboveleft split')
  s.reference_win = api.nvim_get_current_win()
  s.present(s.reference_win, s.quiet)
  s.present(s.reference_win, { wrap = true, linebreak = true, statusline = ' Lilt · Reference ' })
  api.nvim_win_set_buf(s.reference_win, s.reference_buf)
  api.nvim_set_current_win(s.user_win)
end

function M.draw(s, _, results)
  for row, result in ipairs(results) do
    for _, span in ipairs(result.spans) do
      if span.kind == 'replace' or span.kind == 'extra' then
      api.nvim_buf_set_extmark(s.manuscript, render.namespace, row - 1, span.text_start, {
        end_col = span.text_end, hl_group = 'LiltError', priority = 150, undo_restore = false,
      })
      end
    end
  end
end

return M
