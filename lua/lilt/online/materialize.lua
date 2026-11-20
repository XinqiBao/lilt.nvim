-- Source-neutral preparation inside an acquisition-owned temporary directory.
local work = require('lilt.work')
local request = require('lilt.online.request')
local epub = require('lilt.import.epub')
local M = {}

local function checked(value, message)
  if not value then
    error('Lilt: ' .. tostring(message), 0)
  end
  return value
end

local function prepared(manifest, warnings)
  return { manifest = manifest, snapshot = {}, attribution = {}, import_warnings = warnings or {} }
end

function M.epub(url, directory, metadata, options, callback)
  local cancelled, cancel_step = false, nil
  -- The converter requires an absent output directory. Keep its input beside
  -- that directory until conversion completes, then retain it inside the work.
  local source = directory .. '.epub'
  local function finish(err, result)
    vim.fn.delete(source)
    if not cancelled then
      callback(err, result)
    end
  end
  cancel_step = epub.check(function(tool_error)
    if cancelled then
      return
    end
    if tool_error then
      finish(tool_error)
      return
    end
    cancel_step = request(url, function(err, path)
      if cancelled then
        return
      end
      if err then
        finish(err)
        return
      end
      local copied, copy_error = pcall(function()
        checked(vim.uv.fs_copyfile(path, source, { excl = true }))
      end)
      if not copied then
        finish(tostring(copy_error))
        return
      end
      local settings = vim.tbl_extend('force', metadata, options)
      cancel_step = epub.prepare(source, directory, settings, function(prepare_error, reading)
        if cancelled then
          return
        end
        if prepare_error then
          finish(prepare_error)
          return
        end
        local ok, result = pcall(function()
          checked(vim.uv.fs_rename(source, directory .. '/SOURCE.epub'))
          local manifest = vim.tbl_extend('force', reading.manifest, metadata)
          manifest.source = vim.tbl_extend('force', metadata.source, { file = 'SOURCE.epub' })
          return prepared(manifest, reading.import_warnings)
        end)
        if ok then
          finish(nil, result)
        else
          finish(tostring(result))
        end
      end)
    end)
  end)
  return function()
    cancelled = true
    if cancel_step then
      cancel_step()
    end
    vim.fn.delete(source)
  end
end

function M.text(lines, directory, metadata)
  checked(type(lines) == 'table' and vim.islist(lines), 'expected an array of text rows')
  for _, line in ipairs(lines) do
    checked(type(line) == 'string' and not line:find('[\r\n%z]'), 'invalid plain-text row')
  end
  checked(not vim.uv.fs_lstat(directory), 'preparation destination already exists')
  checked(vim.fn.mkdir(directory) == 1, 'cannot create preparation directory')
  local path = directory .. '/001.txt'
  checked(vim.fn.writefile(lines, path) == 0, 'cannot write reading unit')
  -- The normal work reader also validates UTF-8/NUL. Readback detects its BOM
  -- handling rather than silently changing the first source row.
  checked(vim.deep_equal(work.read(path), lines), 'plain-text rows changed during preparation')
  local manifest = vim.tbl_extend('force', metadata, {
    version = 1,
    units = { { title = metadata.title, path = '001.txt' } },
    preparation = { plain_quotes = false },
  })
  return prepared(manifest)
end

return M
