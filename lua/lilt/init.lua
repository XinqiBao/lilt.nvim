local session = require('lilt.session')
local M = {}
local data_home = vim.env.XDG_DATA_HOME
if not data_home or data_home:sub(1, 1) ~= '/' then
  data_home = vim.env.HOME .. '/.local/share'
end
local library_root = vim.fs.normalize(data_home .. '/lilt')
local catalog = require('lilt.online.catalog').default_url
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')

function M.setup(options)
  options = options or {}
  for key in pairs(options) do
    assert(key == 'library' or key == 'catalog', 'Lilt: unknown option ' .. tostring(key))
  end
  if options.library ~= nil then
    assert(
      type(options.library) == 'string' and options.library ~= '',
      'Lilt: library must be a path'
    )
    library_root = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(options.library), ':p'))
  end
  if options.catalog ~= nil then
    assert(
      type(options.catalog) == 'string'
        and options.catalog:match('^https://[^/%s?#@]+[^%s?#]*$')
        and not options.catalog:find('[@%c]'),
      'Lilt: catalog must be an HTTPS Gutendex server URL'
    )
    catalog = options.catalog:gsub('/+$', '')
  end
end

function M.open()
  require('lilt.picker').open(library_root, root .. '/examples', catalog)
end

local function switch(view)
  if not session.open(view) then
    vim.notify('Lilt: no active reading. Use :Lilt to choose a work.', vim.log.levels.INFO)
  end
end

function M.ghost()
  switch('ghost')
end

function M.split()
  switch('split')
end

M.close = session.close
return M
