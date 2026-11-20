-- Acquisition owns staging and publication; providers own source preparation.
local library = require('lilt.library')
local names = require('lilt.name')
local json = require('lilt.json')
local work = require('lilt.work')
local M = {}

function M.existing(root, entry)
  return library.find_source(root, entry.source)
end

function M.acquire(root, provider, entry, callback, name)
  local cancelled, finished, cancel_step, staging = false, false, nil, nil
  local selected_source = vim.deepcopy(entry.source)
  local function cleanup()
    if staging and vim.uv.fs_lstat(staging) and vim.fn.delete(staging, 'rf') ~= 0 then
      vim.notify('Lilt: could not remove acquisition staging: ' .. staging, vim.log.levels.WARN)
    end
  end
  local function finish(err, value)
    if finished then
      return
    end
    finished = true
    cleanup()
    if not cancelled then
      callback(err, value)
    end
  end
  -- Defer even immediate reuse/errors so callers can install their cancel handle.
  vim.schedule(function()
    if cancelled then
      return
    end
    local ok, err = pcall(function()
      if not entry.source or entry.source.provider ~= provider.id then
        error('Lilt: selected source does not match provider', 0)
      end
      local installed = M.existing(root, entry)
      if installed then
        finish(nil, installed)
        return
      end
      name = name or names.work(entry.title, entry.source)
      library.available(root, name, entry.source)
      if not entry.supported then
        error('Lilt: ' .. (entry.availability or 'this source entry is unavailable'), 0)
      end
      staging = vim.fn.tempname()
      assert(vim.fn.mkdir(staging) == 1, 'Lilt: cannot create acquisition staging directory')
      local directory = staging .. '/work'
      cancel_step = provider.prepare(entry, directory, function(prepare_error, prepared)
        if cancelled or finished then
          return
        end
        if prepare_error then
          finish(prepare_error)
          return
        end
        local installed_ok, result = pcall(function()
          local manifest = prepared.manifest
          local source = manifest.source
          if
            not source
            or source.provider ~= selected_source.provider
            or source.id ~= selected_source.id
          then
            error('Lilt: prepared source identity does not match selection', 0)
          end
          assert(source.file, 'Lilt: prepared work must retain its original source artifact')
          json.write(directory .. '/lilt.json', manifest)
          json.write(directory .. '/SOURCE.json', prepared.snapshot)
          local lines = {
            manifest.title,
            table.concat(manifest.authors or {}, '; '),
            '',
            'Source: ' .. provider.name .. ' · ' .. source.id,
            source.url,
            '',
          }
          if source.version then
            lines[#lines + 1] = 'Source version: ' .. source.version
          end
          if source.title then
            lines[#lines + 1] = 'Source copy title: ' .. source.title
          end
          for _, field in ipairs({
            { 'Rights (source claim)', 'rights' },
            { 'License / rights URL', 'rights_url' },
            { 'Publisher', 'publisher' },
            { 'Published', 'published' },
            { 'Description', 'description' },
          }) do
            if manifest[field[2]] then
              vim.list_extend(
                lines,
                vim.split(field[1] .. ': ' .. manifest[field[2]], '\n', { plain = true })
              )
            end
          end
          if manifest.preparation then
            local preparation = manifest.preparation
            if preparation.wrap_columns then
              lines[#lines + 1] = 'Prose wrap columns: ' .. preparation.wrap_columns
            end
            if preparation.plain_quotes ~= nil then
              lines[#lines + 1] = 'Plain quotes: ' .. (preparation.plain_quotes and 'yes' or 'no')
            end
          end
          vim.list_extend(lines, prepared.attribution)
          vim.list_extend(lines, prepared.import_warnings or {})
          assert(
            vim.fn.writefile(lines, directory .. '/README.txt') == 0,
            'Lilt: cannot write attribution'
          )
          work.validate(directory)
          local reading = library.add(root, directory, name)
          reading.import_warnings = prepared.import_warnings
          return reading
        end)
        if installed_ok then
          finish(nil, result)
        else
          finish(tostring(result))
        end
      end)
    end)
    if not ok then
      finish(tostring(err))
    end
  end)
  return function()
    cancelled = true
    if cancel_step then
      cancel_step()
    end
    cleanup()
  end
end

return M
