-- Pandoc writer: local reading units and a separate source navigation tree.
-- selene: allow(global_usage)
local pandoc = _G.pandoc

local function clean(text)
  return (text:gsub('%s+', ' '):match('^%s*(.-)%s*$'))
end

local function rows(text)
  local result = {}
  for line in (text .. '\n'):gmatch('(.-)\n') do
    result[#result + 1] = line
  end
  while #result > 0 and not result[#result]:find('%S') do
    table.remove(result)
  end
  while #result > 0 and not result[1]:find('%S') do
    table.remove(result, 1)
  end
  return result
end

local function identifiers(block)
  local result = {}
  local function collect(element)
    if element.identifier and element.identifier ~= '' then
      result[element.identifier] = true
    end
  end
  collect(block)
  block:walk({ Inline = collect, Block = collect })
  return result
end

local function heading_label(block)
  local label = block:walk({
    Span = function(span)
      if span.classes:includes('caption') then
        return {}
      end
    end,
  })
  return clean(pandoc.utils.stringify(label.content))
end

-- selene: allow(global_usage)
_G.Writer = function(doc)
  if not pandoc.json then
    error('Lilt: EPUB conversion requires Pandoc 3.1.1 or newer')
  end
  doc = doc:walk({
    Image = function()
      return {}
    end,
    HorizontalRule = function()
      return {}
    end,
  })
  local catalogs = doc.meta['lilt-navigation']
      and pandoc.json.decode(pandoc.utils.stringify(doc.meta['lilt-navigation']))
    or {}
  -- Resolve against cleaned, readable content. A removed distribution footer or
  -- an empty image wrapper must not become an action pointing at another unit.
  local available, labels = {}, {}
  local function collect(block)
    if clean(pandoc.utils.stringify(block)) == '' then
      return
    end
    if block.t == 'Header' then
      labels[block.identifier] =
        { raw = clean(pandoc.utils.stringify(block.content)), title = heading_label(block) }
    end
    if block.t == 'Div' then
      available[block.identifier] = true
      for _, nested in ipairs(block.content) do
        collect(nested)
      end
    else
      for id in pairs(identifiers(block)) do
        available[id] = true
      end
    end
  end
  for _, block in ipairs(doc.blocks) do
    collect(block)
  end
  local function usable(nodes)
    local result = {}
    for _, node in ipairs(nodes or {}) do
      local children = usable(node.children)
      local target = available[node.target] and node.target or nil
      if target or #children > 0 then
        local label = labels[target]
        local title = label and label.raw == node.title and label.title ~= '' and label.title
          or node.title
        result[#result + 1] = { title = title, target = target, children = children }
      end
    end
    return result
  end
  local toc = usable(catalogs.nav)
  if #toc == 0 then
    toc = usable(catalogs.ncx)
  end
  local targets, order = {}, 0
  local function index(nodes)
    for _, node in ipairs(nodes) do
      if node.target then
        order = order + 1
        targets[node.target] = targets[node.target] or { title = node.title, order = order }
      end
      index(node.children)
    end
  end
  index(toc)

  local units, blocks, anchors, locations, has_body = {}, {}, {}, {}, false
  local primary
  local title = clean(pandoc.utils.stringify(doc.meta['lilt-title'] or doc.meta.title or ''))
  if title == '' then
    title = 'Reading'
  end
  local function flush(force)
    if #blocks == 0 or (not has_body and not force) then
      return
    end
    local function text_only(element)
      if element.attr then
        element.attr = pandoc.Attr()
      end
      return element
    end
    local rendered = pandoc.Pandoc(blocks):walk({ Inline = text_only, Block = text_only })
    local lines = rows(pandoc.write(rendered, 'plain', { columns = 72, wrap_text = 'auto' }))
    local parts, first = {}, 1
    while first <= #lines do
      local last = #lines
      for i = first + 299, #lines - 80 do
        if not lines[i]:find('%S') then
          last = i
          break
        end
      end
      local part = {}
      for i = first, last do
        part[#part + 1] = lines[i]
      end
      while #part > 0 and not part[#part]:find('%S') do
        table.remove(part)
      end
      if #part > 0 then
        parts[#parts + 1] = part
      end
      first = last + 1
      while first <= #lines and not lines[first]:find('%S') do
        first = first + 1
      end
    end
    local location = { first = #units + 1, count = #parts, primary = primary }
    if #parts > 0 then
      for id in pairs(anchors) do
        locations[id] = location
      end
    end
    for i, part in ipairs(parts) do
      units[#units + 1] = { title = #parts > 1 and (title .. ' · ' .. i) or title, lines = part }
    end
    blocks, anchors, has_body, primary = {}, {}, false, nil
  end
  local function boundary(ids)
    local chosen, target_id
    for id in pairs(ids) do
      local target = targets[id]
      if target and (not chosen or target.order < chosen.order) then
        chosen = target
        target_id = id
      end
    end
    if chosen then
      flush()
      title = chosen.title
      -- Heading-only starts can share one text unit. The target nearest its
      -- body owns the reading parts; earlier starts remain simple aliases.
      primary = target_id
    end
    for id in pairs(ids) do
      if targets[id] then
        anchors[id] = true
      end
    end
  end
  local function expand(block)
    if block.t == 'Header' then
      return true
    elseif block.t == 'Div' then
      if targets[block.identifier] then
        return true
      end
      for _, value in ipairs(block.content) do
        if expand(value) then
          return true
        end
      end
      for id in pairs(identifiers(block)) do
        if targets[id] then
          return true
        end
      end
    end
    return false
  end
  local seen_heading = false
  local function visit(items)
    for _, block in ipairs(items) do
      if block.t == 'Div' and expand(block) then
        boundary({ [block.identifier] = true })
        visit(block.content)
      elseif block.t == 'Header' then
        local heading = heading_label(block)
        if heading ~= '' then
          if not seen_heading then
            title = 'Front matter'
          end
          flush()
          seen_heading, title = true, heading
        end
        boundary(identifiers(block))
        blocks[#blocks + 1] = block
      else
        -- Inline targets enter at their enclosing block's start, retaining the
        -- whole paragraph/table/verse rather than cutting authored text apart.
        boundary(identifiers(block))
        blocks[#blocks + 1] = block
        has_body = has_body or clean(pandoc.utils.stringify(block)) ~= ''
      end
    end
  end
  visit(doc.blocks)
  flush(true)
  if #units == 0 then
    error('Lilt: EPUB has no readable text')
  end
  local expanded = {}
  local function mapped(nodes)
    local result = {}
    for _, node in ipairs(nodes) do
      local children = mapped(node.children)
      local location = locations[node.target]
      local target
      if
        location
        and (location.count == 1 or location.primary ~= node.target or expanded[location])
      then
        target = location.first
      elseif location then
        expanded[location] = true
        local parts = {}
        for i = 1, location.count do
          parts[#parts + 1] =
            { title = 'Part ' .. i .. ' of ' .. location.count, unit = location.first + i - 1 }
        end
        for _, nested in ipairs(children) do
          parts[#parts + 1] = nested
        end
        children = parts
      end
      if target or #children > 0 then
        result[#result + 1] =
          { title = node.title, unit = target, children = #children > 0 and children or nil }
      end
    end
    return result
  end
  local navigation = mapped(toc)
  return pandoc.json.encode({
    units = units,
    toc = #navigation > 0 and navigation or nil,
    warnings = catalogs.warnings,
  })
end
