-- Pandoc custom writer: EPUB structure to Lilt reading units. No network or files.
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

-- selene: allow(global_usage)
_G.Writer = function(doc)
  if not pandoc.json then
    error('Lilt: EPUB conversion requires Pandoc 3.1.1 or newer')
  end
  doc = doc:walk({
    -- Images remain in the input EPUB. Never fetch linked assets or turn
    -- alt text into mysterious reference text or chapter-name fragments.
    Image = function()
      return {}
    end,
    HorizontalRule = function()
      return {}
    end,
  })
  local units, blocks, has_body = {}, {}, false
  local title = clean(pandoc.utils.stringify(doc.meta['lilt-title'] or doc.meta.title))
  local function flush(force)
    if #blocks == 0 or (not has_body and not force) then
      return
    end
    local text = pandoc.write(pandoc.Pandoc(blocks), 'plain', {
      columns = 72,
      wrap_text = 'auto',
    })
    local lines = rows(text)
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
    for i, part in ipairs(parts) do
      units[#units + 1] = {
        title = #parts > 1 and (title .. ' · ' .. i) or title,
        lines = part,
      }
    end
    blocks = {}
    has_body = false
  end
  local function contains_heading(block)
    if block.t == 'Header' then
      return true
    end
    if block.t == 'Div' then
      for _, child in ipairs(block.content) do
        if contains_heading(child) then
          return true
        end
      end
    end
    return false
  end
  local seen_heading = false
  local function visit(items)
    for _, block in ipairs(items) do
      if block.t == 'Div' and contains_heading(block) then
        visit(block.content)
      elseif block.t == 'Header' then
        -- A caption nested in a heading is still retained in reference text,
        -- but is not part of the chapter's navigation label.
        local label = block:walk({
          Span = function(span)
            if span.classes:includes('caption') then
              return {}
            end
          end,
        })
        local heading = clean(pandoc.utils.stringify(label.content))
        if heading ~= '' then
          if not seen_heading then
            title = 'Front matter'
          end
          flush()
          seen_heading = true
          title = heading
        end
        blocks[#blocks + 1] = block
      else
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
  return pandoc.json.encode(units)
end
