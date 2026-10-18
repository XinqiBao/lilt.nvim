-- A passive excerpt beside the unit list. No focus, mappings, or reading state.
local api = vim.api
local M = {}

function M.new()
  local p = {}

  function p:close()
    local win, buf = self.win, self.buf
    self.win, self.buf, self.item, self.lines = nil, nil, nil, nil
    if win and api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
    if buf and api.nvim_buf_is_valid(buf) then
      api.nvim_buf_delete(buf, { force = true })
    end
  end

  function p:show(item, config)
    if not config then
      self:close()
      return
    end
    local lines
    if not item or not item.preview then
      lines = { 'Select a reading unit.' }
    elseif item == self.item then
      lines = self.lines
    else
      local ok, text = pcall(item.preview)
      lines = ok and text or { 'Preview unavailable', (tostring(text):gsub('%c', ' ')) }
      self.item, self.lines = item, lines
    end
    if not self.buf then
      self.buf = api.nvim_create_buf(false, true)
      vim.bo[self.buf].bufhidden = 'hide'
    end
    vim.bo[self.buf].readonly = false
    vim.bo[self.buf].modifiable = true
    api.nvim_buf_set_lines(self.buf, 0, -1, false, vim.list_slice(lines, 1, config.height))
    vim.bo[self.buf].modifiable = false
    vim.bo[self.buf].readonly = true
    config.relative, config.style, config.border = 'editor', 'minimal', 'rounded'
    config.focusable, config.title = false, ' Reference preview '
    if self.win then
      api.nvim_win_set_config(self.win, config)
    else
      self.win = api.nvim_open_win(self.buf, false, config)
      for name, value in pairs({
        wrap = true,
        linebreak = true,
        foldenable = false,
        scrolloff = 0,
        scrollbind = false,
        cursorbind = false,
        conceallevel = 0,
        colorcolumn = '',
        spell = false,
        list = false,
        winbar = '',
      }) do
        api.nvim_set_option_value(name, value, { win = self.win })
      end
    end
    api.nvim_win_set_cursor(self.win, { 1, 0 })
    api.nvim_win_call(self.win, function()
      vim.fn.winrestview({ topline = 1, leftcol = 0, skipcol = 0 })
    end)
  end
  return p
end

return M
