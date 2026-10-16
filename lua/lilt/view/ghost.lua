local api = vim.api
local render = require('lilt.render')
local M = {}

function M.enter(s)
  s.present(s.user_win, { wrap = false, linebreak = true, statusline = ' Lilt · Ghost %m' })
end

function M.draw(s, lines, results)
  for row, line in ipairs(lines) do
    for _, range in ipairs(results[row].errors) do
      api.nvim_buf_set_extmark(s.manuscript, render.namespace, row - 1, range[1], {
        end_col = range[2], hl_group = 'LiltError', priority = 150, undo_restore = false,
      })
    end
    if results[row].pending ~= '' then
      api.nvim_buf_set_extmark(s.manuscript, render.namespace, row - 1, #line, {
        virt_text = { { results[row].pending, 'LiltPending' } },
        virt_text_pos = 'inline', undo_restore = false,
      })
    end
  end
  if #lines < #s.reference then
    local future = {}
    for row = #lines + 1, #s.reference do
      future[#future + 1] = { { s.reference[row], 'LiltPending' } }
    end
    api.nvim_buf_set_extmark(s.manuscript, render.namespace, #lines - 1, 0, {
      virt_lines = future, virt_lines_overflow = 'scroll', undo_restore = false,
    })
  end
end

return M
