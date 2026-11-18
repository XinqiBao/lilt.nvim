local names = require('lilt.name')
local library = require('lilt.library')
local M = {}

function M.prompt(s, root, title, source, callback)
  s:prompt({
    title = 'Library directory name',
    default = title,
    footer = 'Enter add · Esc cancel',
    preview = function(value)
      local ok, name = pcall(names.work, value, source)
      return ok and name or 'Enter a name with letters or numbers'
    end,
    validate = function(value)
      local name = names.work(value, source)
      library.available(root, name, source)
      return name
    end,
  }, callback)
end

return M
