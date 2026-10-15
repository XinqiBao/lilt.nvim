local api = vim.api
local compare = require('lilt.compare')
local M = { namespace = api.nvim_create_namespace('lilt') }

function M.clear(buf)
  if api.nvim_buf_is_valid(buf) then
    api.nvim_buf_clear_namespace(buf, M.namespace, 0, -1)
  end
end

function M.draw(session)
  local buf = session.manuscript
  M.clear(buf)
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  for row, line in ipairs(lines) do
    local result = compare.line(session.reference[row] or '', line)
    for _, range in ipairs(result.errors) do
      api.nvim_buf_set_extmark(buf, M.namespace, row - 1, range[1], {
        end_col = range[2], hl_group = 'LiltError', priority = 150,
        undo_restore = false,
      })
    end
    if session.view == 'ghost' and result.pending ~= '' then
      api.nvim_buf_set_extmark(buf, M.namespace, row - 1, #line, {
        virt_text = { { result.pending, 'LiltPending' } },
        virt_text_pos = 'inline', undo_restore = false,
      })
    end
  end
  if session.view == 'ghost' and #lines < #session.reference then
    local future = {}
    for row = #lines + 1, #session.reference do
      future[#future + 1] = { { session.reference[row], 'LiltPending' } }
    end
    api.nvim_buf_set_extmark(buf, M.namespace, #lines - 1, 0, {
      virt_lines = future, virt_lines_overflow = 'scroll', undo_restore = false,
    })
  end
end

return M
