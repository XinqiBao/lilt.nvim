-- Local file conversion. The caller owns downloading, attribution, and installation.
local work = require('lilt.work')
local M = {}
local writer = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h:h:h')
  .. '/pandoc/units.lua'
local install = 'Ensure Pandoc 3.1.1+ is installed on PATH: https://pandoc.org/installing.html'

-- Check before downloading. No version manager, shell, or persistent tool cache.
function M.check(callback)
  local cancelled, process = false, nil
  local function finish(err)
    vim.schedule(function()
      if not cancelled then
        callback(err)
      end
    end)
  end
  local ok, err = pcall(function()
    if vim.fn.executable('pandoc') ~= 1 then
      error('Lilt: EPUB conversion requires Pandoc. ' .. install, 0)
    end
    process = vim.system({ 'pandoc', '--version' }, { timeout = 5000 }, function(result)
      local major, minor, patch = (result.stdout or ''):match('^pandoc%s+(%d+)%.(%d+)%.?(%d*)')
      local supported = major
        and vim.version.ge({ tonumber(major), tonumber(minor), tonumber(patch) or 0 }, { 3, 1, 1 })
      finish(
        (result.code ~= 0 or not supported)
            and ('Lilt: Pandoc is unavailable or older than 3.1.1. ' .. install)
          or nil
      )
    end)
  end)
  if not ok then
    finish(tostring(err))
  end
  return function()
    cancelled = true
    if process then
      process:kill(15)
    end
  end
end

-- Punctuation is a reading-copy policy, applied after structural conversion.
local function reference(lines, plain_quotes)
  if not plain_quotes then
    return lines
  end
  return vim.tbl_map(function(line)
    return (line:gsub('“', '"'):gsub('”', '"'):gsub('‘', "'"):gsub('’', "'"))
  end, lines)
end

-- Create a new standard work, never overwrite an existing destination. Options
-- carry manifest metadata, optional plain_quotes, and an optional Pandoc filter.
-- The input is unchanged; the caller retains any source archive and credits.
function M.prepare(path, directory, options, callback)
  local cancelled, process, created = false, nil, false
  local output = vim.fn.tempname()
  local function cleanup()
    vim.fn.delete(output)
  end
  local ok, err = pcall(function()
    if vim.uv.fs_lstat(directory) then
      error('Lilt: conversion destination already exists: ' .. directory, 0)
    end
    local input = vim.uv.fs_realpath(path)
    local input_stat = input and vim.uv.fs_stat(input)
    if not input_stat or input_stat.type ~= 'file' then
      error('Lilt: expected a local EPUB file: ' .. path, 0)
    end
    local args = {
      'pandoc',
      '--sandbox',
      '--from=epub',
      '--to=' .. writer,
      '--metadata=lilt-title:' .. options.title,
      '--output=' .. output,
    }
    if options.filter then
      args[#args + 1] = '--lua-filter=' .. options.filter
    end
    args[#args + 1] = input
    process = vim.system(args, { timeout = 45000 }, function(result)
      vim.schedule(function()
        if cancelled then
          cleanup()
          return
        end
        local prepared, value = pcall(function()
          if result.code ~= 0 then
            error('Lilt: EPUB preparation failed: ' .. vim.trim(result.stderr), 0)
          end
          local stat = vim.uv.fs_stat(output)
          if not stat or stat.size > 48 * 1024 * 1024 then
            error('Lilt: prepared text is missing or exceeds 48 MiB', 0)
          end
          local units = vim.json.decode(table.concat(work.read(output), '\n'))
          if type(units) ~= 'table' or not vim.islist(units) or #units == 0 then
            error('Lilt: invalid EPUB preparation result', 0)
          end
          if vim.fn.mkdir(directory) ~= 1 then
            error('Lilt: cannot create conversion destination: ' .. directory, 0)
          end
          created = true
          local manifest = {
            title = options.title,
            author = options.author,
            source = options.source,
            units = {},
          }
          for i, unit in ipairs(units) do
            local filename = string.format('%03d.txt', i)
            if
              vim.fn.writefile(
                reference(unit.lines, options.plain_quotes),
                directory .. '/' .. filename
              ) ~= 0
            then
              error('Lilt: cannot write reading unit', 0)
            end
            manifest.units[i] = { title = unit.title, path = filename }
          end
          if vim.fn.writefile({ vim.json.encode(manifest) }, directory .. '/lilt.json') ~= 0 then
            error('Lilt: cannot write manifest', 0)
          end
          return work.validate(directory)
        end)
        cleanup()
        if not prepared and created then
          if vim.fn.delete(directory, 'rf') ~= 0 then
            value = tostring(value) .. '\nCould not remove conversion output: ' .. directory
          end
        end
        if prepared then
          callback(nil, value)
        else
          callback(tostring(value))
        end
      end)
    end)
  end)
  if not ok then
    cleanup()
    vim.schedule(function()
      if not cancelled then
        callback(tostring(err))
      end
    end)
  end
  return function()
    cancelled = true
    if process then
      process:kill(15)
    end
    cleanup()
  end
end

return M
