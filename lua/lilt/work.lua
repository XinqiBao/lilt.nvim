local uv = vim.uv
local M = {}

local function fail(message)
  error('Lilt: ' .. message, 0)
end

local function read(path)
  local file, err = io.open(path, 'rb')
  if not file then
    fail(path .. ': ' .. err)
  end
  local text, read_err = file:read('*a')
  file:close()
  if not text then
    fail(path .. ': ' .. read_err)
  end
  -- Reject invalid UTF-8 and NULs before they reach comparison or buffer APIs.
  local i = 1
  while i <= #text do
    local a, b = text:byte(i, i + 1)
    local size = a < 128 and 1
      or (a >= 194 and a <= 223) and 2
      or (a >= 224 and a <= 239) and 3
      or (a >= 240 and a <= 244) and 4
    if
      a == 0
      or not size
      or i + size - 1 > #text
      or (a == 224 and b < 160)
      or (a == 237 and b > 159)
      or (a == 240 and b < 144)
      or (a == 244 and b > 143)
    then
      fail(path .. ': expected UTF-8 text without NUL bytes')
    end
    for j = i + 1, i + size - 1 do
      local byte = text:byte(j)
      if byte < 128 or byte > 191 then
        fail(path .. ': invalid UTF-8')
      end
    end
    i = i + size
  end
  return (text:gsub('^\239\187\191', ''))
end

function M.read(path)
  local text = read(path):gsub('\r\n', '\n')
  if text == '' then
    return {}
  end
  local lines = vim.split(text, '\n', { plain = true })
  if lines[#lines] == '' then
    table.remove(lines)
  end
  return lines
end

local function title(value, field)
  if type(value) ~= 'string' or not value:find('%S') or value:find('%c') then
    fail(field .. ' must be a nonempty single-line string')
  end
end

local function fields(value, allowed, label)
  if type(value) ~= 'table' or vim.islist(value) then
    fail(label .. ' must be an object')
  end
  for key in pairs(value) do
    if not allowed[key] then
      fail(label .. ': unknown field ' .. tostring(key))
    end
  end
end

-- Portable relative paths only; no normalization that could alias two units.
local function reference_path(root, path)
  if type(path) ~= 'string' or path == '' or path:find('[\\:%c]') then
    fail(root .. ': unit path must be a relative path using / separators')
  end
  local current = root
  for _, part in ipairs(vim.split(path, '/', { plain = true })) do
    if part == '' or part == '.' or part == '..' then
      fail(root .. ': unit path must stay inside the work: ' .. path)
    end
    current = current .. '/' .. part
    local stat = uv.fs_lstat(current)
    if not stat or (stat.type ~= 'file' and stat.type ~= 'directory') then
      fail(root .. ': missing file or unsupported symlink in unit path: ' .. path)
    end
  end
  if uv.fs_stat(current).type ~= 'file' then
    fail(root .. ': unit path is not a file: ' .. path)
  end
  return current
end

function M.load(directory)
  local root, err = uv.fs_realpath(vim.fn.fnamemodify(directory, ':p'))
  if not root then
    fail(directory .. ': ' .. err)
  end
  local manifest = root .. '/lilt.json'
  local stat = uv.fs_lstat(manifest)
  if not stat or stat.type ~= 'file' then
    fail(manifest .. ': expected a regular manifest file')
  end
  local ok, data = pcall(vim.json.decode, read(manifest))
  if not ok then
    fail(manifest .. ': invalid JSON: ' .. tostring(data))
  end
  fields(data, { title = true, author = true, source = true, units = true }, manifest)
  title(data.title, manifest .. ': title')
  if data.author ~= nil then
    title(data.author, manifest .. ': author')
  end
  if data.source ~= nil then
    fields(data.source, { provider = true, id = true, url = true }, manifest .. ': source')
    for _, key in ipairs({ 'provider', 'id', 'url' }) do
      title(data.source[key], manifest .. ': source ' .. key)
    end
    if not data.source.url:match('^https?://%S+$') then
      fail(manifest .. ': source url must be an HTTP(S) URL')
    end
  end
  if type(data.units) ~= 'table' or not vim.islist(data.units) or #data.units == 0 then
    fail(manifest .. ': units must be a nonempty array')
  end
  local seen, units = {}, {}
  for index, unit in ipairs(data.units) do
    fields(unit, { title = true, path = true }, manifest .. ': unit ' .. index)
    title(unit.title, manifest .. ': unit ' .. index .. ' title')
    local path = reference_path(root, unit.path)
    if seen[unit.path] or unit.path == 'lilt.json' then
      fail(manifest .. ': duplicate or reserved unit path: ' .. unit.path)
    end
    seen[unit.path] = true
    units[#units + 1] = { title = unit.title, path = unit.path, reference = path }
  end
  return {
    root = root,
    title = data.title,
    author = data.author,
    source = data.source,
    units = units,
  }
end

-- Full validation belongs at installation (and selected-unit consumption), not
-- at discovery. Keep only manifests and file metadata in the navigation model.
function M.validate(directory)
  local reading = M.load(directory)
  for _, unit in ipairs(reading.units) do
    M.read(unit.reference)
  end
  return reading
end

function M.read_unit(reading, unit)
  return M.read(reference_path(reading.root, unit.path))
end

-- Scan bytes in bounded memory, even for a reference with very long lines.
-- A BOM is not a row; CRLF and LF each contain one newline. This is a numerical
-- aid only: text encoding is validated when a reference is opened or installed.
function M.count_lines(path)
  local stat = uv.fs_stat(path)
  if not stat or stat.type ~= 'file' then
    fail(path .. ': expected a regular file for line counting')
  end
  local file, err = io.open(path, 'rb')
  if not file then
    fail(path .. ': ' .. err)
  end
  local count, last, first = 0, '', true
  while true do
    local chunk, read_err = file:read(65536)
    if not chunk then
      file:close()
      if read_err then
        fail(path .. ': ' .. read_err)
      end
      break
    end
    if first then
      chunk = chunk:gsub('^\239\187\191', '')
      first = false
    end
    local _, newlines = chunk:gsub('\n', '')
    count = count + newlines
    if #chunk > 0 then
      last = chunk:sub(-1)
    end
  end
  return count + ((last ~= '' and last ~= '\n') and 1 or 0)
end

function M.discover(directory)
  local stat, err, code = uv.fs_stat(directory)
  if not stat and code == 'ENOENT' then
    return {}, {}
  end
  if not stat then
    fail(directory .. ': ' .. err)
  end
  local works, errors = {}, {}
  local entries, scan_err = uv.fs_scandir(directory)
  if not entries then
    fail(directory .. ': ' .. scan_err)
  end
  while true do
    local name = uv.fs_scandir_next(entries)
    if not name then
      break
    end
    if name:sub(1, 1) ~= '.' then
      local path = directory .. '/' .. name
      local entry = uv.fs_lstat(path)
      if entry and entry.type == 'directory' then
        local ok, value = pcall(function()
          if name:find('[\\:%c]') then
            error('Lilt: invalid work directory name: ' .. path, 0)
          end
          return M.load(path)
        end)
        if ok then
          value.name = name
          works[#works + 1] = value
        else
          errors[#errors + 1] = tostring(value)
        end
      end
    end
  end
  table.sort(works, function(a, b)
    if a.title == b.title then
      return a.name < b.name
    end
    return a.title < b.title
  end)
  table.sort(errors)
  return works, errors
end

return M
