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
  s.options[s.reference_win or -1] = nil
  s.reference_win = nil
  if s.reference_buf and api.nvim_buf_is_valid(s.reference_buf) then
    api.nvim_buf_delete(s.reference_buf, { force = true })
  end
  s.reference_buf = nil
end

function M.enter(s)
  s.reference_buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(s.reference_buf, 'lilt://reference/alice')
  api.nvim_buf_set_lines(s.reference_buf, 0, -1, false, s.reference)
  vim.bo[s.reference_buf].filetype = 'text'
  vim.bo[s.reference_buf].modifiable = false
  vim.bo[s.reference_buf].readonly = true
  -- One separator plus a comfortable prepared-line width in each window.
  -- Choose once; native rearrangement/resizing owns the layout afterwards.
  local wide = api.nvim_win_get_width(s.user_win) >= 2 * s.width + 1
  -- Native splits inherit window options. Remove our presentation first so
  -- the new window snapshots editor state, rather than Lilt's own settings.
  s.restore(s.user_win)
  vim.cmd(wide and 'aboveleft vsplit' or 'aboveleft split')
  s.reference_win = api.nvim_get_current_win()
  local presentation = { wrap = true, linebreak = true, statusline = ' Lilt · Reference ' }
  s.present(s.reference_win, s.quiet)
  s.present(s.reference_win, presentation)
  api.nvim_win_set_buf(s.reference_win, s.reference_buf)
  -- Buffer assignment can reset window-local options. Reapply presentation,
  -- keeping the inherited editor baseline captured before the buffer change.
  s.present(s.reference_win, s.quiet)
  s.present(s.reference_win, presentation)
  s.present(s.user_win, s.quiet)
  s.present(s.user_win, {
    wrap = true,
    linebreak = true,
    statusline = ' Lilt · Manuscript %m',
  })
  api.nvim_set_current_win(s.user_win)
end

function M.draw(s, _, results)
  if not s.reference_buf or not api.nvim_buf_is_valid(s.reference_buf) then
    return
  end
  render.clear(s.reference_buf)
  for row, result in ipairs(results) do
    for _, span in ipairs(result.spans) do
      local authored_group = span.kind == 'replace' and 'LiltError'
        or span.kind == 'extra' and 'LiltExtra'
      if authored_group then
        api.nvim_buf_set_extmark(s.manuscript, render.namespace, row - 1, span.text_start, {
          end_col = span.text_end,
          hl_group = authored_group,
          priority = 150,
          undo_restore = false,
        })
      end
      local reference_group = ({
        pending = 'LiltPending',
        replace = 'LiltError',
        missing = 'LiltMissing',
      })[span.kind]
      if reference_group and span.ref_end > span.ref_start then
        api.nvim_buf_set_extmark(s.reference_buf, render.namespace, row - 1, span.ref_start, {
          end_col = span.ref_end,
          hl_group = reference_group,
          priority = 150,
          undo_restore = false,
        })
      end
    end
  end
end

return M
