-- Directory spelling is independent of book titles and source identity.
local M = {}

function M.slug(value)
  assert(type(value) == 'string', 'Lilt: directory name must be text')
  local parts = {}
  for _, code in ipairs(vim.fn.str2list(value)) do
    local char = vim.fn.nr2char(code)
    if char ~= "'" and char ~= '’' and char ~= '‘' then
      local class = vim.fn.charclass(char)
      local letter = code < 128 and char:match('[A-Za-z0-9]')
        or code >= 128 and code < 256 and vim.fn.toupper(char) ~= vim.fn.tolower(char)
        or code >= 256 and class >= 2 and class ~= 3
      parts[#parts + 1] = letter and char:gsub('%u', string.lower) or '-'
    end
  end
  local slug = table.concat(parts):gsub('%-+', '-'):gsub('^%-', ''):gsub('%-$', '')
  -- Leave room for the source suffix; never split a UTF-8 codepoint.
  while #slug > 120 do
    slug = vim.fn.strcharpart(slug, 0, vim.fn.strchars(slug) - 1)
  end
  return (slug:gsub('%-$', ''))
end

function M.work(value, source)
  local slug = M.slug(value)
  if source then
    local suffix = M.slug(source.provider) .. '-' .. M.slug(source.id)
    assert(
      #suffix <= 100 and not suffix:match('^%-') and not suffix:match('%-$'),
      'Lilt: invalid source directory suffix'
    )
    slug = slug == '' and suffix or (slug .. '-' .. suffix)
  end
  assert(slug ~= '', 'Lilt: directory name needs a letter or number')
  local reserved = slug:match('^com([1-9])$') or slug:match('^lpt([1-9])$')
  assert(
    not reserved and slug ~= 'con' and slug ~= 'prn' and slug ~= 'aux' and slug ~= 'nul',
    'Lilt: reserved directory name'
  )
  return slug
end

return M
