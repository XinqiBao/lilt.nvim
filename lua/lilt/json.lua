-- Neovim 0.11 has no indented JSON encoder. Native encoding still owns scalar
-- escaping and the distinction between empty JSON objects and arrays.
local M = {}

function M.encode(value)
  local function encode(item, depth)
    if type(item) ~= 'table' or next(item) == nil then
      return vim.json.encode(item)
    end
    local array = vim.islist(item)
    local keys = array and vim.fn.range(1, #item) or vim.tbl_keys(item)
    if not array then
      table.sort(keys)
    end
    local lines = {}
    for _, key in ipairs(keys) do
      lines[#lines + 1] = string.rep('  ', depth + 1)
        .. (array and '' or (vim.json.encode(key) .. ': '))
        .. encode(item[key], depth + 1)
    end
    return (array and '[' or '{')
      .. '\n'
      .. table.concat(lines, ',\n')
      .. '\n'
      .. string.rep('  ', depth)
      .. (array and ']' or '}')
  end
  return encode(value, 0)
end

function M.write(path, value)
  assert(
    vim.fn.writefile(vim.split(M.encode(value), '\n', { plain = true }), path) == 0,
    'Lilt: cannot write ' .. path
  )
end

return M
