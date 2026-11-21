-- Bibliographic presentation only. Callers own provenance, actions and resources.
local M = {}

local function field(items, label, values)
  if values and #values > 0 then
    items[#items + 1] = { label = label .. ': ' .. table.concat(values, '; '), wrap = 'full' }
  end
end

function M.identity(metadata, context)
  local items = {
    { label = metadata.title, hl = 'Title', wrap = 'full' },
    { label = context, wrap = 'full' },
  }
  field(
    items,
    metadata.authors and #metadata.authors == 1 and 'Author' or 'Authors',
    metadata.authors
  )
  return items
end

function M.fields(metadata)
  local items = {}
  field(items, 'Translators', metadata.translators)
  field(items, 'Languages', metadata.languages)
  field(items, 'Subjects', metadata.subjects)
  field(items, 'Bookshelves', metadata.bookshelves)
  for _, pair in ipairs({
    { 'Publisher', 'publisher' },
    { 'Published', 'published' },
    { 'Description', 'description' },
    { 'Rights (source claim)', 'rights' },
    { 'License / rights URL', 'rights_url' },
  }) do
    local value = metadata[pair[2]]
    if value then
      local lines = pair[2] == 'description' and vim.split(value, '\n', { plain = true })
        or { value }
      lines[1] = pair[1] .. ': ' .. lines[1]
      for _, line in ipairs(lines) do
        items[#items + 1] = { label = line, wrap = 'full' }
      end
    end
  end
  if metadata.source then
    items[#items + 1] = { label = 'Source', hl = 'Title' }
    items[#items + 1] = {
      label = require('lilt.online.providers').name(metadata.source.provider),
      wrap = 'full',
    }
    items[#items + 1] = {
      label = metadata.source.provider .. ':' .. metadata.source.id,
      wrap = 'full',
    }
    items[#items + 1] = { label = metadata.source.url, wrap = 'full' }
    if metadata.source.version then
      items[#items + 1] = { label = 'Source version: ' .. metadata.source.version, wrap = 'full' }
    end
    if metadata.source.title then
      items[#items + 1] = { label = 'Source copy title: ' .. metadata.source.title, wrap = 'full' }
    end
  end
  return items
end

function M.items(metadata, context)
  return vim.list_extend(M.identity(metadata, context), M.fields(metadata))
end

return M
