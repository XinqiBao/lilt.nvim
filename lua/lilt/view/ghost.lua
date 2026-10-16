local api = vim.api
local render = require('lilt.render')
local compare = require('lilt.compare')
local M = {}

-- Keep context at word boundaries; whitespace differences include both neighbors.
local function expand(text, first, last)
  local whitespace = first == last or text:sub(first + 1, last):find('%s')
  if whitespace then
    while first > 0 and text:sub(first, first):match('%s') do first = first - 1 end
    while last < #text and text:sub(last + 1, last + 1):match('%s') do last = last + 1 end
  end
  while first > 0 and not text:sub(first, first):match('%s') do first = first - 1 end
  while last < #text and not text:sub(last + 1, last + 1):match('%s') do last = last + 1 end
  return first, last
end

local function context(reference, text, result, target)
  local rs, re = expand(reference, target.ref_start, target.ref_end)
  local ts, te = expand(text, target.text_start, target.text_end)
  -- Project context through the existing alignment, including replacements
  -- with unequal UTF-8 byte lengths. No second diff is calculated.
  local function project(value, base, other, other_base, first, last)
    local prefix = vim.fn.strchars(value:sub(base + 1, first))
    local length = vim.fn.strchars(value:sub(first + 1, last))
    local tail = other:sub(other_base + 1)
    return other_base + vim.fn.byteidx(tail, prefix), other_base + vim.fn.byteidx(tail, prefix + length)
  end
  for _ = 1, 2 do
    for _, span in ipairs(result.spans) do
      if span.kind == 'equal' or span.kind == 'replace' then
        local a, b = math.max(ts, span.text_start), math.min(te, span.text_end)
        if a < b then
          local first, last = project(text, span.text_start, reference, span.ref_start, a, b)
          rs, re = math.min(rs, first), math.max(re, last)
        end
        a, b = math.max(rs, span.ref_start), math.min(re, span.ref_end)
        if a < b then
          local first, last = project(reference, span.ref_start, text, span.text_start, a, b)
          ts, te = math.min(ts, first), math.max(te, last)
        end
      elseif span.kind ~= 'pending' and ((span.ref_start < re and span.ref_end > rs)
        or (span.text_start < te and span.text_end > ts)) then
        rs, re = math.min(rs, span.ref_start), math.max(re, span.ref_end)
        ts, te = math.min(ts, span.text_start), math.max(te, span.text_end)
      end
    end
    rs, re = expand(reference, rs, re)
    ts, te = expand(text, ts, te)
  end
  local function excerpt(value, first, last, anchor)
    local before = vim.fn.strchars(value:sub(first + 1, anchor))
    local part = value:sub(first + 1, last)
    local start = math.max(0, before - 24)
    local clipped = vim.fn.strcharpart(part, start, 52)
    return (start > 0 and '…' or '') .. clipped
      .. (start + 52 < vim.fn.strchars(part) and '…' or '')
  end
  return { 'Expected  ' .. excerpt(reference, rs, re, target.ref_start),
    'Typed     ' .. excerpt(text, ts, te, target.text_start) }
end

local function dismiss(h)
  h.generation = h.generation + 1
  if h.timer then
    h.timer:stop()
    if not h.timer:is_closing() then h.timer:close() end
    h.timer = nil
  end
  local win, buf = h.win, h.buf
  h.win, h.buf = nil, nil
  if win or buf then
    -- on_lines runs under textlock. Invalidate immediately; release UI resources
    -- on the next main-loop turn, before another hint can become visible.
    vim.schedule(function()
      if win and api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
      if buf and api.nvim_buf_is_valid(buf) then api.nvim_buf_delete(buf, { force = true }) end
    end)
  end
end

local function request(s)
  local h = s.ghost
  if not h then return end
  dismiss(h)
  if api.nvim_get_current_win() ~= s.user_win or api.nvim_get_mode().mode ~= 'n'
    or api.nvim_win_get_buf(s.user_win) ~= s.manuscript then return end
  local generation = h.generation
  local cursor = api.nvim_win_get_cursor(s.user_win)
  local tick = api.nvim_buf_get_changedtick(s.manuscript)
  h.timer = vim.defer_fn(function()
    if not h.active or h.generation ~= generation then return end
    h.timer = nil
    if not api.nvim_win_is_valid(s.user_win) or not api.nvim_buf_is_valid(s.manuscript)
      or api.nvim_get_current_win() ~= s.user_win or api.nvim_get_mode().mode ~= 'n'
      or api.nvim_win_get_buf(s.user_win) ~= s.manuscript
      or api.nvim_buf_get_changedtick(s.manuscript) ~= tick
      or not vim.deep_equal(api.nvim_win_get_cursor(s.user_win), cursor) then return end
    local text = api.nvim_buf_get_lines(s.manuscript, cursor[1] - 1, cursor[1], false)[1]
    local reference = s.reference[cursor[1]] or ''
    local result = compare.line(reference, text)
    local target
    for _, span in ipairs(result.spans) do
      if (span.kind == 'missing' and cursor[2] == span.text_start)
        or ((span.kind == 'replace' or span.kind == 'extra')
          and cursor[2] >= span.text_start and cursor[2] < span.text_end) then
        target = vim.deepcopy(span)
        if span.kind ~= 'missing' then
          target.text_start = cursor[2]
          target.text_end = cursor[2] + #vim.fn.strcharpart(text:sub(cursor[2] + 1), 0, 1)
          if span.kind == 'replace' then
            local index = vim.fn.strchars(text:sub(span.text_start + 1, cursor[2]))
            local tail = reference:sub(span.ref_start + 1, span.ref_end)
            target.ref_start = span.ref_start + vim.fn.byteidx(tail, index)
            target.ref_end = span.ref_start + vim.fn.byteidx(tail, index + 1)
          end
        end
        break
      end
    end
    if not target then return end
    local content = context(reference, text, result, target)
    local width = math.max(vim.fn.strdisplaywidth(content[1]), vim.fn.strdisplaywidth(content[2]))
    h.buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(h.buf, 0, -1, false, content)
    vim.bo[h.buf].modifiable = false
    h.win = api.nvim_open_win(h.buf, false, {
      relative = 'win', win = s.user_win, bufpos = { cursor[1] - 1, cursor[2] },
      width = math.max(1, math.min(width, api.nvim_win_get_width(s.user_win) - 2)),
      height = 2, style = 'minimal', border = 'rounded', focusable = false,
      noautocmd = true,
    })
    vim.wo[h.win].wrap = false
  end, 250)
end

function M.leave(s)
  if not s.ghost then return end
  local h = s.ghost
  h.active = false
  dismiss(h)
  api.nvim_del_augroup_by_id(h.group)
  s.ghost = nil
end

function M.enter(s)
  s.present(s.user_win, { wrap = false, linebreak = true, statusline = ' Lilt · Ghost %m' })
  local h = { active = true, generation = 0, group = api.nvim_create_augroup('LiltGhost', { clear = true }) }
  s.ghost = h
  api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'ModeChanged', 'WinEnter', 'BufEnter', 'TextChanged', 'TextChangedI' }, {
    group = h.group, callback = function() request(s) end,
  })
  api.nvim_create_autocmd({ 'InsertEnter', 'WinLeave', 'BufLeave', 'CmdlineEnter' }, {
    group = h.group, callback = function() dismiss(h) end,
  })
end

function M.draw(s, lines, results)
  request(s)
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
