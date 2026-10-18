-- EPUB container and navigation reader. Pandoc still parses every XHTML document.
-- selene: allow(global_usage)
local pandoc = _G.pandoc
local directory = debug.getinfo(1, 'S').source:sub(2):match('^(.*)/')
local xml = dofile(directory .. '/xml.lua')
local opf = 'http://www.idpf.org/2007/opf'
local xhtml = 'http://www.w3.org/1999/xhtml'
local ops = 'http://www.idpf.org/2007/ops'
local ncx = 'http://www.daisy.org/z3986/2005/ncx/'

local function child(node, name, namespace)
  return xml.children(node, name, namespace)[1]
end

local function token(value, word)
  return (' ' .. (value or ''):gsub('%s+', ' ') .. ' '):find(' ' .. word .. ' ', 1, true)
end

local function decode(value)
  return (value:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

-- Resolve publication URLs in memory. Nothing is extracted to the filesystem.
local function resolve(base, href)
  if not href or href:find('^%a[%w+.-]*:') or href:sub(1, 2) == '//' then
    return
  end
  local path, fragment = href:match('^([^#]*)#?(.*)$')
  if path:find('?', 1, true) then
    return
  end
  path = decode(path)
  if path == '' then
    path = base
  elseif path:sub(1, 1) ~= '/' then
    path = (base:match('^(.*)/') or '') .. '/' .. path
  end
  local parts = {}
  for part in path:gmatch('[^/]+') do
    if part == '..' then
      if #parts == 0 then
        return
      end
      table.remove(parts)
    elseif part ~= '.' then
      parts[#parts + 1] = part
    end
  end
  path = table.concat(parts, '/')
  if path == '' or path:find('[%c\\]') then
    return
  end
  return path, decode(fragment)
end

local function identity(path, fragment)
  -- Escape the separator in filenames; fragments may themselves contain '#'.
  return (path:gsub('%%', '%%25'):gsub('#', '%%23'))
    .. ((fragment and fragment ~= '') and ('#' .. fragment) or '')
end

local function navigation(doc, path)
  local function find(node)
    if
      node.name == 'nav'
      and node.namespace == xhtml
      and token(xml.attr(node, 'type', ops), 'toc')
    then
      return node
    end
    for _, value in ipairs(node.children) do
      if type(value) == 'table' then
        local found = find(value)
        if found then
          return found
        end
      end
    end
  end
  local function list(ol)
    local result = {}
    for _, li in ipairs(ol and xml.children(ol, 'li', xhtml) or {}) do
      local label = child(li, 'a', xhtml) or child(li, 'span', xhtml)
      local nested = list(child(li, 'ol', xhtml))
      local href = label and xml.attr(label, 'href')
      local target, fragment = resolve(path, href)
      local title = label and xml.text(label) or ''
      if title ~= '' then
        result[#result + 1] = {
          title = title,
          target = target and identity(target, fragment),
          children = nested,
        }
      else
        for _, node in ipairs(nested) do
          result[#result + 1] = node
        end
      end
    end
    return result
  end
  local toc = find(doc)
  return toc and list(child(toc, 'ol', xhtml)) or {}
end

local function legacy(doc, path)
  local function list(parent)
    local result = {}
    for _, point in ipairs(parent and xml.children(parent, 'navPoint', ncx) or {}) do
      local label = child(point, 'navLabel', ncx)
      local content = child(point, 'content', ncx)
      local target, fragment = resolve(path, content and xml.attr(content, 'src'))
      local title = label and xml.text(label) or ''
      local nested = list(point)
      if title ~= '' then
        result[#result + 1] = {
          title = title,
          target = target and identity(target, fragment),
          children = nested,
        }
      else
        for _, node in ipairs(nested) do
          result[#result + 1] = node
        end
      end
    end
    return result
  end
  return list(child(doc, 'navMap', ncx))
end

-- selene: allow(global_usage)
_G.ByteStringReader = function(input)
  local entries, total = {}, 0
  for _, entry in ipairs(pandoc.zip.Archive(input).entries) do
    assert(not entries[entry.path], 'duplicate EPUB archive path')
    entries[entry.path] = entry
  end
  local function read(path)
    local entry = assert(entries[path], 'missing EPUB resource: ' .. tostring(path))
    local text = entry:contents()
    total = total + #text
    assert(total <= 48 * 1024 * 1024, 'EPUB content exceeds 48 MiB')
    return text
  end
  local container = xml.parse(read('META-INF/container.xml'))
  local namespace = 'urn:oasis:names:tc:opendocument:xmlns:container'
  local roots = assert(child(container, 'rootfiles', namespace), 'missing EPUB rootfiles')
  local root = assert(child(roots, 'rootfile', namespace), 'missing EPUB rootfile')
  local package_path = assert(resolve('', xml.attr(root, 'full-path')), 'invalid EPUB package path')
  local package = xml.parse(read(package_path))
  local manifest = assert(child(package, 'manifest', opf), 'missing EPUB manifest')
  local spine = assert(child(package, 'spine', opf), 'missing EPUB spine')
  local items, nav, old = {}, nil, nil
  for _, item in ipairs(xml.children(manifest, 'item', opf)) do
    local id = xml.attr(item, 'id')
    local path = resolve(package_path, xml.attr(item, 'href'))
    assert(id and path and not items[id], 'invalid EPUB manifest item')
    items[id] = { path = path, media = xml.attr(item, 'media-type') }
    if not nav and token(xml.attr(item, 'properties'), 'nav') then
      nav = items[id]
    end
    if items[id].media == 'application/x-dtbncx+xml' then
      old = items[id]
    end
  end
  old = items[xml.attr(spine, 'toc')] or old
  local warnings = {}
  local function toc(item, parse)
    if not item then
      return {}
    end
    local ok, value = pcall(function()
      return parse(xml.parse(read(item.path)), item.path)
    end)
    if ok then
      return value
    end
    warnings[1] = 'Could not read EPUB navigation; using available structure.'
    return {}
  end
  local catalogs = { nav = toc(nav, navigation), ncx = toc(old, legacy), warnings = warnings }
  local blocks, rendered = {}, {}
  for _, ref in ipairs(xml.children(spine, 'itemref', opf)) do
    if xml.attr(ref, 'linear') ~= 'no' then
      local item = assert(items[xml.attr(ref, 'idref')], 'missing EPUB spine item')
      assert(not rendered[item.path], 'duplicate EPUB spine document')
      rendered[item.path] = true
      if item.media == 'application/xhtml+xml' or item.media == 'text/html' then
        local doc =
          pandoc.read(read(item.path), 'html+epub_html_exts+raw_html-auto_identifiers-line_blocks')
        local function scoped(element)
          if element.t == 'Link' then
            local path, fragment = resolve(item.path, element.target)
            if path then
              element.target = '#' .. identity(path, fragment)
            end
          end
          if element.identifier and element.identifier ~= '' then
            element.identifier = identity(item.path, element.identifier)
          end
          return element
        end
        doc = doc:walk({ Inline = scoped, Block = scoped })
        blocks[#blocks + 1] = pandoc.Div(doc.blocks, pandoc.Attr(identity(item.path)))
      elseif not item.media or not item.media:match('^image/') then
        error('unsupported EPUB spine resource: ' .. tostring(item.media))
      end
    end
  end
  return pandoc.Pandoc(
    blocks,
    { ['lilt-navigation'] = pandoc.MetaString(pandoc.json.encode(catalogs)) }
  )
end
