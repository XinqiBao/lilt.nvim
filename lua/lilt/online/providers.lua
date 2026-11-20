local M = {}

function M.list(catalog)
  return { require('lilt.online.providers.gutenberg').new(catalog) }
end

function M.name(id)
  for _, provider in ipairs(M.list()) do
    if provider.id == id then
      return provider.name
    end
  end
  return id
end

return M
