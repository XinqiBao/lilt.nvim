-- Small DOM adapter around SLAXML. XML is metadata, never fetched or executed.
local directory = debug.getinfo(1, 'S').source:sub(2):match('^(.*)/')
local parser = dofile(directory .. '/vendor/slaxml.lua')
local M = {}

function M.parse(text)
  assert(#text <= 4 * 1024 * 1024, 'EPUB XML exceeds 4 MiB')
  local root, stack = nil, {}
  parser
    :parser({
      startElement = function(name, namespace)
        assert(#stack < 64, 'EPUB XML nesting exceeds 64 levels')
        local node = { name = name, namespace = namespace, attrs = {}, children = {} }
        if #stack == 0 then
          assert(not root, 'multiple XML roots')
          root = node
        else
          table.insert(stack[#stack].children, node)
        end
        table.insert(stack, node)
      end,
      attribute = function(name, value, namespace)
        stack[#stack].attrs[(namespace or '') .. ':' .. name] = value
      end,
      text = function(value)
        if #stack > 0 then
          table.insert(stack[#stack].children, value)
        end
      end,
      closeElement = function(name, namespace)
        local node = table.remove(stack)
        assert(node and node.name == name and node.namespace == namespace, 'mismatched XML close')
      end,
    })
    :parse(text)
  assert(root and #stack == 0, 'incomplete XML')
  return root
end

function M.attr(node, name, namespace)
  return node.attrs[(namespace or '') .. ':' .. name]
end

function M.children(node, name, namespace)
  local result = {}
  for _, child in ipairs(node.children) do
    if type(child) == 'table' and child.name == name and child.namespace == namespace then
      result[#result + 1] = child
    end
  end
  return result
end

function M.text(node)
  local parts = {}
  local function visit(value)
    if type(value) == 'string' then
      parts[#parts + 1] = value
    else
      if value.name == 'img' then
        parts[#parts + 1] = M.attr(value, 'alt') or ''
      end
      for _, child in ipairs(value.children) do
        visit(child)
      end
    end
  end
  visit(node)
  return (table.concat(parts):gsub('%s+', ' '):match('^%s*(.-)%s*$'))
end

return M
