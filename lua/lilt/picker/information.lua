-- Bibliographic presentation only. Callers own provenance, actions and resources.
local M = {}

function M.items(metadata, context)
  local items = {
    { label = metadata.title, hl = 'Title', wrap = 'full' },
    { label = context, wrap = 'full' },
  }
  local function field(label, values)
    if values and #values > 0 then
      items[#items + 1] = { label = label .. ': ' .. table.concat(values, '; '), wrap = 'full' }
    end
  end
  field(metadata.authors and #metadata.authors == 1 and 'Author' or 'Authors', metadata.authors)
  field('Translators', metadata.translators)
  field('Languages', metadata.languages)
  field('Subjects', metadata.subjects)
  field('Bookshelves', metadata.bookshelves)
  for _, pair in ipairs({
    { 'Publisher', 'publisher' },
    { 'Published', 'published' },
    { 'Description', 'description' },
    { 'Rights (source claim)', 'rights' },
    { 'License / rights URL', 'rights_url' },
  }) do
    local value = metadata[pair[2]]
    if value then
      items[#items + 1] = { label = pair[1] .. ': ' .. value, wrap = 'full' }
    end
  end
  if metadata.source then
    items[#items + 1] = { label = 'Source', hl = 'Title' }
    items[#items + 1] = {
      label = metadata.source.provider .. ':' .. metadata.source.id,
      wrap = 'full',
    }
    items[#items + 1] = { label = metadata.source.url, wrap = 'full' }
  end
  return items
end

return M
