local session = require('lilt.session')
local manuscript = require('lilt.manuscript')
local work = require('lilt.work')
local library = require('lilt.library')
local M = {}
local sample
local library_root = vim.fn.expand('~/Lilt')
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')

function M.setup(options)
  options = options or {}
  for key in pairs(options) do
    assert(key == 'library', 'Lilt: unknown option ' .. tostring(key))
  end
  if options.library ~= nil then
    assert(
      type(options.library) == 'string' and options.library ~= '',
      'Lilt: library must be a path'
    )
    library_root = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(options.library), ':p'))
  end
end

-- Native UI callbacks run later, outside the command's error boundary.
local function safely(callback)
  return function(...)
    local ok, err = pcall(callback, ...)
    if not ok then
      vim.notify(tostring(err), vim.log.levels.ERROR)
    end
  end
end

local function select_unit(root_path, reading)
  local items = {}
  for _, unit in ipairs(reading.units) do
    local progress = library.progress(root_path, reading, unit)
    items[#items + 1] = {
      unit = unit,
      label = unit.title .. '  ' .. (progress and (progress .. '%') or '—'),
    }
  end
  vim.ui.select(
    items,
    {
      prompt = reading.title,
      format_item = function(item)
        return item.label
      end,
    },
    safely(function(item)
      if not item then
        return
      end
      local reference = work.read(item.unit.reference)
      local buf = manuscript.open(library.manuscript(root_path, reading, item.unit))
      session.open('ghost', { manuscript = buf, reference = reference })
    end)
  )
end

function M.open()
  safely(function()
    local root_path = library_root
    local works, errors = library.list(root_path)
    if #errors > 0 then
      vim.notify(table.concat(errors, '\n'), vim.log.levels.WARN)
    end
    local items = {}
    for _, reading in ipairs(works) do
      items[#items + 1] =
        { reading = reading, label = reading.title .. ' [' .. reading.name .. ']' }
    end
    items[#items + 1] = { action = 'add', label = 'Add local work…' }
    items[#items + 1] = { action = 'example', label = 'Example: Alice (temporary manuscript)' }
    vim.ui.select(
      items,
      {
        prompt = 'Lilt · Library',
        format_item = function(item)
          return item.label
        end,
      },
      safely(function(item)
        if not item then
          return
        end
        if item.reading then
          select_unit(root_path, item.reading)
        elseif item.action == 'add' then
          vim.ui.input(
            { prompt = 'Local work directory: ', completion = 'dir' },
            safely(function(directory)
              if not directory or directory == '' then
                return
              end
              select_unit(root_path, library.add(root_path, vim.fn.expand(directory)))
            end)
          )
        else
          M.example()
        end
      end)
    )
  end)()
end

function M.example(view)
  local example = work.load(root .. '/samples')
  if not sample or not vim.api.nvim_buf_is_valid(sample) then
    sample = manuscript.open()
  end
  session.open(view or 'ghost', {
    manuscript = sample,
    reference = work.read(example.units[1].reference),
  })
end

function M.ghost()
  if not session.open('ghost') then
    M.example('ghost')
  end
end

function M.split()
  if not session.open('split') then
    M.example('split')
  end
end

M.close = session.close
return M
