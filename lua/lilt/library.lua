local uv = vim.uv
local work = require('lilt.work')
local M = {}

local function checked(value, err)
  if not value then
    error('Lilt: ' .. tostring(err), 0)
  end
  return value
end

local function validate_name(name)
  if name == '' or name:sub(1, 1) == '.' or name:find('[/\\:%c]') or #name > 240 then
    error('Lilt: choose a nonhidden work directory with a portable name: ' .. name, 0)
  end
end

function M.find_source(root, source)
  if not source then
    return nil
  end
  local found
  local readings = work.discover(root .. '/references')
  for _, reading in ipairs(readings) do
    if
      reading.source
      and reading.source.provider == source.provider
      and reading.source.id == source.id
    then
      if found then
        error('Lilt: multiple library copies of source ' .. source.provider .. ':' .. source.id, 0)
      end
      found = reading
    end
  end
  return found
end

-- Check before downloading/copying and again immediately before publication.
function M.available(root, name, source)
  validate_name(name)
  for _, path in ipairs({ root .. '/references/' .. name, root .. '/manuscripts/' .. name }) do
    local stat, err, code = uv.fs_lstat(path)
    if stat then
      error('Lilt: work name already exists: ' .. name, 0)
    end
    if code ~= 'ENOENT' then
      error('Lilt: ' .. tostring(err), 0)
    end
  end
  local existing = M.find_source(root, source)
  if existing then
    error('Lilt: source already installed as ' .. existing.name, 0)
  end
end

local function scan(path)
  return checked(uv.fs_scandir(path))
end

local function copy(source, target)
  local entries = scan(source)
  while true do
    local name = uv.fs_scandir_next(entries)
    if not name then
      return
    end
    local from, to = source .. '/' .. name, target .. '/' .. name
    local stat = checked(uv.fs_lstat(from))
    if stat.type == 'directory' then
      checked(uv.fs_mkdir(to, 493)) -- 0755, subject to umask
      copy(from, to)
    elseif stat.type == 'file' then
      checked(uv.fs_copyfile(from, to, { excl = true }))
    else
      error('Lilt: cannot copy symlink or special file: ' .. from, 0)
    end
  end
end

-- Copy all work files (including attribution), then validate the copy before
-- publishing it. Hidden staging directories never appear as library works.
function M.add(root, directory, name)
  local source = work.load(directory)
  name = name or vim.fn.fnamemodify(source.root, ':t')
  M.available(root, name, source.source)
  vim.fn.mkdir(root .. '/references', 'p')
  local references = checked(uv.fs_realpath(root .. '/references'))
  if references == source.root or references:sub(1, #source.root + 1) == source.root .. '/' then
    error('Lilt: the library reference tree cannot be inside the source work', 0)
  end
  local destination = references .. '/' .. name
  local staging = checked(uv.fs_mkdtemp(references .. '/.lilt-XXXXXX'))
  local ok, result = pcall(function()
    copy(source.root, staging)
    local installed = work.validate(staging)
    -- A readable source manifest may be read-only; format our owned copy.
    checked(uv.fs_unlink(staging .. '/lilt.json'))
    require('lilt.json').write(staging .. '/lilt.json', installed.manifest)
    M.available(root, name, installed.source)
    checked(uv.fs_rename(staging, destination))
    installed.root, installed.name = destination, name
    for _, unit in ipairs(installed.units) do
      unit.reference = destination .. '/' .. unit.path
    end
    return installed
  end)
  if not ok then
    if vim.fn.delete(staging, 'rf') ~= 0 then
      result = tostring(result) .. '\nCould not remove staging directory: ' .. staging
    end
    error(result, 0)
  end
  return result
end

function M.manuscript(root, reading, unit)
  return root .. '/manuscripts/' .. reading.name .. '/' .. unit.path
end

-- Only saved files count. An empty file has zero rows; use a denominator of one
-- for an empty reference so progress is always finite, including extra writing.
function M.progress(root, reading, unit)
  local path = M.manuscript(root, reading, unit)
  local stat, err, code = uv.fs_stat(path)
  if not stat and code == 'ENOENT' then
    return nil
  end
  checked(stat, err)
  return math.floor(100 * work.count_lines(path) / math.max(1, work.count_lines(unit.reference)))
end

return M
