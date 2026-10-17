if vim.g.loaded_lilt then
  return
end
vim.g.loaded_lilt = true

for command, method in pairs({
  Lilt = 'open',
  LiltGhost = 'ghost',
  LiltSplit = 'split',
  LiltClose = 'close',
}) do
  vim.api.nvim_create_user_command(command, function()
    require('lilt')[method]()
  end, { desc = 'Lilt: ' .. method })
end
