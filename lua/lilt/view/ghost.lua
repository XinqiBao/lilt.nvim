local api = vim.api
local render = require('lilt.render')
local M = {}

function M.enter(s)
  s.present(s.user_win, { wrap = false, linebreak = true, statusline = ' Lilt · Ghost %m' })
end

function M.draw(s, lines, results)
  for row, line in ipairs(lines) do
    for _, span in ipairs(results[row].spans) do
      local group, finish
      if span.kind == 'replace' then group, finish = 'LiltError', span.text_end
      elseif span.kind == 'extra' then group, finish = 'LiltExtra', span.text_end
      elseif span.kind == 'missing' then
        -- Missing spans always precede a real authored character: trailing
        -- omissions are Pending. Underline that next character, without adding
        -- a placeholder or shifting any actual text.
        group = 'LiltMissing'
        finish = span.text_start + #vim.fn.strcharpart(line:sub(span.text_start + 1), 0, 1)
      end
      if group then
        api.nvim_buf_set_extmark(s.manuscript, render.namespace, row - 1, span.text_start, {
          end_col = finish, hl_group = group, priority = 150, undo_restore = false,
        })
      end
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
